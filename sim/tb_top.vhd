-------------------------------------------------------------------------------
-- tb_top.vhd
--
-- Behavioral testbench for the GRISC ASIP, modelled on the Lab 5 reference
-- testbench.  Stimulus pattern:
--   * generate the 125 MHz system clock (tb_clk)
--   * hold btn_0 (active-high reset) high for 1 us, then release
--   * passively listen on RXD and print every byte the FPGA UART transmits
--   * after the design finishes printing "hello_world", drive a couple of
--     bytes onto TXD so the recv -> wpix loop can be observed
--
-- Waveform signal names match the Lab 5 reference waveform exactly so the
-- xsim wave window reads identically to the lecture slide.  The mapping
-- (all driven by VHDL-2008 external names from inside the DUT - no
-- synthesisable code is touched):
--     ps               <- dut.u_ctrl.state                 (present state)
--     pc[13:0]         <- dut.u_ctrl.pc_sig(13:0)          (program counter)
--     opcode[4:0]      <- dut.u_ctrl.ir(31:27)             (top-5 of IR)
--     imm_arg[15:0]    <- dut.u_ctrl.ir(16:1)              (extracted immediate)
--     reg1addr/2/3     <- ir(26:22), ir(21:17), ir(16:12)  (instr fields)
--     reg1data/2/3     <- dut.u_regs.mem(reg{1,2,3}addr)   (live reg values)
--     controls_0_wr_enR1  <- dut.u_ctrl.wr_enR1
--     charSend / charRec / newChar  <- dut.u_charSend / charRec / newChar
--     fbWr_en / fbAddr1 / fbDout1 / fbDin1  <- dut.fb_*
--     tb_vga_r / tb_vga_g / tb_vga_b        <- vga_r / vga_g / vga_b
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;
use work.regs_pkg.all;

entity tb_top is
    -- COE paths come from the simulator at elaboration time so the testbench
    -- is portable between macOS / Linux / Windows.  create_project.tcl sets
    -- both generics on the sim_1 fileset to absolute paths computed from
    -- $proj_dir, so no editing of this file is required when the project is
    -- cloned to a new machine.  GHDL invocations override them with -g.
    generic (
        TEXT_COE : string := "text.coe";
        DATA_COE : string := "data.coe"
    );
end tb_top;

architecture sim of tb_top is
    --------------------------------------------------------------------
    -- Clock + UART parameters
    --------------------------------------------------------------------
    constant SYS_HZ_TB : integer := 125_000_000;
    constant BAUD_TB   : integer := 5_000_000;     -- fast UART for sim
    constant CLK_PER   : time    := 8 ns;
    constant BIT_PER   : time    := (1 sec) / BAUD_TB;

    --------------------------------------------------------------------
    -- DUT boundary signals (names follow the lab manual reference BD)
    --------------------------------------------------------------------
    signal tb_clk : std_logic := '0';
    signal btn_0  : std_logic := '1';

    signal TXD    : std_logic := '1';                -- host -> FPGA
    signal RXD    : std_logic;                       -- FPGA -> host
    signal RTS    : std_logic;                       -- FPGA OUTPUT, tri-stated 'Z' inside DUT
    signal CTS    : std_logic;                       -- FPGA OUTPUT, tri-stated 'Z' inside DUT

    signal vga_r  : std_logic_vector(4 downto 0);    -- tb_vga_r
    signal vga_g  : std_logic_vector(5 downto 0);    -- tb_vga_g
    signal vga_b  : std_logic_vector(4 downto 0);    -- tb_vga_b
    signal vga_hs : std_logic;
    signal vga_vs : std_logic;

    --------------------------------------------------------------------
    -- Reference-named monitor signals.  These are tb-level mirrors of
    -- DUT internals exposed via VHDL-2008 external names so the wcfg can
    -- display the *exact* signal names used in the lab manual reference
    -- waveform (no hierarchy paths, no aliasing).
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

begin
    --------------------------------------------------------------------
    -- DUT (structural top, identical interface to the BD wrapper)
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
    -- VHDL-2008 external-name views into DUT internals.
    -- These let the waveform expose lab-reference names without changing
    -- any of the synthesisable code.
    --------------------------------------------------------------------
    pc_sig_view <= << signal .tb_top.dut.u_ctrl.pc_sig : unsigned(15 downto 0) >>;
    ir_view     <= << signal .tb_top.dut.u_ctrl.ir     : std_logic_vector(31 downto 0) >>;
    reg_view    <= << signal .tb_top.dut.u_regs.mem    : reg_array_t >>;

    pc       <= std_logic_vector(pc_sig_view(13 downto 0));
    opcode   <= ir_view(31 downto 27);
    imm_arg  <= ir_view(16 downto  1);

    -- GRISC instruction format: [op(5)][reg1(5)][reg2(5)][reg3(5)][...]
    reg1addr <= ir_view(26 downto 22);     -- destination
    reg2addr <= ir_view(21 downto 17);     -- source 1
    reg3addr <= ir_view(16 downto 12);     -- source 2 / unused for I/J types
    reg1data <= reg_view(to_integer(unsigned(reg1addr)));
    reg2data <= reg_view(to_integer(unsigned(reg2addr)));
    reg3data <= reg_view(to_integer(unsigned(reg3addr)));

    -- Mirror BD-style net names so the wcfg signal list matches the
    -- lecture screenshot row-for-row.
    controls_0_wr_enR1 <= << signal .tb_top.dut.u_ctrl.wr_enR1 : std_logic >>;
    newChar  <= << signal .tb_top.dut.u_newChar  : std_logic >>;
    charSend <= << signal .tb_top.dut.u_charSend : std_logic_vector(7 downto 0) >>;
    charRec  <= << signal .tb_top.dut.u_charRec  : std_logic_vector(7 downto 0) >>;
    fbWr_en  <= << signal .tb_top.dut.fb_we      : std_logic >>;
    fbAddr1  <= << signal .tb_top.dut.fb_addr1   : std_logic_vector(11 downto 0) >>;
    fbDin1   <= << signal .tb_top.dut.fb_dout1   : std_logic_vector(15 downto 0) >>; -- read INTO controls
    fbDout1  <= << signal .tb_top.dut.fb_din     : std_logic_vector(15 downto 0) >>; -- write OUT from controls

    tb_vga_r <= vga_r;
    tb_vga_g <= vga_g;
    tb_vga_b <= vga_b;

    --------------------------------------------------------------------
    -- 125 MHz clock
    --------------------------------------------------------------------
    clk_gen : process
    begin
        tb_clk <= '0';
        wait for CLK_PER / 2;
        tb_clk <= '1';
        wait for CLK_PER / 2;
    end process;

    --------------------------------------------------------------------
    -- Active-high reset pulse on btn_0
    --------------------------------------------------------------------
    rst_gen : process
    begin
        btn_0 <= '1';
        wait for 1 us;
        btn_0 <= '0';
        wait;
    end process;

    --------------------------------------------------------------------
    -- Passive UART receiver: prints every byte the FPGA UART transmits
    -- (the FPGA TX pin is RXD from the host's perspective).
    --------------------------------------------------------------------
    tx_listener : process
        variable l : line;
        variable d : std_logic_vector(7 downto 0);
    begin
        if RXD /= '1' then
            wait until RXD = '1';
        end if;
        loop
            wait until RXD = '0';                     -- start bit
            wait for BIT_PER + BIT_PER / 2;           -- centre of bit 0
            for i in 0 to 7 loop
                d(i) := RXD;
                wait for BIT_PER;
            end loop;
            wait for BIT_PER / 2;                     -- stop bit centre

            write(l, string'("[TX] 0x"));
            hwrite(l, d);
            if d /= x"00" and to_integer(unsigned(d)) >= 32 then
                write(l, string'("  '" & character'val(to_integer(unsigned(d))) & "'"));
            end if;
            writeline(output, l);

            if RXD /= '1' then
                wait until RXD = '1';
            end if;
        end loop;
    end process;

    --------------------------------------------------------------------
    -- Active UART driver: sends two bytes from the host into TXD so we
    -- can watch the recv -> wpix loop.
    --------------------------------------------------------------------
    rx_driver : process
        procedure send_byte (b : std_logic_vector(7 downto 0)) is
            variable l : line;
        begin
            write(l, string'("[RX] driving 0x"));
            hwrite(l, b);
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
        send_byte(x"41");                             -- 'A'
        wait for 40 us;
        send_byte(x"5A");                             -- 'Z'
        wait;
    end process;

    --------------------------------------------------------------------
    -- Simulation watchdog
    --------------------------------------------------------------------
    watchdog : process
    begin
        wait for 200 us;
        report "tb_top: simulation watchdog reached, ending." severity note;
        std.env.stop;
    end process;
end sim;
