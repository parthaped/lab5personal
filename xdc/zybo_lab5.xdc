###############################################################################
# zybo_lab5.xdc
#
# Pin assignments for the GRISC ASIP on a Digilent Zybo Z7-10 (xc7z010clg400-1)
# with a Digilent Pmod VGA on connector JB + JC and a Pmod USBUART on JE.
#
# Pin numbers come from Digilent's "ZYBO Z7-10 Master XDC" (rev. C).
# If your board uses a different VGA Pmod arrangement, replace the JB / JC
# entries below with the values from that master XDC.
###############################################################################

###############################################################################
# System clock - 125 MHz
###############################################################################
set_property -dict { PACKAGE_PIN K17 IOSTANDARD LVCMOS33 } [get_ports clk]
create_clock -name sys_clk -period 8.000 [get_ports clk]

###############################################################################
# Reset button - BTN0  (named btn_0 to match the lab BD)
###############################################################################
set_property -dict { PACKAGE_PIN K18 IOSTANDARD LVCMOS33 } [get_ports btn_0]

###############################################################################
# UART on Pmod JE  (Pmod USBUART module). Port names match the Pmod
# silkscreen and the lab manual reference BD:
#   TXD = Pmod's TXD pin (JE3, FPGA INPUT,  host -> FPGA)
#   RXD = Pmod's RXD pin (JE2, FPGA OUTPUT, FPGA -> host)
#   CTS = Pmod's CTS pin (JE4, FPGA OUTPUT tied to '0', no flow control)
#   RTS = Pmod's RTS pin (JE1, FPGA OUTPUT tied to '0', no flow control)
# Per Lab 3 page 5: CTS and RTS are unused flow-control pins that must be
# tied to ground in the design.
###############################################################################
set_property -dict { PACKAGE_PIN J15 IOSTANDARD LVCMOS33 } [get_ports TXD] ;# JE3
set_property -dict { PACKAGE_PIN W16 IOSTANDARD LVCMOS33 } [get_ports RXD] ;# JE2
set_property -dict { PACKAGE_PIN H15 IOSTANDARD LVCMOS33 } [get_ports CTS] ;# JE4
set_property -dict { PACKAGE_PIN V12 IOSTANDARD LVCMOS33 } [get_ports RTS] ;# JE1

###############################################################################
# Pmod VGA - hardware is 4+4+4 RGB but pixel_pusher emits 5+6+5.
# We constrain the TOP 4 bits of each channel to the Pmod pins. The unused
# LSB(s) (vga_r[0], vga_g[0..1], vga_b[0]) are left unconnected; allow that
# explicitly so synth/impl don't error out.
#
#   JB1..JB4 = R[3..0] -> tied to vga_r[4..1]    (vga_r[0] unused)
#   JB7..JB10 = B[3..0] -> tied to vga_b[4..1]    (vga_b[0] unused)
#   JC1..JC4 = G[3..0] -> tied to vga_g[5..2]    (vga_g[1..0] unused)
#   JC7      = HS
#   JC8      = VS
###############################################################################
set_property -dict { PACKAGE_PIN T20 IOSTANDARD LVCMOS33 } [get_ports {vga_r[1]}] ;# JB1  -> R0
set_property -dict { PACKAGE_PIN U20 IOSTANDARD LVCMOS33 } [get_ports {vga_r[2]}] ;# JB2  -> R1
set_property -dict { PACKAGE_PIN V20 IOSTANDARD LVCMOS33 } [get_ports {vga_r[3]}] ;# JB3  -> R2
set_property -dict { PACKAGE_PIN W20 IOSTANDARD LVCMOS33 } [get_ports {vga_r[4]}] ;# JB4  -> R3 (MSB)

set_property -dict { PACKAGE_PIN Y19 IOSTANDARD LVCMOS33 } [get_ports {vga_b[1]}] ;# JB7  -> B0
set_property -dict { PACKAGE_PIN Y18 IOSTANDARD LVCMOS33 } [get_ports {vga_b[2]}] ;# JB8  -> B1
set_property -dict { PACKAGE_PIN W18 IOSTANDARD LVCMOS33 } [get_ports {vga_b[3]}] ;# JB9  -> B2
set_property -dict { PACKAGE_PIN W19 IOSTANDARD LVCMOS33 } [get_ports {vga_b[4]}] ;# JB10 -> B3 (MSB)

set_property -dict { PACKAGE_PIN V15 IOSTANDARD LVCMOS33 } [get_ports {vga_g[2]}] ;# JC1  -> G0
set_property -dict { PACKAGE_PIN W15 IOSTANDARD LVCMOS33 } [get_ports {vga_g[3]}] ;# JC2  -> G1
set_property -dict { PACKAGE_PIN T11 IOSTANDARD LVCMOS33 } [get_ports {vga_g[4]}] ;# JC3  -> G2
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports {vga_g[5]}] ;# JC4  -> G3 (MSB)
set_property -dict { PACKAGE_PIN W14 IOSTANDARD LVCMOS33 } [get_ports vga_hs]     ;# JC7
set_property -dict { PACKAGE_PIN Y14 IOSTANDARD LVCMOS33 } [get_ports vga_vs]     ;# JC8

# The unused VGA LSB outputs are intentionally unconstrained.
set_property BITSTREAM.GENERAL.UNCONSTRAINEDPINS Allow [current_design]

###############################################################################
# Configuration voltage (Zynq devices)
###############################################################################
set_property CFGBVS VCCO         [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
