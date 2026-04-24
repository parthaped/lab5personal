-------------------------------------------------------------------------------
-- my_alu.vhd
--
-- 16-bit synchronous ALU for the GRISC ASIP. Operations are clocked and gated
-- by a clock-enable so that controls can hold operands stable for one cycle
-- and capture the result on the following rising edge (NOTE 1 in the lab).
--
-- Comparison results (B,C,D,E,F) are produced as a single bit in position 0
-- of Y as required by the Lab 5 ALU table; all other bits are zero.
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity my_alu is
    Port (
        clk    : in  std_logic;
        en     : in  std_logic;
        A      : in  std_logic_vector(15 downto 0);
        B      : in  std_logic_vector(15 downto 0);
        opcode : in  std_logic_vector(3 downto 0);
        Y      : out std_logic_vector(15 downto 0)
    );
end my_alu;

architecture Behavioral of my_alu is
    signal result : std_logic_vector(15 downto 0) := (others => '0');
begin
    process(clk)
        variable A_s, B_s : signed(15 downto 0);
        variable A_u, B_u : unsigned(15 downto 0);
        variable tmp      : std_logic_vector(15 downto 0);
    begin
        if rising_edge(clk) then
            if en = '1' then
                A_s := signed(A);
                B_s := signed(B);
                A_u := unsigned(A);
                B_u := unsigned(B);
                tmp := (others => '0');

                case opcode is
                    when x"0" => tmp := std_logic_vector(A_u + B_u);
                    when x"1" => tmp := std_logic_vector(A_u - B_u);
                    when x"2" => tmp := std_logic_vector(A_u + 1);
                    when x"3" => tmp := std_logic_vector(A_u - 1);
                    when x"4" => tmp := std_logic_vector(0 - A_s);
                    when x"5" => tmp := std_logic_vector(shift_left(A_u, 1));
                    when x"6" => tmp := std_logic_vector(shift_right(A_u, 1));
                    when x"7" => tmp := std_logic_vector(shift_right(A_s, 1));
                    when x"8" => tmp := A and B;
                    when x"9" => tmp := A or B;
                    when x"A" => tmp := A xor B;
                    when x"B" =>
                        if A_s < B_s then tmp(0) := '1'; end if;
                    when x"C" =>
                        if A_s > B_s then tmp(0) := '1'; end if;
                    when x"D" =>
                        if A_u = B_u then tmp(0) := '1'; end if;
                    when x"E" =>
                        if A_u < B_u then tmp(0) := '1'; end if;
                    when x"F" =>
                        if A_u > B_u then tmp(0) := '1'; end if;
                    when others =>
                        tmp := (others => '0');
                end case;

                result <= tmp;
            end if;
        end if;
    end process;

    Y <= result;
end Behavioral;
