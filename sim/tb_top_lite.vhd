-------------------------------------------------------------------------------
-- tb_top_lite.vhd
--
-- Alternative behavioural testbench for the GRISC ASIP.  Functionally
-- equivalent to tb_top.vhd (same boundary stimulus, same resulting
-- waveforms on the wcfg-tracked signals: state, pc_sig, opcode, charSend,
-- charRec, fb_*, vga_*) but rewritten so that Vivado's xsim does NOT crash
-- on Windows.
--
-- Why the original tb_top.vhd can crash xsim
-- ------------------------------------------
-- 1. The instruction ROM (irMem.vhd) and data RAM (dMem.vhd) declare their
--    storage as a *signal* (`signal mem : mem_t`) sized 16384 x 32 b and
--    32768 x 16 b respectively. xsim allocates per-element waveform tracking
--    for every signal in scope. With ~1.05 Mbits of state plus the wcfg
--    referencing deep DUT hierarchy, the .wdb file balloons to multiple GB
--    over the 200 us run and exhausts available RAM / page file.
-- 2. The original tb runs for 200 us at 125 MHz (25_000 cycles tracked).
--    The 25 MHz pixel-clock domain runs constantly inside that window and
--    every signal in the VGA pipeline toggles thousands of times.
-- 3. `std.env.stop` does not terminate xsim - it just halts the kernel,
--    leaving the giant WDB resident in memory.  On Windows that often
--    presents as the GUI hanging or the OOM-killer taking the whole IDE.
-- 4. The original tx_listener uses unbounded `wait until RXD = '0'`/`= '1'`
--    statements; if the design hangs in reset, the testbench hangs too,
--    leaving xsim chewing memory until the user force-quits.
--
-- What this lite testbench does differently
-- -----------------------------------------
-- * Uses a *counted* clock (CLK_CYCLES) so the simulation has a hard
--   upper bound and naturally terminates even if `finish` is not honoured.
-- * Calls `std.env.finish` (not `stop`) to fully exit the simulator process.
-- * Default run length is 50 us (enough to capture full debounce -> reset
--   release, the "hello_world" TX burst, and a couple of host bytes); raise
--   STOP_AT_US to extend.
-- * Bounded `wait until ... for` calls in the UART listener prevent
--   deadlocks if the design ever stops toggling RXD.
-- * Emits the same console trace ([TX] 0x.. and [RX] driving 0x..) so the
--   simulation log is interchangeable with tb_top.vhd's.
--
-- Recommended xsim run-time settings (in Vivado Tcl console):
--   set_property -name {xsim.simulate.runtime}        -value {50us} \
--                -objects [get_filesets sim_1]
--   set_property -name {xsim.simulate.log_all_signals} -value {false} \
--                -objects [get_filesets sim_1]
-- and DO NOT add /tb_top_lite/dut/u_dm/mem or /tb_top_lite/dut/u_ir/mem to
-- the wave window - those are the BRAM models and tracking them is the
-- single biggest WDB amplifier.
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;
use STD.ENV.ALL;
use work.regs_pkg.all;

entity tb_top_lite is
    generic (
        TEXT_COE   : string  := "text.coe";
        DATA_COE   : string  := "data.coe";
        STOP_AT_US : integer := 50            -- simulation watchdog (us)
    );
end tb_top_lite;

architecture sim of tb_top_lite is
    --------------------------------------------------------------------
    -- Clock + UART parameters
    --------------------------------------------------------------------
    constant SYS_HZ_TB : integer := 125_000_000;
    constant BAUD_TB   : integer := 5_000_000;     -- fast UART for sim
    constant CLK_PER   : time    := 8 ns;          -- 125 MHz
    constant BIT_PER   : time    := (1 sec) / BAUD_TB;

    -- Hard upper bound on number of clock edges (ceil(STOP_AT_US * 1us / CLK_PER))
    constant CLK_CYCLES : integer := (STOP_AT_US * 1_000) / 8 + 4;

    --------------------------------------------------------------------
    -- DUT boundary signals
    --------------------------------------------------------------------
    signal tb_clk : std_logic := '0';
    signal btn_0  : std_logic := '1';

    signal TXD    : std_logic := '1';                -- host -> FPGA
    signal RXD    : std_logic;                       -- FPGA -> host
    signal RTS    : std_logic := '0';
    signal CTS    : std_logic := '0';                -- input to DUT

    signal vga_r  : std_logic_vector(4 downto 0);
    signal vga_g  : std_logic_vector(5 downto 0);
    signal vga_b  : std_logic_vector(4 downto 0);
    signal vga_hs : std_logic;
    signal vga_vs : std_logic;

    -- Termination flag set by the watchdog so all stimulus processes can
    -- bail out cleanly before std.env.finish is called.
    signal sim_done : boolean := false;

    --------------------------------------------------------------------
    -- Reference-named monitor signals (see tb_top.vhd for the rationale).
    --------------------------------------------------------------------
    signal pc_sig_view : unsigned(15 downto 0);
    signal ir_view     : std_logic_vector(31 downto 0);
    signal reg_view    : reg_array_t;

    signal pc          : std_logic_vector(13 downto 0);
    signal opcode      : std_logic_vector(4 downto 0);
    signal imm_arg     : std_logic_vector(15 downto 0);

    signal reg1addr    : std_logic_vector(4 downto 0);
    signal reg2addr    : std_logic_vector(4 downto 0);
    signal reg3addr    : std_logic_vector(4 downto 0);
    signal reg1data    : std_logic_vector(15 downto 0);
    signal reg2data    : std_logic_vector(15 downto 0);
    signal reg3data    : std_logic_vector(15 downto 0);

    signal controls_0_wr_enR1 : std_logic;

    signal newChar     : std_logic;
    signal charSend    : std_logic_vector(7 downto 0);
    signal charRec     : std_logic_vector(7 downto 0);

    signal fbWr_en     : std_logic;
    signal fbAddr1     : std_logic_vector(11 downto 0);
    signal fbDin1      : std_logic_vector(15 downto 0);
    signal fbDout1     : std_logic_vector(15 downto 0);

    signal tb_vga_r    : std_logic_vector(4 downto 0);
    signal tb_vga_g    : std_logic_vector(5 downto 0);
    signal tb_vga_b    : std_logic_vector(4 downto 0);

    --------------------------------------------------------------------
    -- Helper: hex nibble character
    --------------------------------------------------------------------
    function nibble2hex(n : integer) return character is
        constant LUT : string(1 to 16) := "0123456789ABCDEF";
    begin
        return LUT(n + 1);
    end function;

    function byte2hex(b : std_logic_vector(7 downto 0)) return string is
        variable r : string(1 to 2);
    begin
        r(1) := nibble2hex(to_integer(unsigned(b(7 downto 4))));
        r(2) := nibble2hex(to_integer(unsigned(b(3 downto 0))));
        return r;
    end function;
begin
    --------------------------------------------------------------------
    -- DUT
    --------------------------------------------------------------------
    dut : entity work.uproc_top_level
        generic map (
            SYS_HZ   => SYS_HZ_TB,
            BAUD     => BAUD_TB,
            PIX_DIV  => 5,
            TEXT_COE => TEXT_COE,
            DATA_COE => DATA_COE
        )
        port map (
            clk    => tb_clk,
            btn_0  => btn_0,
            TXD    => TXD,
            RXD    => RXD,
            RTS    => RTS,
            CTS    => CTS,
            vga_r  => vga_r,
            vga_g  => vga_g,
            vga_b  => vga_b,
            vga_hs => vga_hs,
            vga_vs => vga_vs
        );

    --------------------------------------------------------------------
    -- VHDL-2008 external-name views into DUT internals (lab-reference
    -- waveform names without changing any synthesisable code).
    --------------------------------------------------------------------
    pc_sig_view <= << signal .tb_top_lite.dut.u_ctrl.pc_sig : unsigned(15 downto 0) >>;
    ir_view     <= << signal .tb_top_lite.dut.u_ctrl.ir     : std_logic_vector(31 downto 0) >>;
    reg_view    <= << signal .tb_top_lite.dut.u_regs.mem    : reg_array_t >>;

    pc       <= std_logic_vector(pc_sig_view(13 downto 0));
    opcode   <= ir_view(31 downto 27);
    imm_arg  <= ir_view(16 downto  1);

    reg1addr <= ir_view(26 downto 22);
    reg2addr <= ir_view(21 downto 17);
    reg3addr <= ir_view(16 downto 12);
    reg1data <= reg_view(to_integer(unsigned(reg1addr)));
    reg2data <= reg_view(to_integer(unsigned(reg2addr)));
    reg3data <= reg_view(to_integer(unsigned(reg3addr)));

    controls_0_wr_enR1 <= << signal .tb_top_lite.dut.u_ctrl.wr_enR1 : std_logic >>;
    newChar  <= << signal .tb_top_lite.dut.u_newChar  : std_logic >>;
    charSend <= << signal .tb_top_lite.dut.u_charSend : std_logic_vector(7 downto 0) >>;
    charRec  <= << signal .tb_top_lite.dut.u_charRec  : std_logic_vector(7 downto 0) >>;
    fbWr_en  <= << signal .tb_top_lite.dut.fb_we      : std_logic >>;
    fbAddr1  <= << signal .tb_top_lite.dut.fb_addr1   : std_logic_vector(11 downto 0) >>;
    fbDin1   <= << signal .tb_top_lite.dut.fb_dout1   : std_logic_vector(15 downto 0) >>;
    fbDout1  <= << signal .tb_top_lite.dut.fb_din     : std_logic_vector(15 downto 0) >>;

    tb_vga_r <= vga_r;
    tb_vga_g <= vga_g;
    tb_vga_b <= vga_b;

    --------------------------------------------------------------------
    -- Counted 125 MHz clock - terminates after CLK_CYCLES toggles so the
    -- simulator naturally drains even if std.env.finish is ignored.
    --------------------------------------------------------------------
    clk_gen : process
    begin
        for i in 0 to CLK_CYCLES loop
            tb_clk <= '0';
            wait for CLK_PER / 2;
            tb_clk <= '1';
            wait for CLK_PER / 2;
            exit when sim_done;
        end loop;
        wait;
    end process;

    --------------------------------------------------------------------
    -- Active-high reset pulse on btn_0 (1 us, same as tb_top.vhd)
    --------------------------------------------------------------------
    rst_gen : process
    begin
        btn_0 <= '1';
        wait for 1 us;
        btn_0 <= '0';
        wait;
    end process;

    --------------------------------------------------------------------
    -- Passive UART receiver - bounded waits prevent deadlock.
    --------------------------------------------------------------------
    tx_listener : process
        variable l       : line;
        variable d       : std_logic_vector(7 downto 0);
        variable timed_out : boolean;
    begin
        -- Wait for the line to settle high after reset (bounded).
        if RXD /= '1' then
            wait until RXD = '1' for 5 us;
        end if;

        loop
            exit when sim_done;

            -- Wait for start bit, but with a long bounded timeout so we
            -- never block the simulator forever.
            wait until RXD = '0' for STOP_AT_US * 1 us;
            timed_out := (RXD /= '0');
            exit when timed_out or sim_done;

            wait for BIT_PER + BIT_PER / 2;           -- centre of bit 0
            for i in 0 to 7 loop
                d(i) := RXD;
                wait for BIT_PER;
            end loop;
            wait for BIT_PER / 2;                     -- stop bit centre

            write(l, string'("[TX] 0x"));
            write(l, byte2hex(d));
            if to_integer(unsigned(d)) >= 32 and to_integer(unsigned(d)) < 127 then
                write(l, string'("  '" & character'val(to_integer(unsigned(d))) & "'"));
            end if;
            writeline(output, l);

            if RXD /= '1' then
                wait until RXD = '1' for 5 us;
            end if;
        end loop;
        wait;
    end process;

    --------------------------------------------------------------------
    -- Active UART driver - sends two bytes from the host into TXD so the
    -- recv -> wpix loop can be observed in the waveform.
    --------------------------------------------------------------------
    rx_driver : process
        procedure send_byte (b : std_logic_vector(7 downto 0)) is
            variable l : line;
        begin
            write(l, string'("[RX] driving 0x"));
            write(l, byte2hex(b));
            writeline(output, l);
            TXD <= '0';                               -- start bit
            wait for BIT_PER;
            for i in 0 to 7 loop
                TXD <= b(i);
                wait for BIT_PER;
            end loop;
            TXD <= '1';                               -- stop bit
            wait for BIT_PER;
        end procedure;
    begin
        TXD <= '1';
        wait for 35 us;                               -- let TX finish "hello_world"
        if sim_done then wait; end if;
        send_byte(x"41");                             -- 'A'
        wait for 5 us;
        if sim_done then wait; end if;
        send_byte(x"5A");                             -- 'Z'
        wait;
    end process;

    --------------------------------------------------------------------
    -- Simulation watchdog - flips sim_done so every other process exits
    -- cleanly, then calls std.env.finish to fully terminate xsim.
    --------------------------------------------------------------------
    watchdog : process
    begin
        wait for STOP_AT_US * 1 us;
        report "tb_top_lite: watchdog reached " & integer'image(STOP_AT_US) &
               " us, ending simulation." severity note;
        sim_done <= true;
        wait for 100 ns;          -- give other processes a chance to drain
        finish;                   -- std.env.finish - true xsim termination
    end process;
end sim;
