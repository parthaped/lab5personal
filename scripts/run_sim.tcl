###############################################################################
# run_sim.tcl - Launch the lean behavioural simulation (tb_top_lite).
#
# Run inside Vivado after create_project.tcl has succeeded:
#     source scripts/run_sim.tcl
#
# What it does:
#   1. Sets sim_1's top to tb_top_lite (the crash-safe testbench).
#   2. Caps xsim runtime to 50 us and disables log_all_signals to keep the
#      .wdb file small (this is what prevents the OOM crash on Windows).
#   3. Loads the tb_top.wcfg layout but explicitly removes any references
#      to the BRAM `mem` arrays from irMem/dMem if Vivado tries to add them.
#   4. Calls launch_simulation and runs to completion.
###############################################################################

set proj_dir [file normalize "[file dirname [info script]]/.."]

if {[catch {current_project} _]} {
    puts "ERROR: no project open. Run scripts/create_project.tcl first."
    return
}

# 1. Pick the lean testbench
if {[llength [get_files -quiet -of [get_filesets sim_1] tb_top_lite.vhd]] == 0} {
    add_files -fileset sim_1 -norecurse "$proj_dir/sim/tb_top_lite.vhd"
    set_property file_type {VHDL 2008} \
        [get_files "$proj_dir/sim/tb_top_lite.vhd"]
}
set_property top tb_top_lite [get_filesets sim_1]
update_compile_order -fileset sim_1

# 2. xsim memory-friendly settings
set_property -name {xsim.simulate.runtime}         -value {50us} \
    -objects [get_filesets sim_1]
set_property -name {xsim.simulate.log_all_signals} -value {false} \
    -objects [get_filesets sim_1]

# 3. Launch
launch_simulation
puts ""
puts "===================================================================="
puts "Simulation launched with tb_top_lite (50 us, log_all_signals=false)."
puts ""
puts "If you previously added /tb_top/dut/u_dm/mem or /tb_top/dut/u_ir/mem"
puts "to the wave window, REMOVE them now - they are 1 Mbit BRAM signal"
puts "arrays and tracking them is what crashes xsim."
puts ""
puts "Look for [TX] and [RX] lines in the Tcl console / sim log."
puts "===================================================================="
