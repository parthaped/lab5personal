-------------------------------------------------------------------------------
-- pixel_pusher.vhd
--
-- Walks the 64x64 framebuffer in raster order and produces RGB565 colour data
-- to the VGA DAC. Anything outside the 64x64 image area is driven black.
--
--   pixel(15:11) -> R[4:0]
--   pixel(10:5)  -> G[5:0]
--   pixel(4:0)   -> B[4:0]
--
-- Address counter:
--   reset to 0 while VS sync pulse is active (vs='0'), increments by one
--   each pixel inside the 64x64 image window.
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity pixel_pusher is
    Port (
        clk    : in  std_logic;
        en     : in  std_logic;
        vs     : in  std_logic;
        pixel  : in  std_logic_vector(15 downto 0);
        hcount : in  std_logic_vector(9 downto 0);
        vcount : in  std_logic_vector(9 downto 0);
        vid    : in  std_logic;
        r      : out std_logic_vector(4 downto 0);
        g      : out std_logic_vector(5 downto 0);
        b      : out std_logic_vector(4 downto 0);
        addr   : out std_logic_vector(11 downto 0)
    );
end pixel_pusher;

architecture Behavioral of pixel_pusher is
    signal addr_cnt : unsigned(11 downto 0) := (others => '0');
    signal in_img   : std_logic;
begin
    in_img <= '1' when (unsigned(hcount) < 64 and unsigned(vcount) < 64) else '0';

    process(clk)
    begin
        if rising_edge(clk) then
            if en = '1' then
                if vs = '0' then
                    addr_cnt <= (others => '0');
                elsif in_img = '1' then
                    addr_cnt <= addr_cnt + 1;
                end if;
            end if;
        end if;
    end process;

    addr <= std_logic_vector(addr_cnt);

    process(clk)
    begin
        if rising_edge(clk) then
            if en = '1' then
                if vid = '1' and in_img = '1' then
                    r <= pixel(15 downto 11);
                    g <= pixel(10 downto 5);
                    b <= pixel(4 downto 0);
                else
                    r <= (others => '0');
                    g <= (others => '0');
                    b <= (others => '0');
                end if;
            end if;
        end if;
    end process;
end Behavioral;
