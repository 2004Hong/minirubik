# Test tools

Run commands from this `tests` directory in Windows PowerShell. Existing measurements are in the sibling `../results` directory. Runs create new timestamped folders rather than replacing existing records.

## Native C comparison

Build `../c_file/CAHw_IDA.c` and `../c_file/CAHw_IDA_improve.c` in Release/x64. Pass the actual executable paths; executables are not included in the submission:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run_c_compare_v2.ps1 -OriginalExe "C:\path\to\original.exe" -OptimizedExe "C:\path\to\optimized.exe"
```

If no executable paths are given, the script expects `CAHw_IDA.exe` and `CAHw_IDA_improve.exe` inside `../c_file`. Each of three inputs is tested three times per version. Results go to `../results/c_compare/`.

## Target model checks

Generate the final renderer-free source first:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\rv32i\final\build.ps1 -Version final -Render 0
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run_models.ps1
```

The model runner defaults to `C:\Ripes\Ripes.exe` and `../rv32i/final/cli.s`. Use `-RipesExe` or `-SolverFile` to override. It tests solved, one-move and required distance-11 inputs on RV32_ISS and RV32_5S. Results go to `../results/models/`.

## Distance-11 sweep

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run_depth11_tests.ps1 -Count 2644
```

The default without `-Count` is a five-case pilot. Inputs are `depth11_inputs.txt`: 2,644 unique states whose exact BFS distance is 11. `export_depth11.c` generates this file using a host BFS; build it as native C in Release/x64 and run from the intended output directory. Results go to `../results/depth11/`.

All three runners accept `-OutputRoot` to choose another results location. Test results include the current source/binary hashes where applicable. Original manifests keep the paths and names used when those measurements were made.

## Ripes baseline measurements

`ripes_baseline/` contains the rate loop, three memory loops, and memory measurement script. For memory measurement:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ripes_baseline\measure_ripes_memory.ps1 -TestDirectory .\ripes_baseline
```

For rate measurement, run `ripes_baseline/ripes_rate.s` on RV32_ISS and RV32_5S using `--iret --exectime`, three fresh processes per model. Original six measurements are under `../results/ripes_baseline/rate/`. Original memory measurements are under `../results/ripes_baseline/memory/`.
