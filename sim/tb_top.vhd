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

    signal clk    : std_logic := '0';
    signal btn    : std_logic := '1';
    signal rx     : std_logic := '1';
    signal tx     : std_logic;
    signal vga_r  : std_logic_vector(3 downto 0);
    signal vga_g  : std_logic_vector(3 downto 0);
    signal vga_b  : std_logic_vector(3 downto 0);
    signal vga_hs : std_logic;
    signal vga_vs : std_logic;

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
            clk => clk, btn => btn,
            rx => rx, tx => tx,
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
        btn <= '1';
        wait for 1 us;
        btn <= '0';
        wait;
    end process;

    --------------------------------------------------------------------
    -- TX listener: prints every byte the FPGA UART transmits.
    --------------------------------------------------------------------
    tx_listener : process
        variable l : line;
        variable d : std_logic_vector(7 downto 0);
    begin
        -- Make sure tx is high (idle) before looking for a start bit.
        if tx /= '1' then
            wait until tx = '1';
        end if;
        loop
            wait until tx = '0';
            wait for BIT_PER + BIT_PER / 2;
            for i in 0 to 7 loop
                d(i) := tx;
                wait for BIT_PER;
            end loop;
            wait for BIT_PER / 2;

            write(l, string'("[TX] 0x"));
            hwrite(l, d);
            if d /= x"00" and to_integer(unsigned(d)) >= 32 then
                write(l, string'("  '" & character'val(to_integer(unsigned(d))) & "'"));
            end if;
            writeline(output, l);

            -- ensure we resync between bytes
            if tx /= '1' then
                wait until tx = '1';
            end if;
        end loop;
    end process;

    --------------------------------------------------------------------
    -- RX driver: after a delay, sends two bytes so we can see recv/wpix.
    --------------------------------------------------------------------
    rx_driver : process
        procedure send_byte (b : std_logic_vector(7 downto 0)) is
            variable l : line;
        begin
            write(l, string'("[RX] driving 0x"));
            hwrite(l, b);
            writeline(output, l);
            rx <= '0';                          -- start bit
            wait for BIT_PER;
            for i in 0 to 7 loop
                rx <= b(i);
                wait for BIT_PER;
            end loop;
            rx <= '1';                          -- stop bit
            wait for BIT_PER;
        end procedure;
    begin
        rx <= '1';
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
