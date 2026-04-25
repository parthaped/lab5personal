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
add_module clock_div    clock_div_cpu
add_module clock_div_25 clock_div_25_inst
add_module debounce     debounce_inst
add_module controls     controls_inst
add_module regs         regs_inst
add_module my_alu       my_alu_inst
add_module framebuffer  framebuffer_inst
add_module vga_ctrl     vga_ctrl_inst
add_module pixel_pusher pixel_pusher_inst
add_module uart         uart_inst

# Generics
set_property -dict [list \
    CONFIG.DIV {1} \
] [get_bd_cells clock_div_cpu]

set_property -dict [list \
    CONFIG.DIV {5} \
] [get_bd_cells clock_div_25_inst]

set_property -dict [list \
    CONFIG.STABLE {1250000} \
] [get_bd_cells debounce_inst]

# UART CLKS_PER_BIT = 125 MHz / 115200 = 1085 on Zybo Z7-10.
set_property -dict [list \
    CONFIG.CLKS_PER_BIT {1085} \
] [get_bd_cells uart_inst]

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
# UART port names match the Pmod silkscreen convention (lab manual style):
#   tx external port = wire labelled "tx" on the Pmod (i.e. Pmod's TX, FPGA INPUT)
#   rx external port = wire labelled "rx" on the Pmod (i.e. Pmod's RX, FPGA OUTPUT)
# This is why they appear "crossed" against the uart cell's tx/rx pins.
#
# VGA outputs are 5-6-5 directly out of pixel_pusher, matching the lab BD
# (no slice IPs in the diagram). Pmod VGA is physically 4-4-4 - the XDC maps
# the top 4 bits of each channel and leaves the LSB(s) unconstrained.
create_bd_port -dir I -type clk clk
create_bd_port -dir I btn
create_bd_port -dir I tx
create_bd_port -dir O rx
create_bd_port -dir O -from 4 -to 0 vga_r
create_bd_port -dir O -from 5 -to 0 vga_g
create_bd_port -dir O -from 4 -to 0 vga_b
create_bd_port -dir O vga_hs
create_bd_port -dir O vga_vs

# --------- 6. wiring ---------
proc cn {a b} { connect_bd_net $a $b }

# Clock + reset distribution
cn [get_bd_ports clk]                      [get_bd_pins clock_div_cpu/clk]
cn [get_bd_ports clk]                      [get_bd_pins clock_div_25_inst/clk]
cn [get_bd_ports clk]                      [get_bd_pins debounce_inst/clk]
cn [get_bd_ports clk]                      [get_bd_pins controls_inst/clk]
cn [get_bd_ports clk]                      [get_bd_pins regs_inst/clk]
cn [get_bd_ports clk]                      [get_bd_pins my_alu_inst/clk]
cn [get_bd_ports clk]                      [get_bd_pins framebuffer_inst/clk]
cn [get_bd_ports clk]                      [get_bd_pins vga_ctrl_inst/clk]
cn [get_bd_ports clk]                      [get_bd_pins pixel_pusher_inst/clk]
cn [get_bd_ports clk]                      [get_bd_pins uart_inst/clk]
cn [get_bd_ports clk]                      [get_bd_pins irMem/clka]
cn [get_bd_ports clk]                      [get_bd_pins dMem/clka]

cn [get_bd_ports btn]                      [get_bd_pins debounce_inst/btn]
cn [get_bd_pins debounce_inst/dbn]         [get_bd_pins clock_div_cpu/rst]
cn [get_bd_pins debounce_inst/dbn]         [get_bd_pins clock_div_25_inst/rst]
cn [get_bd_pins debounce_inst/dbn]         [get_bd_pins controls_inst/rst]
cn [get_bd_pins debounce_inst/dbn]         [get_bd_pins regs_inst/rst]
cn [get_bd_pins debounce_inst/dbn]         [get_bd_pins uart_inst/rst]

# Clock-enables (the UART has counter-based bit timing and only needs clk)
cn [get_bd_pins clock_div_cpu/en]          [get_bd_pins controls_inst/en]
cn [get_bd_pins clock_div_cpu/en]          [get_bd_pins regs_inst/en]
cn [get_bd_pins clock_div_cpu/en]          [get_bd_pins my_alu_inst/en]
cn [get_bd_pins clock_div_cpu/en]          [get_bd_pins framebuffer_inst/en1]
cn [get_bd_pins clock_div_25_inst/en]      [get_bd_pins framebuffer_inst/en2]
cn [get_bd_pins clock_div_25_inst/en]      [get_bd_pins vga_ctrl_inst/en]
cn [get_bd_pins clock_div_25_inst/en]      [get_bd_pins pixel_pusher_inst/en]

# controls <-> regs
cn [get_bd_pins controls_inst/rID1]        [get_bd_pins regs_inst/id1]
cn [get_bd_pins controls_inst/rID2]        [get_bd_pins regs_inst/id2]
cn [get_bd_pins controls_inst/wr_enR1]     [get_bd_pins regs_inst/wr_en1]
cn [get_bd_pins controls_inst/wr_enR2]     [get_bd_pins regs_inst/wr_en2]
cn [get_bd_pins controls_inst/regwD1]      [get_bd_pins regs_inst/din1]
cn [get_bd_pins controls_inst/regwD2]      [get_bd_pins regs_inst/din2]
cn [get_bd_pins regs_inst/dout1]           [get_bd_pins controls_inst/regrD1]
cn [get_bd_pins regs_inst/dout2]           [get_bd_pins controls_inst/regrD2]

# controls <-> framebuffer (port 1)
cn [get_bd_pins controls_inst/fbRST]       [get_bd_pins framebuffer_inst/ld]
cn [get_bd_pins controls_inst/fbAddr1]     [get_bd_pins framebuffer_inst/addr1]
cn [get_bd_pins controls_inst/fbDout1]     [get_bd_pins framebuffer_inst/din1]
cn [get_bd_pins framebuffer_inst/dout1]    [get_bd_pins controls_inst/fbDin1]
cn [get_bd_pins controls_inst/fbWr_en]     [get_bd_pins framebuffer_inst/wr_en1]

# pixel_pusher <-> framebuffer (port 2)
cn [get_bd_pins pixel_pusher_inst/addr]    [get_bd_pins framebuffer_inst/addr2]
cn [get_bd_pins framebuffer_inst/dout2]    [get_bd_pins pixel_pusher_inst/pixel]

# vga_ctrl <-> pixel_pusher
cn [get_bd_pins vga_ctrl_inst/hcount]      [get_bd_pins pixel_pusher_inst/hcount]
cn [get_bd_pins vga_ctrl_inst/vcount]      [get_bd_pins pixel_pusher_inst/vcount]
cn [get_bd_pins vga_ctrl_inst/vid]         [get_bd_pins pixel_pusher_inst/vid]
cn [get_bd_pins vga_ctrl_inst/vs]          [get_bd_pins pixel_pusher_inst/vs]

# VGA outputs (5-6-5 from pixel_pusher straight to external ports)
cn [get_bd_pins pixel_pusher_inst/r]       [get_bd_ports vga_r]
cn [get_bd_pins pixel_pusher_inst/g]       [get_bd_ports vga_g]
cn [get_bd_pins pixel_pusher_inst/b]       [get_bd_ports vga_b]
cn [get_bd_pins vga_ctrl_inst/hs]          [get_bd_ports vga_hs]
cn [get_bd_pins vga_ctrl_inst/vs]          [get_bd_ports vga_vs]

# controls <-> ALU
cn [get_bd_pins controls_inst/aluA]        [get_bd_pins my_alu_inst/A]
cn [get_bd_pins controls_inst/aluB]        [get_bd_pins my_alu_inst/B]
cn [get_bd_pins controls_inst/aluOp]       [get_bd_pins my_alu_inst/opcode]
cn [get_bd_pins my_alu_inst/Y]             [get_bd_pins controls_inst/aluResult]

# controls <-> irMem (BMG IP). BMG ports: addra, dina, douta, ena, wea
cn [get_bd_pins controls_inst/irAddr]      [get_bd_pins irMem/addra]
cn [get_bd_pins irMem/douta]               [get_bd_pins controls_inst/irWord]
cn [get_bd_pins clock_div_cpu/en]          [get_bd_pins irMem/ena]

# controls <-> dMem
cn [get_bd_pins controls_inst/dAddr]       [get_bd_pins dMem/addra]
cn [get_bd_pins controls_inst/dOut]        [get_bd_pins dMem/dina]
cn [get_bd_pins dMem/douta]                [get_bd_pins controls_inst/dIn]
cn [get_bd_pins controls_inst/d_wr_en]     [get_bd_pins dMem/wea]
cn [get_bd_pins clock_div_cpu/en]          [get_bd_pins dMem/ena]

# controls <-> uart
cn [get_bd_pins controls_inst/send]        [get_bd_pins uart_inst/send]
cn [get_bd_pins controls_inst/charSend]    [get_bd_pins uart_inst/charSend]
cn [get_bd_pins uart_inst/ready]           [get_bd_pins controls_inst/ready]
cn [get_bd_pins uart_inst/newChar]         [get_bd_pins controls_inst/newChar]
cn [get_bd_pins uart_inst/charRec]         [get_bd_pins controls_inst/charRec]
# Crossed: external "tx" port is the Pmod's TX line (FPGA INPUT) feeding uart.rx
#          external "rx" port is the Pmod's RX line (FPGA OUTPUT) driven by uart.tx
cn [get_bd_ports tx]                       [get_bd_pins uart_inst/rx]
cn [get_bd_pins uart_inst/tx]              [get_bd_ports rx]

# --------- 7. validate, layout, wrap, save ---------
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
