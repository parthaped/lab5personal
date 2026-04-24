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
# Reset button - BTN0
###############################################################################
set_property -dict { PACKAGE_PIN K18 IOSTANDARD LVCMOS33 } [get_ports btn]

###############################################################################
# UART on Pmod JE  (Pmod USBUART module)
#   JE2 = TX (FPGA -> host)
#   JE3 = RX (host  -> FPGA)
###############################################################################
set_property -dict { PACKAGE_PIN W16 IOSTANDARD LVCMOS33 } [get_ports tx]   ;# JE2
set_property -dict { PACKAGE_PIN J15 IOSTANDARD LVCMOS33 } [get_ports rx]   ;# JE3

###############################################################################
# Pmod VGA - 4+4+4 RGB
#
#   JB1..JB4 = R[0..3]
#   JB7..JB10 = B[0..3]
#   JC1..JC4 = G[0..3]
#   JC7      = HS
#   JC8      = VS
###############################################################################
set_property -dict { PACKAGE_PIN T20 IOSTANDARD LVCMOS33 } [get_ports {vga_r[0]}] ;# JB1
set_property -dict { PACKAGE_PIN U20 IOSTANDARD LVCMOS33 } [get_ports {vga_r[1]}] ;# JB2
set_property -dict { PACKAGE_PIN V20 IOSTANDARD LVCMOS33 } [get_ports {vga_r[2]}] ;# JB3
set_property -dict { PACKAGE_PIN W20 IOSTANDARD LVCMOS33 } [get_ports {vga_r[3]}] ;# JB4

set_property -dict { PACKAGE_PIN Y19 IOSTANDARD LVCMOS33 } [get_ports {vga_b[0]}] ;# JB7
set_property -dict { PACKAGE_PIN Y18 IOSTANDARD LVCMOS33 } [get_ports {vga_b[1]}] ;# JB8
set_property -dict { PACKAGE_PIN W18 IOSTANDARD LVCMOS33 } [get_ports {vga_b[2]}] ;# JB9
set_property -dict { PACKAGE_PIN W19 IOSTANDARD LVCMOS33 } [get_ports {vga_b[3]}] ;# JB10

set_property -dict { PACKAGE_PIN V15 IOSTANDARD LVCMOS33 } [get_ports {vga_g[0]}] ;# JC1
set_property -dict { PACKAGE_PIN W15 IOSTANDARD LVCMOS33 } [get_ports {vga_g[1]}] ;# JC2
set_property -dict { PACKAGE_PIN T11 IOSTANDARD LVCMOS33 } [get_ports {vga_g[2]}] ;# JC3
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports {vga_g[3]}] ;# JC4
set_property -dict { PACKAGE_PIN W14 IOSTANDARD LVCMOS33 } [get_ports vga_hs]      ;# JC7
set_property -dict { PACKAGE_PIN Y14 IOSTANDARD LVCMOS33 } [get_ports vga_vs]      ;# JC8

###############################################################################
# Configuration voltage (Zynq devices)
###############################################################################
set_property CFGBVS VCCO         [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
