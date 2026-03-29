# TODO: Update for Tetris project
# - Source file list: tetris_top.sv + all submodules (see PLAN.md Section 7)
# - Top module: tetris_top
# - XDC: nexys_a7.xdc (update for Tetris pins including SW, DP, audio)
#
# Vivado Synthesis + Implementation for Tetris on Nexys A7-100T
# Usage: vivado -mode batch -source synth.tcl

set proj_dir [file dirname [info script]]

# Create project
create_project -force tetris ${proj_dir}/build -part xc7a100tcsg324-1

# Add all synthesizable sources (exclude tb_*)
foreach f [glob -nocomplain ${proj_dir}/*.sv] {
    if {![string match "*/tb_*" $f]} {
        add_files -fileset sources_1 $f
    }
}

# Add constraints
add_files -fileset constrs_1 ${proj_dir}/nexys_a7.xdc

# Set top
set_property top tetris_top [current_fileset]
update_compile_order -fileset sources_1

# Synthesis
synth_design -top tetris_top -part xc7a100tcsg324-1
report_utilization -file ${proj_dir}/build/utilization.txt
report_timing_summary -file ${proj_dir}/build/timing.txt

# Implementation
opt_design
place_design
route_design

# Reports
report_utilization -file ${proj_dir}/build/utilization_post.txt
report_timing_summary -file ${proj_dir}/build/timing_post.txt

# Generate bitstream
write_bitstream -force ${proj_dir}/build/top.bit

puts "========================================="
puts "Bitstream generated: build/top.bit"
puts "========================================="

close_project
