-------------------------------------------------------------------------------
-- tb_top.vhd
--
-- End-to-end behavioral testbench for the GRISC ASIP (Lab 5).
--
-- The simulation:
--   * generates a 125 MHz system clock
--   * holds btn (reset) for 1 us, then releases
--   * captures every byte the design transmits on tx and reports it
--   * after a short delay, drives a few bytes into rx (host -> FPGA UART) so
--     the recv -> wpix loop can be observed in the waveform
--
-- To get to "Hello_World" exiting on tx in reasonable simulation time we
-- override BAUD to 5_000_000 and SYS_HZ to 125 MHz so UART_DIV = 25 cycles
-- per bit. This keeps the visible behaviour identical but lets the simulator
-- finish in seconds instead of minutes.
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;

entity tb_top is
end tb_top;

architecture sim of tb_top is
    constant SYS_HZ_TB : integer := 125000000;
    constant BAUD_TB   : integer := 5000000;     -- fast UART for sim
    constant CLK_PER   : time    := 8 ns;
    constant BIT_PER   : time    := (1 sec) / BAUD_TB;

    constant TEXT_COE_PATH : string := "/Users/parthapediredla/lab5/coe/text.coe";
    constant DATA_COE_PATH : string := "/Users/parthapediredla/lab5/coe/data.coe";

    -- Port names match the lab manual reference BD (Pmod silkscreen).
    --   TXD = host -> FPGA UART RX  (FPGA INPUT)
    --   RXD = FPGA UART TX -> host  (FPGA OUTPUT)
    --   CTS = FPGA OUTPUT (tied low by the design)
    --   RTS = FPGA INPUT  (ignored)
    signal clk    : std_logic := '0';
    signal btn_0  : std_logic := '1';
    signal TXD    : std_logic := '1';                       -- host -> FPGA
    signal RXD    : std_logic;                              -- FPGA -> host
    signal RTS    : std_logic := '0';
    signal CTS    : std_logic;
    signal vga_r  : std_logic_vector(4 downto 0);
    signal vga_g  : std_logic_vector(5 downto 0);
    signal vga_b  : std_logic_vector(4 downto 0);
    signal vga_hs : std_logic;
    signal vga_vs : std_logic;

    -- Convenience aliases for the waveform window: shows the same names you'd
    -- see in the lab manual (ps, pc, opcode, reg1addr, etc.). All of these
    -- live inside the DUT - VHDL-2008 external names give us a flat handle.
    -- Add these to your wave window: dut/u_ctrl/state, dut/irAddr, dut/u_regs/*
    -- (Vivado xsim hierarchy lets you drag any internal signal in directly.)

begin
    --------------------------------------------------------------------
    -- DUT
    --------------------------------------------------------------------
    dut : entity work.uproc_top_level
        generic map (
            SYS_HZ   => SYS_HZ_TB,
            BAUD     => BAUD_TB,
            PIX_DIV  => 5,
            TEXT_COE => TEXT_COE_PATH,
            DATA_COE => DATA_COE_PATH
        )
        port map (
            clk => clk, btn_0 => btn_0,
            TXD => TXD, RXD => RXD, CTS => CTS, RTS => RTS,
            vga_r => vga_r, vga_g => vga_g, vga_b => vga_b,
            vga_hs => vga_hs, vga_vs => vga_vs
        );

    --------------------------------------------------------------------
    -- Clock
    --------------------------------------------------------------------
    clk_gen : process
    begin
        clk <= '0';
        wait for CLK_PER / 2;
        clk <= '1';
        wait for CLK_PER / 2;
    end process;

    --------------------------------------------------------------------
    -- Reset
    --------------------------------------------------------------------
    rst_gen : process
    begin
        btn_0 <= '1';
        wait for 1 us;
        btn_0 <= '0';
        wait;
    end process;

    --------------------------------------------------------------------
    -- TX listener: prints every byte the FPGA UART transmits.
    -- The FPGA UART output appears on the RXD line.
    --------------------------------------------------------------------
    tx_listener : process
        variable l : line;
        variable d : std_logic_vector(7 downto 0);
    begin
        if RXD /= '1' then
            wait until RXD = '1';
        end if;
        loop
            wait until RXD = '0';
            wait for BIT_PER + BIT_PER / 2;
            for i in 0 to 7 loop
                d(i) := RXD;
                wait for BIT_PER;
            end loop;
            wait for BIT_PER / 2;

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
    -- RX driver: drives the host->FPGA line (TXD).
    --------------------------------------------------------------------
    rx_driver : process
        procedure send_byte (b : std_logic_vector(7 downto 0)) is
            variable l : line;
        begin
            write(l, string'("[RX] driving 0x"));
            hwrite(l, b);
            writeline(output, l);
            TXD <= '0';                         -- start bit
            wait for BIT_PER;
            for i in 0 to 7 loop
                TXD <= b(i);
                wait for BIT_PER;
            end loop;
            TXD <= '1';                         -- stop bit
            wait for BIT_PER;
        end procedure;
    begin
        TXD <= '1';
        wait for 35 us;                         -- let TX finish "hello_world"
        send_byte(x"41");                       -- 'A'
        wait for 40 us;
        send_byte(x"5A");                       -- 'Z'
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
