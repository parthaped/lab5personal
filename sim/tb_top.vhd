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
-- Waveform aliases (sig_*) mirror the names used in the Lab 5 reference
-- waveform:
--     ps               <- dut.u_ctrl.state           (present state)
--     pc[13:0]         <- dut.u_ctrl.pc_sig          (program counter)
--     opcode[4:0]      <- dut.u_ctrl.opcode          (top-5 of IR)
--     imm_arg[15:0]    <- dut.u_ctrl.imm16           (extracted immediate)
--     reg1addr / reg2addr            <- rID1, rID2
--     controls_0_wr_enR1             <- wr_en1
--     reg1data / reg2data / reg3data <- regrD1, regrD2, regs(3)
--     charSend / charRec / newChar   <- u_charSend, u_charRec, u_newChar
--     fbWr_en / fbAddr1 / fbDout1 / fbDin1
--     tb_vga_r / tb_vga_g / tb_vga_b
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;

entity tb_top is
end tb_top;

architecture sim of tb_top is
    --------------------------------------------------------------------
    -- Clock + UART parameters
    --------------------------------------------------------------------
    constant SYS_HZ_TB : integer := 125_000_000;
    constant BAUD_TB   : integer := 5_000_000;     -- fast UART for sim
    constant CLK_PER   : time    := 8 ns;
    constant BIT_PER   : time    := (1 sec) / BAUD_TB;

    constant TEXT_COE_PATH : string := "/Users/parthapediredla/lab5/coe/text.coe";
    constant DATA_COE_PATH : string := "/Users/parthapediredla/lab5/coe/data.coe";

    --------------------------------------------------------------------
    -- DUT boundary signals (names follow the lab manual reference BD)
    --------------------------------------------------------------------
    signal tb_clk : std_logic := '0';
    signal btn_0  : std_logic := '1';

    signal TXD    : std_logic := '1';                -- host -> FPGA
    signal RXD    : std_logic;                       -- FPGA -> host
    signal RTS    : std_logic := '0';
    signal CTS    : std_logic;

    signal vga_r  : std_logic_vector(4 downto 0);    -- tb_vga_r
    signal vga_g  : std_logic_vector(5 downto 0);    -- tb_vga_g
    signal vga_b  : std_logic_vector(4 downto 0);    -- tb_vga_b
    signal vga_hs : std_logic;
    signal vga_vs : std_logic;

begin
    --------------------------------------------------------------------
    -- DUT (structural top, identical interface to the BD wrapper)
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
