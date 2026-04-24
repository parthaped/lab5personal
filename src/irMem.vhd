-------------------------------------------------------------------------------
-- irMem.vhd
--
-- 32-bit x 16384 word instruction ROM. Initialised from a Xilinx-style COE
-- file at elaboration time so that both simulation and synthesis see the
-- same image. Vivado infers BRAM from this template.
--
-- The block design described in the lab uses a Block Memory Generator IP for
-- this role; this entity is functionally identical (single-port ROM, sync
-- read, COE-initialised) and can be substituted with BMG by removing this
-- file from the design sources and adding the IP instead.
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;
use IEEE.STD_LOGIC_TEXTIO.ALL;

entity irMem is
    Generic (
        COE_FILE : string := "text.coe"
    );
    Port (
        clk  : in  std_logic;
        en   : in  std_logic;
        addr : in  std_logic_vector(13 downto 0);
        dout : out std_logic_vector(31 downto 0)
    );
end irMem;

architecture Behavioral of irMem is
    type rom_t is array (0 to 16383) of std_logic_vector(31 downto 0);

    impure function load_coe(name : string) return rom_t is
        file     fh    : text;
        variable l     : line;
        variable r     : rom_t := (others => (others => '0'));
        variable v     : std_logic_vector(31 downto 0);
        variable idx   : integer := 0;
        variable status: file_open_status;
        variable c     : character;
        variable bits  : string(1 to 32);
        variable bcnt  : integer;
        variable started : boolean := false;
    begin
        file_open(status, fh, name, read_mode);
        if status /= open_ok then
            report "irMem: could not open " & name severity warning;
            return r;
        end if;

        while not endfile(fh) loop
            readline(fh, l);
            if l'length = 0 then next; end if;

            if not started then
                if l(l'low) = 'M' or l(l'low) = 'm' then
                    if l'length >= 30 then
                        started := true;
                    end if;
                    next;
                end if;
                next;
            end if;

            bcnt := 0;
            for i in l'range loop
                c := l(i);
                if c = '0' or c = '1' then
                    bcnt := bcnt + 1;
                    bits(bcnt) := c;
                    if bcnt = 32 then exit; end if;
                elsif c = ',' or c = ';' then
                    exit;
                end if;
            end loop;

            if bcnt = 32 then
                for i in 0 to 31 loop
                    if bits(i + 1) = '1' then
                        v(31 - i) := '1';
                    else
                        v(31 - i) := '0';
                    end if;
                end loop;
                r(idx) := v;
                idx := idx + 1;
            end if;
        end loop;

        file_close(fh);
        return r;
    end function;

    signal mem : rom_t := load_coe(COE_FILE);
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if en = '1' then
                dout <= mem(to_integer(unsigned(addr)));
            end if;
        end if;
    end process;
end Behavioral;
