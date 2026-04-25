###############################################################################
# create_project.tcl - Bootstraps the Lab 5 GRISC processor project.
#
# Run from inside Vivado:
#   File -> Project -> New (cancel any wizard), then in the Tcl Console:
#       cd /Users/parthapediredla/lab5
#       source scripts/create_project.tcl
#
# Or from the command line:
#       cd /Users/parthapediredla/lab5
#       vivado -mode batch -source scripts/create_project.tcl
#
# The result is a complete project ready for synthesis/implementation/bitstream
# with `uproc_top_level` as the synthesis top entity.
###############################################################################

set proj_name  "lab5_grisc"
set proj_dir   [file normalize "[file dirname [info script]]/.."]
set part       "xc7z010clg400-1"

# Create the project (overwrite if it already exists).
if {[file exists "$proj_dir/$proj_name"]} {
    puts "Removing existing project at $proj_dir/$proj_name ..."
    file delete -force "$proj_dir/$proj_name"
}
create_project $proj_name "$proj_dir/$proj_name" -part $part
set_property target_language VHDL [current_project]
set_property simulator_language Mixed [current_project]

# Add design sources (custom VHDL).
set design_files [list \
    "$proj_dir/src/clock_div.vhd" \
    "$proj_dir/src/clock_div_25.vhd" \
    "$proj_dir/src/debounce.vhd" \
    "$proj_dir/src/my_alu.vhd" \
    "$proj_dir/src/regs.vhd" \
    "$proj_dir/src/framebuffer.vhd" \
    "$proj_dir/src/vga_ctrl.vhd" \
    "$proj_dir/src/pixel_pusher.vhd" \
    "$proj_dir/src/uart.vhd" \
    "$proj_dir/src/controls.vhd" \
    "$proj_dir/src/irMem.vhd" \
    "$proj_dir/src/dMem.vhd" \
    "$proj_dir/src/uproc_top_level.vhd" \
]
foreach f $design_files {
    if {[file exists $f]} {
        add_files -norecurse $f
    } else {
        puts "WARNING: missing source $f - add it before synthesis."
    }
}

# Set file types:
#   - VHDL-2008 for the files that genuinely need it (TEXTIO COE loaders).
#   - Plain VHDL (-93) for everything else, because IP Integrator Module
#     References cannot reference a VHDL-2008 file (Vivado restriction).
set vhdl2008_files [list \
    "$proj_dir/src/irMem.vhd" \
    "$proj_dir/src/dMem.vhd" \
]
foreach f $design_files {
    if {[file exists $f]} {
        if {[lsearch -exact $vhdl2008_files $f] >= 0} {
            set_property file_type {VHDL 2008} [get_files $f]
        } else {
            set_property file_type {VHDL} [get_files $f]
        }
    }
}

# Add COE files to the project so the irMem/dMem TEXTIO loaders can find them.
foreach coe_path [list "$proj_dir/coe/text.coe" "$proj_dir/coe/data.coe"] {
    if {[file exists $coe_path]} {
        add_files -norecurse $coe_path
    }
}

# Add simulation sources.
if {[file exists "$proj_dir/sim/tb_top.vhd"]} {
    add_files -fileset sim_1 -norecurse "$proj_dir/sim/tb_top.vhd"
    set_property file_type {VHDL 2008} [get_files "$proj_dir/sim/tb_top.vhd"]
    set_property top tb_top [get_filesets sim_1]
}

# Add the default wave configuration file (lab manual layout).
if {[file exists "$proj_dir/sim/tb_top.wcfg"]} {
    add_files -fileset sim_1 -norecurse "$proj_dir/sim/tb_top.wcfg"
    set_property xsim.view "$proj_dir/sim/tb_top.wcfg" [get_filesets sim_1]
}

# Add XDC.
if {[file exists "$proj_dir/xdc/zybo_lab5.xdc"]} {
    add_files -fileset constrs_1 -norecurse "$proj_dir/xdc/zybo_lab5.xdc"
}

# Set absolute COE paths as generics on uproc_top_level so synthesis can find them.
set_property generic [list \
    TEXT_COE=$proj_dir/coe/text.coe \
    DATA_COE=$proj_dir/coe/data.coe \
] [current_fileset]

# Set the synthesis top.
set_property top uproc_top_level [current_fileset]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts ""
puts "===================================================================="
puts "Project '$proj_name' created at $proj_dir/$proj_name"
puts "Part:        $part"
puts "Synth top:   uproc_top_level"
puts "Sim top:     tb_top"
puts ""
puts "Next steps:"
puts "  1. Optional: launch behavioral sim:"
puts "       launch_simulation"
puts "  2. Run synthesis:"
puts "       launch_runs synth_1 -jobs 4"
puts "       wait_on_run synth_1"
puts "  3. Run implementation + bitstream:"
puts "       launch_runs impl_1 -to_step write_bitstream -jobs 4"
puts "       wait_on_run impl_1"
puts "  4. Open hardware manager and program the Zybo Z7-10."
puts "===================================================================="
