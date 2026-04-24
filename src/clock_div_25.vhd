-------------------------------------------------------------------------------
-- clock_div_25.vhd
--
-- 25 MHz clock-enable from the system clock. Defaults to /5 (125 MHz Zybo);
-- override DIV at instantiation if your board uses a different system rate
-- (e.g. DIV = 4 for a 100 MHz Basys 3).
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity clock_div_25 is
    Generic (
        DIV : integer := 5
    );
    Port (
        clk : in  std_logic;
        rst : in  std_logic;
        en  : out std_logic
    );
end clock_div_25;

architecture Behavioral of clock_div_25 is
    signal cnt : integer range 0 to DIV := 0;
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                cnt <= 0;
            elsif cnt = DIV - 1 then
                cnt <= 0;
            else
                cnt <= cnt + 1;
            end if;
        end if;
    end process;

    en <= '1' when cnt = 0 else '0';
end Behavioral;
