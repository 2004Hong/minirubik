# GCC RV32I reference

`solver_gcc_rv32i.c` adapts the optimized native C solver to Ripes: precomputed tables are embedded, host timing/statistics and runtime BFS are removed, and output uses Ripes ecalls. The search remains on the target. It is not the unmodified native C file.

- `gcc_start.s`: entry point and a 4096-byte stack.
- `gcc_link.ld`: section placement and entry-point configuration.
- `build.ps1`: complete compile/link commands and section-size measurement.
- `results/gcc_iss_11.txt`, `results/gcc_iss_11_console.txt`: original required-vector measurements/output.
- `results/gcc_iss_short.txt`, `results/gcc_iss_short_console.txt`: original one-move measurements/output.
- `results/gcc_size.txt`, `results/compiler_version.txt`: generated section sizes and compiler version.

The supplied input is `21345671111111`. The short-case records use `25314672313211`. Change `cube_input` and rebuild to test another input.

## Build in Windows PowerShell

Run from this folder. Replace the toolchain path with the installed RISC-V GCC `bin` directory:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -ToolchainBin "C:\path\to\riscv-gcc\bin"
```

The original reference used xPack RISC-V GCC 15.2.0. The build produces `solver_gcc_rv32i.s` and `solver_gcc_rv32i.elf`. Both can be regenerated from the supplied sources. The script creates the results directory if needed and writes compiler_version.txt and gcc_size.txt there.

## Ripes measurement

Use the pinned Ripes build v2.2.6-106-g5b8a616. Run from this folder and keep the ELF path relative (the loader may fail with a non-ASCII absolute path):

```powershell
& 'C:\Ripes\Ripes.exe' --mode cli --src solver_gcc_rv32i.elf -t elf --proc RV32_ISS --iret --cycles --exectime --output results/rerun_metrics.txt
```

Original required-vector results: 27,458,618 retired instructions, 1,320 bytes of linked `.text`. Code size excludes tables and renderer; no LED renderer is included in this reference. Retain original logs separately from reruns.
