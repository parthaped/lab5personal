-------------------------------------------------------------------------------
-- regs.vhd
--
-- True dual-port general-purpose register file (32 x 16-bit).
--   * Writes are synchronous, gated by en.
--   * Reads are asynchronous (combinational) so controls can rely on the data
--     being valid one cycle after re-pointing rID*.
--   * Register 0 ($zero) always reads as zero. Writes to index 0 are ignored.
--   * rst zeroes the whole file.
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity regs is
    Port (
        clk     : in  std_logic;
        en      : in  std_logic;
        rst     : in  std_logic;
        id1     : in  std_logic_vector(4 downto 0);
        id2     : in  std_logic_vector(4 downto 0);
        wr_en1  : in  std_logic;
        wr_en2  : in  std_logic;
        din1    : in  std_logic_vector(15 downto 0);
        din2    : in  std_logic_vector(15 downto 0);
        dout1   : out std_logic_vector(15 downto 0);
        dout2   : out std_logic_vector(15 downto 0)
    );
end regs;

architecture Behavioral of regs is
    type reg_array_t is array (0 to 31) of std_logic_vector(15 downto 0);
    signal mem : reg_array_t := (others => (others => '0'));
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                mem <= (others => (others => '0'));
            elsif en = '1' then
                if wr_en1 = '1' and id1 /= "00000" then
                    mem(to_integer(unsigned(id1))) <= din1;
                end if;
                if wr_en2 = '1' and id2 /= "00000" then
                    mem(to_integer(unsigned(id2))) <= din2;
                end if;
            end if;
            mem(0) <= (others => '0');
        end if;
    end process;

    dout1 <= mem(to_integer(unsigned(id1)));
    dout2 <= mem(to_integer(unsigned(id2)));
end Behavioral;
