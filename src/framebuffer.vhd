-------------------------------------------------------------------------------
-- framebuffer.vhd
--
-- 4096 x 16-bit dual-port RAM that infers as BRAM in Vivado.
--
--   * Port 1 (en1, addr1, din1, wr_en1, dout1) is the CPU side: full read/write.
--   * Port 2 (en2, addr2, dout2)               is the video side: read only.
--   * ld asserts a screen-clear: a state machine walks through every address
--     writing zero, finishing 4096 cycles later. Resetting one location per
--     cycle keeps Vivado happy and still infers BRAM (resetting all locations
--     simultaneously forces register-file synthesis instead).
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity framebuffer is
    Port (
        clk     : in  std_logic;
        en1     : in  std_logic;
        en2     : in  std_logic;
        ld      : in  std_logic;
        addr1   : in  std_logic_vector(11 downto 0);
        addr2   : in  std_logic_vector(11 downto 0);
        wr_en1  : in  std_logic;
        din1    : in  std_logic_vector(15 downto 0);
        dout1   : out std_logic_vector(15 downto 0);
        dout2   : out std_logic_vector(15 downto 0)
    );
end framebuffer;

architecture Behavioral of framebuffer is
    type mem_t is array (0 to 4095) of std_logic_vector(15 downto 0);
    signal mem : mem_t := (others => (others => '0'));

    signal clear_active : std_logic              := '0';
    signal clear_cnt    : unsigned(11 downto 0)  := (others => '0');
    signal eff_addr1    : std_logic_vector(11 downto 0);
    signal eff_we1      : std_logic;
    signal eff_din1     : std_logic_vector(15 downto 0);
begin
    -- Clear FSM: ld -> walk every address writing zero.
    process(clk)
    begin
        if rising_edge(clk) then
            if ld = '1' then
                clear_active <= '1';
                clear_cnt    <= (others => '0');
            elsif clear_active = '1' then
                if clear_cnt = to_unsigned(4095, 12) then
                    clear_active <= '0';
                else
                    clear_cnt <= clear_cnt + 1;
                end if;
            end if;
        end if;
    end process;

    eff_addr1 <= std_logic_vector(clear_cnt) when clear_active = '1' else addr1;
    eff_we1   <= '1'                         when clear_active = '1' else wr_en1;
    eff_din1  <= (others => '0')             when clear_active = '1' else din1;

    -- True dual-port BRAM in a single clocked process. Vivado infers BRAM
    -- and modelsim/ghdl synth tools accept this template without needing a
    -- shared variable / protected type.
    process(clk)
    begin
        if rising_edge(clk) then
            -- Port 1: CPU side
            if en1 = '1' or clear_active = '1' then
                if eff_we1 = '1' then
                    mem(to_integer(unsigned(eff_addr1))) <= eff_din1;
                end if;
                dout1 <= mem(to_integer(unsigned(eff_addr1)));
            end if;

            -- Port 2: video side
            if en2 = '1' then
                dout2 <= mem(to_integer(unsigned(addr2)));
            end if;
        end if;
    end process;
end Behavioral;
