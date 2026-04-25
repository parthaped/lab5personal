###############################################################################
# build_block_design.tcl - Automates the IP Integrator steps for Lab 5.
#
# Run inside Vivado AFTER create_project.tcl has succeeded:
#     source scripts/build_block_design.tcl
#
# What it does:
#   1. Creates a block design called uproc_top_level.
#   2. Adds every VHDL entity as a "Module Reference" so you can see the blocks
#      in the canvas exactly like Figures 5.2 / 5.3.
#   3. Adds and configures the irMem (32x16384 ROM, init from text.coe) and
#      dMem (16x32768 RAM, init from data.coe) Block Memory Generator IPs.
#   4. Wires every signal per the lab block diagrams.
#   5. Makes the external ports (clk, btn, rx, tx, vga_*, hs, vs).
#   6. Validates the design, creates the HDL wrapper, sets it top.
###############################################################################

set bd_name "uproc_top_level"
set proj_dir [file normalize "[file dirname [info script]]/.."]

# --------- 1. create the block design ---------
create_bd_design $bd_name
current_bd_design $bd_name

# Convenience: shorter create_bd_cell wrapper
proc add_module {ref inst_name} {
    create_bd_cell -type module -reference $ref $inst_name
}

# --------- 2. add module references ---------
# Cell instance names use Vivado's `<entity>_0` auto-naming convention so the
# generated BD canvas matches the lab manual reference top-level diagram
# row-for-row (e.g. the wr_enR1 net is named `controls_0_wr_enR1`).
add_module clock_div    clock_div_0
add_module clock_div_25 clock_div_25_0
add_module debounce     debounce_0
add_module controls     controls_0
add_module regs         regs_0
add_module my_alu       my_alu_0
add_module framebuffer  framebuffer_0
add_module vga_ctrl     vga_ctrl_0
add_module pixel_pusher pixel_pusher_0
add_module uart         uart_0

# Generics
set_property -dict [list \
    CONFIG.DIV {1} \
] [get_bd_cells clock_div_0]

set_property -dict [list \
    CONFIG.DIV {5} \
] [get_bd_cells clock_div_25_0]

set_property -dict [list \
    CONFIG.STABLE {1250000} \
] [get_bd_cells debounce_0]

# UART CLKS_PER_BIT = 125 MHz / 115200 = 1085 on Zybo Z7-10.
set_property -dict [list \
    CONFIG.CLKS_PER_BIT {1085} \
] [get_bd_cells uart_0]

# --------- 3. instruction memory (BMG IP, 32-bit x 16384, ROM, COE init) ---------
create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen irMem
set_property -dict [list \
    CONFIG.Memory_Type {Single_Port_ROM} \
    CONFIG.Write_Width_A {32} \
    CONFIG.Read_Width_A {32} \
    CONFIG.Write_Depth_A {16384} \
    CONFIG.Use_Byte_Write_Enable {false} \
    CONFIG.Register_PortA_Output_of_Memory_Primitives {false} \
    CONFIG.Load_Init_File {true} \
    CONFIG.Coe_File "$proj_dir/coe/text.coe" \
    CONFIG.use_bram_block {Stand_Alone} \
] [get_bd_cells irMem]

# --------- 4. data memory (BMG IP, 16-bit x 32768, RAM, COE init) ---------
create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen dMem
set_property -dict [list \
    CONFIG.Memory_Type {Single_Port_RAM} \
    CONFIG.Write_Width_A {16} \
    CONFIG.Read_Width_A {16} \
    CONFIG.Write_Depth_A {32768} \
    CONFIG.Use_Byte_Write_Enable {false} \
    CONFIG.Register_PortA_Output_of_Memory_Primitives {false} \
    CONFIG.Load_Init_File {true} \
    CONFIG.Coe_File "$proj_dir/coe/data.coe" \
    CONFIG.use_bram_block {Stand_Alone} \
] [get_bd_cells dMem]

# --------- 5. external ports ---------
# Names match the Pmod USBUART silkscreen convention used in the lab manual
# reference BD:
#   TXD = Pmod's TXD pin (FPGA INPUT, host -> FPGA)
#   RXD = Pmod's RXD pin (FPGA OUTPUT, FPGA -> host)
#   CTS = Pmod's CTS pin (FPGA INPUT, ignored - matches the reference BD,
#         which leaves CTS unconnected internally rather than driving it
#         with an xlconstant)
#   RTS = Pmod's RTS pin (FPGA INPUT, ignored - host is always ready)
#
# btn is named btn_0 to match the lab BD (Vivado's auto-rename convention
# when "Make External" is used on a single-bit pin).
#
# VGA outputs are 5-6-5 straight out of pixel_pusher (no slice IPs in the
# reference BD). The XDC maps the top 4 bits of each channel to Pmod VGA
# pins; the LSBs are intentionally unconstrained.
create_bd_port -dir I -type clk clk
create_bd_port -dir I btn_0
create_bd_port -dir I TXD
create_bd_port -dir O RXD
create_bd_port -dir I RTS
create_bd_port -dir I CTS
create_bd_port -dir O -from 4 -to 0 vga_r
create_bd_port -dir O -from 5 -to 0 vga_g
create_bd_port -dir O -from 4 -to 0 vga_b
create_bd_port -dir O vga_hs
create_bd_port -dir O vga_vs

# --------- 6. wiring ---------
# Wrapper around connect_bd_net that hard-fails if either side resolves to
# an empty pin/port list. Without this, a typo in a pin name silently leaves
# a wire dangling and validate_bd_design later complains about "missing
# connections" with no easy way to find which line caused it.
proc cn {a b} {
    if {[llength $a] == 0} {
        error "connect_bd_net: left-hand pin/port list is empty"
    }
    if {[llength $b] == 0} {
        error "connect_bd_net: right-hand pin/port list is empty"
    }
    connect_bd_net $a $b
}

# Clock + reset distribution
cn [get_bd_ports clk]                      [get_bd_pins clock_div_0/clk]
cn [get_bd_ports clk]                      [get_bd_pins clock_div_25_0/clk]
cn [get_bd_ports clk]                      [get_bd_pins debounce_0/clk]
cn [get_bd_ports clk]                      [get_bd_pins controls_0/clk]
cn [get_bd_ports clk]                      [get_bd_pins regs_0/clk]
cn [get_bd_ports clk]                      [get_bd_pins my_alu_0/clk]
cn [get_bd_ports clk]                      [get_bd_pins framebuffer_0/clk]
cn [get_bd_ports clk]                      [get_bd_pins vga_ctrl_0/clk]
cn [get_bd_ports clk]                      [get_bd_pins pixel_pusher_0/clk]
cn [get_bd_ports clk]                      [get_bd_pins uart_0/clk]
cn [get_bd_ports clk]                      [get_bd_pins irMem/clka]
cn [get_bd_ports clk]                      [get_bd_pins dMem/clka]

cn [get_bd_ports btn_0]                    [get_bd_pins debounce_0/btn]
cn [get_bd_pins debounce_0/dbn]            [get_bd_pins clock_div_0/rst]
cn [get_bd_pins debounce_0/dbn]            [get_bd_pins clock_div_25_0/rst]
cn [get_bd_pins debounce_0/dbn]            [get_bd_pins controls_0/rst]
cn [get_bd_pins debounce_0/dbn]            [get_bd_pins regs_0/rst]
cn [get_bd_pins debounce_0/dbn]            [get_bd_pins uart_0/rst]

# Clock-enables (the UART has counter-based bit timing and only needs clk)
cn [get_bd_pins clock_div_0/en]            [get_bd_pins controls_0/en]
cn [get_bd_pins clock_div_0/en]            [get_bd_pins regs_0/en]
cn [get_bd_pins clock_div_0/en]            [get_bd_pins my_alu_0/en]
cn [get_bd_pins clock_div_0/en]            [get_bd_pins framebuffer_0/en1]
cn [get_bd_pins clock_div_25_0/en]         [get_bd_pins framebuffer_0/en2]
cn [get_bd_pins clock_div_25_0/en]         [get_bd_pins vga_ctrl_0/en]
cn [get_bd_pins clock_div_25_0/en]         [get_bd_pins pixel_pusher_0/en]

# controls <-> regs
cn [get_bd_pins controls_0/rID1]           [get_bd_pins regs_0/id1]
cn [get_bd_pins controls_0/rID2]           [get_bd_pins regs_0/id2]
cn [get_bd_pins controls_0/wr_enR1]        [get_bd_pins regs_0/wr_en1]
cn [get_bd_pins controls_0/wr_enR2]        [get_bd_pins regs_0/wr_en2]
cn [get_bd_pins controls_0/regwD1]         [get_bd_pins regs_0/din1]
cn [get_bd_pins controls_0/regwD2]         [get_bd_pins regs_0/din2]
cn [get_bd_pins regs_0/dout1]              [get_bd_pins controls_0/regrD1]
cn [get_bd_pins regs_0/dout2]              [get_bd_pins controls_0/regrD2]

# controls <-> framebuffer (port 1)
cn [get_bd_pins controls_0/fbRST]          [get_bd_pins framebuffer_0/ld]
cn [get_bd_pins controls_0/fbAddr1]        [get_bd_pins framebuffer_0/addr1]
cn [get_bd_pins controls_0/fbDout1]        [get_bd_pins framebuffer_0/din1]
cn [get_bd_pins framebuffer_0/dout1]       [get_bd_pins controls_0/fbDin1]
cn [get_bd_pins controls_0/fbWr_en]        [get_bd_pins framebuffer_0/wr_en1]

# pixel_pusher <-> framebuffer (port 2)
cn [get_bd_pins pixel_pusher_0/addr]       [get_bd_pins framebuffer_0/addr2]
cn [get_bd_pins framebuffer_0/dout2]       [get_bd_pins pixel_pusher_0/pixel]

# vga_ctrl <-> pixel_pusher
cn [get_bd_pins vga_ctrl_0/hcount]         [get_bd_pins pixel_pusher_0/hcount]
cn [get_bd_pins vga_ctrl_0/vcount]         [get_bd_pins pixel_pusher_0/vcount]
cn [get_bd_pins vga_ctrl_0/vid]            [get_bd_pins pixel_pusher_0/vid]
cn [get_bd_pins vga_ctrl_0/vs]             [get_bd_pins pixel_pusher_0/vs]

# VGA outputs (5-6-5 from pixel_pusher straight to external ports)
cn [get_bd_pins pixel_pusher_0/r]          [get_bd_ports vga_r]
cn [get_bd_pins pixel_pusher_0/g]          [get_bd_ports vga_g]
cn [get_bd_pins pixel_pusher_0/b]          [get_bd_ports vga_b]
cn [get_bd_pins vga_ctrl_0/hs]             [get_bd_ports vga_hs]
cn [get_bd_pins vga_ctrl_0/vs]             [get_bd_ports vga_vs]

# controls <-> ALU
cn [get_bd_pins controls_0/aluA]           [get_bd_pins my_alu_0/A]
cn [get_bd_pins controls_0/aluB]           [get_bd_pins my_alu_0/B]
cn [get_bd_pins controls_0/aluOp]          [get_bd_pins my_alu_0/opcode]
cn [get_bd_pins my_alu_0/Y]                [get_bd_pins controls_0/aluResult]

# controls <-> irMem (BMG IP). BMG ports: addra, dina, douta, ena, wea
cn [get_bd_pins controls_0/irAddr]         [get_bd_pins irMem/addra]
cn [get_bd_pins irMem/douta]               [get_bd_pins controls_0/irWord]
cn [get_bd_pins clock_div_0/en]            [get_bd_pins irMem/ena]

# controls <-> dMem
cn [get_bd_pins controls_0/dAddr]          [get_bd_pins dMem/addra]
cn [get_bd_pins controls_0/dOut]           [get_bd_pins dMem/dina]
cn [get_bd_pins dMem/douta]                [get_bd_pins controls_0/dIn]
cn [get_bd_pins controls_0/d_wr_en]        [get_bd_pins dMem/wea]
cn [get_bd_pins clock_div_0/en]            [get_bd_pins dMem/ena]

# controls <-> uart
# NOTE: the controls entity port is `tx_send` (renamed from `send` to avoid
# clashing with the FSM state literal `send`).  The uart entity still uses
# `send` on its side.
cn [get_bd_pins controls_0/tx_send]        [get_bd_pins uart_0/send]
cn [get_bd_pins controls_0/charSend]       [get_bd_pins uart_0/charSend]
cn [get_bd_pins uart_0/ready]              [get_bd_pins controls_0/ready]
cn [get_bd_pins uart_0/newChar]            [get_bd_pins controls_0/newChar]
cn [get_bd_pins uart_0/charRec]            [get_bd_pins controls_0/charRec]
# UART crossed wiring (lab manual convention):
#   TXD external (Pmod TX, FPGA in) -> uart.rx
#   uart.tx -> RXD external (Pmod RX, FPGA out)
cn [get_bd_ports TXD]                      [get_bd_pins uart_0/rx]
cn [get_bd_pins uart_0/tx]                 [get_bd_ports RXD]
# CTS and RTS are external ports only; the reference BD leaves both
# unconnected internally (no xlconstant driver, no UART pin), so we do
# the same here.

# --------- 7. validate, layout, wrap, save ---------
# regenerate_bd_layout uses Vivado's default "inputs left, outputs right"
# heuristic. If a pin still ends up on the wrong side after the script runs,
# right-click the BD canvas in Vivado and choose "Regenerate Layout" (F6).
regenerate_bd_layout
validate_bd_design
save_bd_design

# Generate the HDL wrapper and set as top
set bd_file [get_files "$bd_name.bd"]
make_wrapper -files [get_files $bd_file] -top
set wrapper "$proj_dir/lab5_grisc/lab5_grisc.gen/sources_1/bd/$bd_name/hdl/${bd_name}_wrapper.vhd"
add_files -norecurse $wrapper
set_property top "${bd_name}_wrapper" [current_fileset]
update_compile_order -fileset sources_1

puts "===================================================================="
puts "Block design '$bd_name' built and validated."
puts "Wrapper: ${bd_name}_wrapper"
puts ""
puts "Next: source scripts/run_sim.tcl  to launch the testbench"
puts "      or: launch_runs synth_1 -jobs 4 ; wait_on_run synth_1"
puts "===================================================================="
