# Lab 5 — GRISC ASIP on Zybo Z7-10

A 16-bit Application-Specific Instruction-Set Processor (GRISC) written in VHDL,
targeting the Digilent Zybo Z7-10 (`xc7z010clg400-1`) with Pmod VGA and Pmod
USBUART. The design fetches and executes a small assembly program that prints
`hello_world` over UART and clears / paints a 64×64 framebuffer to a VGA
display.

## Repository layout

```
src/         Custom VHDL design files
sim/         GHDL testbench
coe/         Memory init files (text.coe = irMem, data.coe = dMem)
xdc/         Zybo Z7-10 + Pmod VGA constraints
scripts/     Vivado Tcl scripts and headless assembler driver
```

### Design modules (`src/`)

| Module                | Purpose                                                         |
|-----------------------|-----------------------------------------------------------------|
| `my_alu.vhd`          | 16-bit synchronous ALU with the spec opcode table                |
| `regs.vhd`            | True dual-port 32×16 register file (`$zero` write-protected)     |
| `framebuffer.vhd`     | 4096×16 dual-port BRAM with rolling clear                        |
| `vga_ctrl.vhd`        | 640×480 @ 60 Hz VGA timing                                       |
| `pixel_pusher.vhd`    | 5:6:5 pixel slicing + 64×64 window addressing                    |
| `uart.vhd`            | 8N1 UART, counter-based bit timing (`CLKS_PER_BIT`)              |
| `controls.vhd`        | Multi-cycle FSM covering fetch/decode + the 8 required ops       |
| `irMem.vhd`           | 32-bit × 16384 instruction ROM, COE-loaded via TEXTIO            |
| `dMem.vhd`            | 16-bit × 32768 data RAM, COE-loaded via TEXTIO                   |
| `clock_div.vhd`       | Generic clock-enable generator                                   |
| `clock_div_25.vhd`    | 25 MHz pixel clock-enable                                        |
| `debounce.vhd`        | Synchronous button debouncer                                     |
| `uproc_top_level.vhd` | Flat structural top wiring everything per Figures 5.2/5.3        |

## Behavioral simulation (GHDL)

```bash
cd build
ghdl -a --std=08 ../src/*.vhd ../sim/tb_top.vhd
ghdl -e --std=08 tb_top
ghdl -r --std=08 tb_top --vcd=tb_top.vcd --stop-time=200us --ieee-asserts=disable
```

Expected output:

```
[TX] 0x68  'h'
[TX] 0x65  'e'
[TX] 0x6C  'l'
[TX] 0x6C  'l'
[TX] 0x6F  'o'
[TX] 0x5F  '_'
[TX] 0x77  'w'
[TX] 0x6F  'o'
[TX] 0x72  'r'
[TX] 0x6C  'l'
[TX] 0x64  'd'
[RX] driving 0x41
[RX] driving 0x5A
```

## Vivado flow

On a machine with Vivado installed:

```bash
vivado -mode batch -source scripts/create_project.tcl
vivado -mode batch -source scripts/build_bitstream.tcl
```

Then in the Vivado Hardware Manager, program the Zybo Z7-10 with
`lab5_grisc/lab5_grisc.runs/impl_1/uproc_top_level.bit`. Press the user button
to release reset; `hello_world` should appear over the Pmod USBUART and the
64×64 image rendered on the Pmod VGA.

## Memory initialization

Regenerate `coe/text.coe` and `coe/data.coe` from a GRISC assembly program:

```bash
python3 scripts/assemble_headless.py path/to/program.asm
```
