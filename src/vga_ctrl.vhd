-------------------------------------------------------------------------------
-- vga_ctrl.vhd
--
-- 640x480 @ 60 Hz VGA timing generator clocked at 25 MHz (clk pixel rate).
-- Total line:  800 pixels (front porch 16, sync 96, back porch 48, active 640)
-- Total frame: 525 lines  (front porch 10, sync 2,  back porch 33, active 480)
--
-- The 64x64 image window is handled in pixel_pusher; this block keeps the
-- standard 640x480 active region so that any monitor can lock to the timing.
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity vga_ctrl is
    Port (
        clk    : in  std_logic;
        en     : in  std_logic;
        hcount : out std_logic_vector(9 downto 0);
        vcount : out std_logic_vector(9 downto 0);
        vid    : out std_logic;
        hs     : out std_logic;
        vs     : out std_logic
    );
end vga_ctrl;

architecture Behavioral of vga_ctrl is
    signal h_cnt : unsigned(9 downto 0) := (others => '0');
    signal v_cnt : unsigned(9 downto 0) := (others => '0');
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if en = '1' then
                if h_cnt = 799 then
                    h_cnt <= (others => '0');
                    if v_cnt = 524 then
                        v_cnt <= (others => '0');
                    else
                        v_cnt <= v_cnt + 1;
                    end if;
                else
                    h_cnt <= h_cnt + 1;
                end if;
            end if;
        end if;
    end process;

    hcount <= std_logic_vector(h_cnt);
    vcount <= std_logic_vector(v_cnt);

    vid <= '1' when (h_cnt < 640 and v_cnt < 480) else '0';
    hs  <= '0' when (h_cnt >= 656 and h_cnt < 752) else '1';
    vs  <= '0' when (v_cnt >= 490 and v_cnt < 492) else '1';
end Behavioral;
