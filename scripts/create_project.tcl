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

# Add design sources (custom VHDL).  regs_pkg.vhd must come before
# regs.vhd so the package is analysed first.
set design_files [list \
    "$proj_dir/src/regs_pkg.vhd" \
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

# Mark the simulation-only sources so they are NEVER pulled into synthesis
# or implementation.  Why this matters:
#   * src/uproc_top_level.vhd is a pure-VHDL structural top used ONLY by
#     the testbench.  Synthesis must use the BD wrapper (uproc_top_level_wrapper),
#     not this file.  Leaving it enabled in synthesis makes Vivado pick the
#     wrong "uproc_top_level" (name collides with the BD design) and pulls
#     in the un-synthesisable irMem.vhd / dMem.vhd below.
#   * src/irMem.vhd / src/dMem.vhd use VHDL TEXTIO (file_open + readline)
#     to load the COE at elaboration time.  TEXTIO is a simulation-only
#     construct - Vivado synth tries to open "text.coe" with a relative
#     path, fails, and then errors out with mismatched array sizes when
#     the empty rom assignment doesn't match dout's width.
#     Synthesis instead uses the Block Memory Generator IPs created in
#     build_block_design.tcl, which load the COE through CONFIG.Coe_File.
set sim_only_files [list \
    "$proj_dir/src/uproc_top_level.vhd" \
    "$proj_dir/src/irMem.vhd" \
    "$proj_dir/src/dMem.vhd" \
]
foreach f $sim_only_files {
    if {[file exists $f]} {
        set_property used_in_synthesis     false [get_files $f]
        set_property used_in_implementation false [get_files $f]
    }
}

# Add COE files to the project so the irMem/dMem TEXTIO loaders can find them.
foreach coe_path [list "$proj_dir/coe/text.coe" "$proj_dir/coe/data.coe"] {
    if {[file exists $coe_path]} {
        add_files -norecurse $coe_path
    }
}

# Add simulation sources.  Both the original behavioural tb and the leaner
# tb_top_lite (which is friendlier to Vivado xsim's WDB / RAM usage) are
# added; the lite one is set as the default top because it is reliable on
# Windows.  Switch back to tb_top with:
#    set_property top tb_top [get_filesets sim_1]
foreach tb_path [list \
    "$proj_dir/sim/tb_top.vhd" \
    "$proj_dir/sim/tb_top_lite.vhd" \
] {
    if {[file exists $tb_path]} {
        add_files -fileset sim_1 -norecurse $tb_path
        set_property file_type {VHDL 2008} [get_files $tb_path]
    }
}
if {[file exists "$proj_dir/sim/tb_top_lite.vhd"]} {
    set_property top tb_top_lite [get_filesets sim_1]
} elseif {[file exists "$proj_dir/sim/tb_top.vhd"]} {
    set_property top tb_top [get_filesets sim_1]
}

# Cap the xsim run-time and disable "log all signals" - this is what stops
# the BRAM `mem` arrays in irMem/dMem from being pulled into the WDB and
# crashing xsim with out-of-memory.
set_property -name {xsim.simulate.runtime}         -value {50us} \
    -objects [get_filesets sim_1]
set_property -name {xsim.simulate.log_all_signals} -value {false} \
    -objects [get_filesets sim_1]

# Add the default wave configuration files (lab manual layout).  The
# tb_top_lite layout takes precedence because tb_top_lite is the default
# sim top, but both are kept in the project so switching tops only needs
# `set_property xsim.view`.
foreach wcfg [list \
    "$proj_dir/sim/tb_top_lite.wcfg" \
    "$proj_dir/sim/tb_top.wcfg" \
] {
    if {[file exists $wcfg]} {
        add_files -fileset sim_1 -norecurse $wcfg
    }
}
if {[file exists "$proj_dir/sim/tb_top_lite.wcfg"]} {
    set_property xsim.view "$proj_dir/sim/tb_top_lite.wcfg" [get_filesets sim_1]
} elseif {[file exists "$proj_dir/sim/tb_top.wcfg"]} {
    set_property xsim.view "$proj_dir/sim/tb_top.wcfg" [get_filesets sim_1]
}

# Add XDC.
if {[file exists "$proj_dir/xdc/zybo_lab5.xdc"]} {
    add_files -fileset constrs_1 -norecurse "$proj_dir/xdc/zybo_lab5.xdc"
}

# Set absolute COE paths as generics on uproc_top_level (for synthesis) and
# on tb_top (for behavioural simulation) so the project is portable across
# macOS / Linux / Windows without editing any VHDL.
set text_coe_abs [file normalize "$proj_dir/coe/text.coe"]
set data_coe_abs [file normalize "$proj_dir/coe/data.coe"]

set_property generic [list \
    "TEXT_COE=$text_coe_abs" \
    "DATA_COE=$data_coe_abs" \
] [get_filesets sources_1]

set_property generic [list \
    "TEXT_COE=$text_coe_abs" \
    "DATA_COE=$data_coe_abs" \
] [get_filesets sim_1]

# NOTE: the synthesis top is intentionally NOT set here.  It will be set to
# `uproc_top_level_wrapper` by build_block_design.tcl after the BD wrapper
# is generated.  Setting it now to "uproc_top_level" would resolve to the
# simulation-only VHDL entity (excluded from synth above) which would then
# fail synthesis with un-synthesisable TEXTIO COE loaders.

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts ""
puts "===================================================================="
puts "Project '$proj_name' created at $proj_dir/$proj_name"
puts "Part:        $part"
puts "Synth top:   <unset> -- will be set to uproc_top_level_wrapper by"
puts "             scripts/build_block_design.tcl"
puts "Sim top:     tb_top_lite (override with: set_property top tb_top \[get_filesets sim_1\])"
puts ""
puts "Next steps:"
puts "  1. Build the block design + wrapper (REQUIRED before synth):"
puts "       source scripts/build_block_design.tcl"
puts "  2. Optional: launch behavioral sim:"
puts "       source scripts/run_sim.tcl"
puts "  3. Run synthesis:"
puts "       launch_runs synth_1 -jobs 4"
puts "       wait_on_run synth_1"
puts "  4. Run implementation + bitstream:"
puts "       launch_runs impl_1 -to_step write_bitstream -jobs 4"
puts "       wait_on_run impl_1"
puts "  5. Open hardware manager and program the Zybo Z7-10."
puts "===================================================================="
