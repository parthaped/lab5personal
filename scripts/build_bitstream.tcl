###############################################################################
# build_bitstream.tcl - Run synth + impl + bitstream end-to-end.
#
# Run from a shell with Vivado in the PATH:
#     cd /Users/parthapediredla/lab5
#     vivado -mode batch -source scripts/build_bitstream.tcl
#
# Or from inside Vivado after sourcing create_project.tcl:
#     source scripts/build_bitstream.tcl
###############################################################################

set proj_name  "lab5_grisc"
set proj_dir   [file normalize "[file dirname [info script]]/.."]

# If the project isn't open yet, source create_project.tcl first.
if {[catch {current_project} _]} {
    if {[file exists "$proj_dir/$proj_name/$proj_name.xpr"]} {
        open_project "$proj_dir/$proj_name/$proj_name.xpr"
    } else {
        puts "Project not found, creating it first..."
        source [file join [file dirname [info script]] create_project.tcl]
    }
}

# Synthesis
puts "===================================================================="
puts "Running synthesis..."
puts "===================================================================="
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "Synthesis failed."
}

# Implementation + bitstream
puts "===================================================================="
puts "Running implementation and bitstream generation..."
puts "===================================================================="
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "Implementation failed."
}

set bitfile "$proj_dir/$proj_name/$proj_name.runs/impl_1/uproc_top_level.bit"
puts ""
puts "===================================================================="
puts "Bitstream generated:"
puts "  $bitfile"
puts ""
puts "To program the Zybo Z7-10:"
puts "  open_hw_manager"
puts "  connect_hw_server"
puts "  open_hw_target"
puts "  set_property PROGRAM.FILE \"$bitfile\" \[get_hw_devices xc7z010_1\]"
puts "  program_hw_devices \[get_hw_devices xc7z010_1\]"
puts "===================================================================="
