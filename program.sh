#!/bin/bash
# Program FPGA with top.bit via Vivado in Docker
BIT=${1:-build/top.bit}

if [ ! -f "$BIT" ]; then
    echo "Error: $BIT not found"
    exit 1
fi

docker run --rm \
  -v "$(realpath "$BIT")":/work/top.bit \
  -v /home/sihun/Xilinx:/home/sihun/Xilinx \
  -v /home/sihun/.Xilinx:/root/.Xilinx \
  --privileged \
  -v /dev/bus/usb:/dev/bus/usb \
  cva6-vivado:latest \
  bash -c '
export PATH=/home/sihun/Xilinx/2025.2/Vivado/bin:$PATH
export LD_LIBRARY_PATH=/home/sihun/Xilinx/2025.2/Vivado/lib/lnx64.o:$LD_LIBRARY_PATH
hw_server &
sleep 3
vivado -mode tcl <<TCLEOF
open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target
set dev [lindex [get_hw_devices] 0]
current_hw_device \$dev
set_property PROGRAM.FILE /work/top.bit \$dev
program_hw_devices \$dev
close_hw_manager
TCLEOF
'
