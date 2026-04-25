-------------------------------------------------------------------------------
-- uproc_top_level.vhd
--
-- GRISC ASIP top-level. Wires together:
--   * controls   - main FSM
--   * regs       - 32 x 16-bit dual-port register file
--   * my_alu     - 16-bit synchronous ALU
--   * framebuffer- 4096 x 16-bit dual-port video memory
--   * vga_ctrl   - 640x480 @ 60 Hz timing generator
--   * pixel_pusher - 16-bit RGB565 -> R/G/B + 12-bit framebuffer address
--   * uart       - 8N1 UART (driven by 115200 Hz enable)
--   * irMem      - 32 x 16384 instruction ROM (text.coe)
--   * dMem       - 16 x 32768 data RAM        (data.coe)
--   * clock_div  - CPU enable
--   * clock_div_25 - 25 MHz pixel-clock enable
--   * clock_div  (UART) - 115200 Hz bit-rate enable
--   * debounce   - reset button cleanup
--
-- Matches Figures 5.2 / 5.3 in the lab manual. Written as a flat structural
-- entity so it works in both behavioral simulation and IP Integrator (the BD
-- equivalent is auto-generated from this file by build_block_design.tcl).
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uproc_top_level is
    Generic (
        SYS_HZ   : integer := 125000000;   -- Zybo Z7-10 board clock
        BAUD     : integer := 115200;
        PIX_DIV  : integer := 5;            -- 125 MHz / 5 = 25 MHz
        TEXT_COE : string  := "text.coe";
        DATA_COE : string  := "data.coe"
    );
    Port (
        clk    : in  std_logic;
        btn    : in  std_logic;            -- active-high reset button

        -- UART. Port names match the Pmod silkscreen convention used in the
        -- Lab 5 BD: `tx` is the Pmod's TX line (FPGA INPUT, host -> FPGA),
        -- `rx` is the Pmod's RX line (FPGA OUTPUT, FPGA -> host).
        tx     : in  std_logic;
        rx     : out std_logic;

        -- Pmod VGA. We expose the full 5-6-5 channels straight out of
        -- pixel_pusher (matches the lab manual BD). The XDC connects only
        -- the top 4 bits of each channel to physical Pmod pins.
        vga_r  : out std_logic_vector(4 downto 0);
        vga_g  : out std_logic_vector(5 downto 0);
        vga_b  : out std_logic_vector(4 downto 0);
        vga_hs : out std_logic;
        vga_vs : out std_logic
    );
end uproc_top_level;

architecture Structural of uproc_top_level is
    -- Reset
    signal rst        : std_logic;

    -- Clock-enables
    signal cpu_en     : std_logic;
    signal pix_en     : std_logic;

    -- VGA
    signal hcount    : std_logic_vector(9 downto 0);
    signal vcount    : std_logic_vector(9 downto 0);
    signal vid       : std_logic;
    signal hs_int    : std_logic;
    signal vs_int    : std_logic;
    signal pp_addr   : std_logic_vector(11 downto 0);
    signal pp_r      : std_logic_vector(4 downto 0);
    signal pp_g      : std_logic_vector(5 downto 0);
    signal pp_b      : std_logic_vector(4 downto 0);

    -- Framebuffer
    signal fb_din    : std_logic_vector(15 downto 0);
    signal fb_dout1  : std_logic_vector(15 downto 0);
    signal fb_dout2  : std_logic_vector(15 downto 0);
    signal fb_addr1  : std_logic_vector(11 downto 0);
    signal fb_we     : std_logic;
    signal fb_rst    : std_logic;

    -- Register file
    signal rID1, rID2     : std_logic_vector(4 downto 0);
    signal regrD1, regrD2 : std_logic_vector(15 downto 0);
    signal regwD1, regwD2 : std_logic_vector(15 downto 0);
    signal wr_en1, wr_en2 : std_logic;

    -- ALU
    signal aluA, aluB    : std_logic_vector(15 downto 0);
    signal aluOp         : std_logic_vector(3 downto 0);
    signal aluResult     : std_logic_vector(15 downto 0);

    -- Memories
    signal irAddr        : std_logic_vector(13 downto 0);
    signal irWord        : std_logic_vector(31 downto 0);
    signal dAddr         : std_logic_vector(14 downto 0);
    signal d_we          : std_logic;
    signal dDin, dDout   : std_logic_vector(15 downto 0);

    -- UART
    signal u_send        : std_logic;
    signal u_ready       : std_logic;
    signal u_newChar     : std_logic;
    signal u_charSend    : std_logic_vector(7 downto 0);
    signal u_charRec     : std_logic_vector(7 downto 0);

    -- Compute UART divisor at elaboration time
    constant UART_DIV    : integer := SYS_HZ / BAUD;
begin
    ----------------------------------------------------------------------
    -- Reset and clock enables
    ----------------------------------------------------------------------
    u_dbn : entity work.debounce
        generic map (STABLE => 1250000)
        port map ( clk => clk, btn => btn, dbn => rst );

    u_ckcpu : entity work.clock_div
        generic map (DIV => 1)
        port map ( clk => clk, rst => rst, en => cpu_en );

    u_ck25 : entity work.clock_div_25
        generic map (DIV => PIX_DIV)
        port map ( clk => clk, rst => rst, en => pix_en );

    ----------------------------------------------------------------------
    -- CPU
    ----------------------------------------------------------------------
    u_ctrl : entity work.controls
        port map (
            clk => clk, en => cpu_en, rst => rst,
            rID1 => rID1, rID2 => rID2,
            wr_enR1 => wr_en1, wr_enR2 => wr_en2,
            regrD1 => regrD1, regrD2 => regrD2,
            regwD1 => regwD1, regwD2 => regwD2,
            fbRST => fb_rst,
            fbAddr1 => fb_addr1,
            fbDin1 => fb_dout1,           -- read data INTO controls
            fbDout1 => fb_din,            -- write data OUT to fb
            fbWr_en => fb_we,
            irAddr => irAddr, irWord => irWord,
            dAddr => dAddr, d_wr_en => d_we,
            dOut => dDin, dIn => dDout,
            aluA => aluA, aluB => aluB, aluOp => aluOp,
            aluResult => aluResult,
            ready => u_ready, newChar => u_newChar,
            send => u_send,
            charRec => u_charRec, charSend => u_charSend
        );

    u_regs : entity work.regs
        port map (
            clk => clk, en => cpu_en, rst => rst,
            id1 => rID1, id2 => rID2,
            wr_en1 => wr_en1, wr_en2 => wr_en2,
            din1 => regwD1, din2 => regwD2,
            dout1 => regrD1, dout2 => regrD2
        );

    u_alu : entity work.my_alu
        port map (
            clk => clk, en => cpu_en,
            A => aluA, B => aluB, opcode => aluOp,
            Y => aluResult
        );

    ----------------------------------------------------------------------
    -- Memory
    ----------------------------------------------------------------------
    u_ir : entity work.irMem
        generic map (COE_FILE => TEXT_COE)
        port map ( clk => clk, en => cpu_en, addr => irAddr, dout => irWord );

    u_dm : entity work.dMem
        generic map (COE_FILE => DATA_COE)
        port map (
            clk => clk, en => cpu_en, wr_en => d_we,
            addr => dAddr, din => dDin, dout => dDout
        );

    ----------------------------------------------------------------------
    -- Video
    ----------------------------------------------------------------------
    u_fb : entity work.framebuffer
        port map (
            clk => clk,
            en1 => cpu_en, en2 => pix_en,
            ld  => fb_rst,
            addr1 => fb_addr1, addr2 => pp_addr,
            wr_en1 => fb_we,
            din1 => fb_din,
            dout1 => fb_dout1,
            dout2 => fb_dout2
        );

    u_vga : entity work.vga_ctrl
        port map (
            clk => clk, en => pix_en,
            hcount => hcount, vcount => vcount,
            vid => vid, hs => hs_int, vs => vs_int
        );

    u_pp : entity work.pixel_pusher
        port map (
            clk => clk, en => pix_en, vs => vs_int,
            pixel => fb_dout2,
            hcount => hcount, vcount => vcount, vid => vid,
            r => pp_r, g => pp_g, b => pp_b,
            addr => pp_addr
        );

    vga_r  <= pp_r;
    vga_g  <= pp_g;
    vga_b  <= pp_b;
    vga_hs <= hs_int;
    vga_vs <= vs_int;

    ----------------------------------------------------------------------
    -- UART (counter-based bit timing)
    ----------------------------------------------------------------------
    -- Crossed UART wiring: external `tx` (Pmod TX, FPGA in) -> uart.rx
    --                       external `rx` (Pmod RX, FPGA out) <- uart.tx
    u_uart : entity work.uart
        generic map (CLKS_PER_BIT => UART_DIV)
        port map (
            clk => clk, rst => rst,
            send => u_send, charSend => u_charSend,
            ready => u_ready, newChar => u_newChar, charRec => u_charRec,
            tx => rx, rx => tx
        );
end Structural;
