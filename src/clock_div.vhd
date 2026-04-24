-------------------------------------------------------------------------------
-- clock_div.vhd
--
-- Generic clock-enable generator. Asserts en for one clk period every
-- DIV cycles, so the downstream block effectively runs at clk_freq / DIV.
--
-- For Lab 5 on Zybo Z7-10 (125 MHz):
--   * UART bit-rate enable: DIV = 1085 -> ~115200 Hz
--   * CPU clock-enable    : DIV = 1    -> full speed (default)
-- For a 100 MHz board, use DIV = 868 for 115200 Hz.
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity clock_div is
    Generic (
        DIV : integer := 1
    );
    Port (
        clk : in  std_logic;
        rst : in  std_logic;
        en  : out std_logic
    );
end clock_div;

architecture Behavioral of clock_div is
    signal cnt : integer range 0 to DIV := 0;
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                cnt <= 0;
            elsif DIV <= 1 then
                cnt <= 0;
            elsif cnt = DIV - 1 then
                cnt <= 0;
            else
                cnt <= cnt + 1;
            end if;
        end if;
    end process;

    en <= '1' when (DIV <= 1) or (cnt = 0) else '0';
end Behavioral;
