# Measurement records

## C comparison

`c_compare/` contains the original measurements from the other test computer:

- `summary.csv`: comparison summary for the original and optimized C programs.
- `results.csv`: all 18 runs (three inputs, two versions, three repetitions); all passed.
- `manifest.json`: test environment, timing scope, and executable hashes.
- `logs/Original/`: 27 files containing the original program's combined, stdout, and stderr logs.
- `logs/Optimized/`: 27 files containing the optimized program's combined, stdout, and stderr logs.

These are the original records; no replacement measurements were generated during file organization.

## Assembly version comparison

`history/` contains the required 11-move input measurements for the two earlier versions presented in the report:

- `baseline_iss_11.txt`: baseline, 31,858,748 retired instructions.
- `opt1_iss_11.txt`: the report's opt1 (formerly opt3), 27,691,761 retired instructions.

The report's final opt2 was formerly named opt4. Its measurements are stored under `models/`.

## Final opt2 processor measurements

- `models/opt2_result/`: all six original runs covering solved, one-move, and required 11-move inputs on ISS and the five-stage processor. The folder includes `results.csv`, `manifest.json`, and each run's console, error, and metric logs. All six runs passed.
- `models/opt2_size.txt`: final opt2 section sizes: `.text` = 1,796 bytes and `.data` = 40,612 bytes. The original tool output retains the old opt4 executable path.

## All states at distance 11

`depth11/depth11_opt4_20261007/` contains the original full sweep for final opt2 (formerly opt4):

- `results.csv`: all 2,644 test results; all passed.
- `all_11_path_result/`: 7,932 individual console, error, and metric logs (three files per case).
- `inputs_snapshot.txt`: the exact input list used for the sweep.
- `solver_snapshot.s`: a copy of the program at the start of the sweep.
- `current_case.s`: the generated working source left after the last test case.
- `manifest.json`: the original test settings and version information.

The folder name retains the historical opt4 name; it refers to the report's final opt2.

## Ripes baseline measurements

`ripes_baseline/rate/` contains the original simulation-rate measurements. `ripes_baseline/memory/` contains the original host-memory measurements and summaries.

H1-H3 verification records remain under `../verify/`. GCC reference records remain under `../gcc_reference/results/`.

Manifests and raw tool output retain the paths and version names used when the tests were run. Those historical paths do not need to match the reorganized submission folders.
