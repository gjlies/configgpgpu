# configgpgpu
A configurable general purpose graphics processing unit for power, performance, and area analysis

The RTL folder contains all SystemVerilog files for a configurable GPGPU modeled after the Tesla Architecture.  Top contains the top level GPGPU file as well as the multiprocessor.  For simulation, I recommend using gpgpu.sv, and providing your own memory initialization file to initialize the contents of the kernel cache.  For synthesis, only synthesize a single multiprocessor with the desired configurations.

The Instructions Excel Sheet gives detailed information about the supported instructions.  This sheet covers the pipeline instructions as well as kernel instructions required for simulation.  The ldst sheet shows how to access block and thread special data by using the load special instruction.
