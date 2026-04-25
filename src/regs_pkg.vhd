-------------------------------------------------------------------------------
-- regs_pkg.vhd
--
-- Shared package that exposes the register-file storage type so that
-- VHDL-2008 testbenches can use external names to peek at the live
-- contents of regs.mem (e.g. to display reg1data/reg2data/reg3data in
-- the simulation waveform with the same names used in the lab manual
-- reference).
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

package regs_pkg is
    type reg_array_t is array (0 to 31) of std_logic_vector(15 downto 0);
end package regs_pkg;
