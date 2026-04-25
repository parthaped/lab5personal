-------------------------------------------------------------------------------
-- tb_top_lite.vhd
--
-- Crash-safe behavioural testbench for the GRISC ASIP.
--
-- Design choices:
--   * Counted 125 MHz clock so the simulation has a hard upper bound and
--     terminates naturally even if `std.env.finish` is ignored.
--   * `std.env.finish` (not `stop`) so xsim cleanly tears down its kernel.
--   * Bounded `wait until ... for` calls in the UART listener prevent
--     deadlocks if the design ever stops toggling RXD.
--   * Default run length: 50 us (long enough for the "hello_world" TX
--     burst plus a couple of host bytes); raise STOP_AT_US to extend.
--   * NO VHDL-2008 external names.  Vivado's xelab is known to segfault
--     on Windows when external names cross VHDL-2008 / VHDL-93 boundaries
--     (which we have because module-reference IPI cells must be -93).
--     The waveform configuration file (sim/tb_top_lite.wcfg) instead
--     references DUT internal signals via direct hierarchy paths
--     (e.g. /tb_top_lite/dut/u_ctrl/pc_sig) with display aliases that
--     match the lab manual reference waveform.
--
-- DO NOT add /tb_top_lite/dut/u_dm/mem or /tb_top_lite/dut/u_ir/mem to
-- the wave window - those are the BRAM models with ~1 Mbit of state and
-- tracking them is what crashes xsim with OOM.
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;
use STD.ENV.ALL;

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

    -- Hard upper bound on number of clock edges.
    constant CLK_CYCLES : integer := (STOP_AT_US * 1_000) / 8 + 4;

    --------------------------------------------------------------------
    -- DUT boundary signals (just observe; the wcfg picks the rest of
    -- the names up directly from the DUT hierarchy)
    --------------------------------------------------------------------
    signal tb_clk : std_logic := '0';
    signal btn_0  : std_logic := '1';

    signal TXD    : std_logic := '1';                -- host -> FPGA
    signal RXD    : std_logic;                       -- FPGA -> host
    signal RTS    : std_logic;                       -- FPGA OUTPUT, tri-stated 'Z' inside DUT
    signal CTS    : std_logic;                       -- FPGA OUTPUT, tri-stated 'Z' inside DUT

    signal vga_r  : std_logic_vector(4 downto 0);
    signal vga_g  : std_logic_vector(5 downto 0);
    signal vga_b  : std_logic_vector(4 downto 0);
    signal vga_hs : std_logic;
    signal vga_vs : std_logic;

    -- Termination flag set by the watchdog so all stimulus processes can
    -- bail out cleanly before std.env.finish is called.
    signal sim_done : boolean := false;

    --------------------------------------------------------------------
    -- Helpers
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
    -- Active-high reset pulse on btn_0 (1 us)
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
        variable l         : line;
        variable d         : std_logic_vector(7 downto 0);
        variable timed_out : boolean;
    begin
        if RXD /= '1' then
            wait until RXD = '1' for 5 us;
        end if;

        loop
            exit when sim_done;

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
