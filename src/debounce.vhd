-------------------------------------------------------------------------------
-- debounce.vhd
--
-- Simple synchronous button debouncer. Holds the input stable for STABLE
-- samples before propagating the new value. With clk = 125 MHz and
-- STABLE = 1_250_000 the response time is roughly 10 ms, well below human
-- perception but well above mechanical bounce on Digilent push-buttons.
--
-- The output is high while the button is pressed; we use this directly as
-- the active-high reset for the rest of the system.
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity debounce is
    Generic (
        STABLE : integer := 1250000
    );
    Port (
        clk : in  std_logic;
        btn : in  std_logic;
        dbn : out std_logic
    );
end debounce;

architecture Behavioral of debounce is
    signal sync0, sync1 : std_logic := '0';
    signal cnt          : integer range 0 to STABLE := 0;
    signal stable_val   : std_logic := '0';
begin
    process(clk)
    begin
        if rising_edge(clk) then
            sync0 <= btn;
            sync1 <= sync0;

            if sync1 /= stable_val then
                if cnt = STABLE - 1 then
                    stable_val <= sync1;
                    cnt        <= 0;
                else
                    cnt <= cnt + 1;
                end if;
            else
                cnt <= 0;
            end if;
        end if;
    end process;

    dbn <= stable_val;
end Behavioral;
