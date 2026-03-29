# TODO: Update source list as modules are implemented
# Makefile for Tetris SystemVerilog simulation
# Supports Vivado xsim

SRCS = $(filter-out tb_%.sv,$(wildcard *.sv))
TB   = tb_top.sv
TOP  = tb_top

# --- Vivado xsim ---
xsim: $(SRCS) $(TB)
	xvlog -sv $(SRCS) $(TB)
	xelab $(TOP) -s sim_snapshot --timescale 1ns/1ps
	xsim sim_snapshot -runall

clean:
	rm -rf xsim.dir *.jou *.log *.pb *.wdb .Xil
	rm -rf build/ sim_snapshot.wdb
	rm -f frame.ppm

.PHONY: xsim clean
