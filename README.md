# minirubik — Computer Architecture Homework 1

This repository is a fork of [sysprog21/minirubik](https://github.com/sysprog21/minirubik). The homework replaces the original full-state BFS solver with IDA*, optimizes the C implementation, and implements the solver in handwritten RV32I assembly with an LED Matrix demonstration in Ripes.

The search uses the half-turn metric (HTM): each of `R R2 R' B B2 B' D D2 D'` counts as one move. The heuristic is `max(permutation distance, orientation distance)`.

- [HackMD report](https://hackmd.io/Ip8LuF4YS6KXOfkMWEEhLQ)
- [Test instructions](tests/README.md)
- [Measurement records](results/README.md)
- [GCC reference instructions](gcc_reference/README.md)

## Repository Layout

```text
minirubik/
├── README.md
├── solver.c                     # Original upstream BFS solver
├── mini.c                       # Original upstream program
├── c_file/
│   ├── CAHw_IDA.c               # Initial IDA* implementation
│   └── CAHw_IDA_improve.c       # Optimized IDA* implementation
├── rv32i/
│   ├── history/
│   │   ├── baseline.s          # Initial RV32I implementation
│   │   ├── opt1.s              # First reported optimization
│   │   └── opt2.s              # Final reported optimization
│   └── final/
│       ├── solver.s            # Shared search and LED source
│       ├── build.ps1           # Generates CLI or LED assembly
│       ├── cli.s               # Renderer disabled; used for measurements
│       └── led.s               # Renderer enabled; used for GUI demonstration
├── verify/
│   ├── CAHW_IDA_improve_verify.c
│   └── verify_release_results.txt
├── tests/                      # Test scripts, input lists, and input generator
├── results/
│   ├── c_compare/              # Native C timing and search-node comparison
│   ├── history/                # Baseline and opt1 instruction measurements
│   ├── models/                 # Final opt2 model measurements and section sizes
│   ├── depth11/                # All 2,644 distance-11 test results
│   └── ripes_baseline/         # Simulation throughput and host-memory records
└── gcc_reference/              # GCC target source, startup, linker script,
                                # build script, and measurement records
```

## Build and Run

The native C programs were measured using Visual Studio 2026 Insiders 18.10.3 with the **Release/x64** configuration. Target measurements use **Ripes v2.2.6-106-g5b8a616**, with `RV32_ISS` and `RV32_5S`. The GCC reference uses **xPack RISC-V GCC 15.2.0** with `-O2 -march=rv32i -mabi=ilp32`.

### Native C

Build `c_file/CAHw_IDA.c` and `c_file/CAHw_IDA_improve.c` as separate native C programs in Release/x64. Executables are not included. From the repository root, run the optimized executable using its actual build location:

```powershell
& "C:\path\to\CAHw_IDA_improve.exe" 21345671111111 11
```

The first argument contains seven permutation digits followed by seven orientation digits. The optional second argument is the maximum search depth, from 0 to 11.

To compare the two C versions, run from the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\run_c_compare_v2.ps1 -OriginalExe "C:\path\to\CAHw_IDA.exe" -OptimizedExe "C:\path\to\CAHw_IDA_improve.exe"
```

This tests three inputs, with three repetitions per version. Timing covers `solve_ida()`; table construction and final replay are excluded.

### RV32I CLI and LED

Run these commands from the repository root:

```powershell
# Generate cli.s for testing and instruction-count measurements.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\rv32i\final\build.ps1 -Version final -Render 0 -InputState 21345671111111

# Generate led.s for the GUI demonstration.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\rv32i\final\build.ps1 -Version final -Render 1 -InputState 21345671111111
```

Both generated versions use the same solver and lookup tables. For the LED demonstration, create **LED Matrix 1**, set **Width 35** and **Height 25**, load `rv32i/final/led.s` in Ripes, and run. The display shows the input state and replays the computed solution. Successful physical-state replay prints `LED replay: 1`.

Instruction measurements use the CLI version with the renderer disabled.

### GCC Reference

The GCC comparison uses `gcc_reference/solver_gcc_rv32i.c`, an adaptation of the optimized C solver with embedded tables and Ripes ecalls. It is built with `gcc_start.s` and `gcc_link.ld`.

From `gcc_reference/`, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -ToolchainBin "C:\path\to\riscv-gcc\bin"
```

See [gcc_reference/README.md](gcc_reference/README.md) for the complete build and Ripes measurement commands.

## Verification and Test Results

### Host Verification: H1–H3

Build `verify/CAHW_IDA_improve_verify.c` in Release/x64 and run the resulting executable with `--self-test`. The program performs the full host verification before its additional self-tests:

```powershell
& "C:\path\to\CAHW_IDA_improve_verify.exe" --self-test
```

- **H1:** The heuristic does not exceed the true BFS distance for any of the 3,674,160 states.
- **H2:** Distance and transition tables pass their completeness and consistency checks.
- **H3:** All 3,674,160 states return solutions of the BFS-optimal length, and every solution solves the cube when replayed.

[Verification source](verify/CAHW_IDA_improve_verify.c) · [Complete verification output](verify/verify_release_results.txt)

### Target Verification: T5–T7

From the repository root, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\run_models.ps1
```

The script tests the solved state, a one-move input, and the specified eleven-move input on `RV32_ISS` and `RV32_5S`. All six archived runs pass the expected solution-length and replay checks.

[Model test results](results/models/opt2_result/results.csv) · [Model test script](tests/run_models.ps1)

For all states at distance 11:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\run_depth11_tests.ps1 -Count 2644
```

Without `-Count 2644`, the script defaults to a five-case pilot. The archived full sweep passes **2,644/2,644** cases. The maximum retired instruction count is **49,850,258**, for input `54721631111111`, below the 50,000,000-instruction limit.

[Complete distance-11 records](results/depth11/depth11_opt4_20261007/) · [Full-sweep CSV](results/depth11/depth11_opt4_20261007/results.csv)

The test scripts default to `C:\Ripes\Ripes.exe`; use `-RipesExe` to specify another installation. See [tests/README.md](tests/README.md) for additional options and the Ripes throughput and memory measurements.

## Version Comparison

These instruction measurements use input `21345671111111` on `RV32_ISS`, with LED rendering disabled.

| Version | Main changes | Retired instructions |
| --- | --- | ---: |
| baseline | Initial RV32I implementation of the optimized C design | 31,858,748 |
| opt1 | Inline heuristic, reuse the move cursor, and retain distance-table base addresses in registers | 27,691,761 |
| opt2 | Check nodes only on entry, decode moves with small tables, skip same-face groups, and prune early on permutation distance | 18,232,235 |

The report's **opt1 was formerly named opt3**, and **opt2 was formerly named opt4**. Original result filenames, manifests, and tool output retain the names and paths used at measurement time.

For the same input, the GCC -O2 reference retires **27,458,618** instructions. The linked `.text` sizes are **1,320 bytes** for GCC and **1,796 bytes** for opt2. The handwritten assembly uses approximately **33.6% fewer instructions**, with **476 bytes more code**, for this input.

The native C comparison reports **14 ms → 2 ms** for the eleven-move input, with identical counts of **38,998 expanded nodes** and **233,961 generated child nodes**. These times are medians of three runs.

- [Native C comparison summary](results/c_compare/summary.csv)
- [Baseline and opt1 measurements](results/history/)
- [Final opt2 measurements](results/models/opt2_result/)
- [Final opt2 section sizes](results/models/opt2_size.txt)
- [GCC measurements](gcc_reference/results/)

The HackMD report provides the algorithm explanations, optimization discussion, LED screenshots, and analysis. This repository provides the corresponding source code, test tools, and measurement evidence.
