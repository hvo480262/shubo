# Reproduction levels and file provenance

## 1. Recompute exported statistics

Run `python scripts/reproduce_results.py` from the project directory. Python 3.9+ and its standard library are sufficient. No additional Python packages, Simulink, network access, or hidden dataset are required. The check calculates results from per-record rows and compares counts to the original summary exports.

## 2. Regenerate plots and check lock logic

Run `RUN_PORTFOLIO_DEMO` from this directory in MATLAB R2024a. This runs from saved CSVs, checks the single/double/normal counts and selected-rule outcomes, and checks the archived lock routine using a small synthetic probability sequence. It does not simulate physical currents or reproduce classifier predictions. The generated PNGs and JSON are derived summaries, not additional experiments.

## 3. Inspect and rerun the original research code

`matlab/` contains 32 original open-circuit functions and five original entry points copied from the saved half-wave comparison project. Three selected sensor-prototype files are also included. The full raw-recording collection, prepared feature matrices, trained networks, prediction caches, and calibration artifacts are not included.

The original `RUN_AMPLITUDE_HALFWAVE_PAIR` needs the original Angle9 `trained_model.mat` (with its frozen manifest) and every raw recording referenced by that manifest. The original `RUN_VALIDATE_LOCK_THRESHOLD_PAIR` needs the paired experiment directory, its frozen trained models, validation raw data, and saved test predictions. These are advanced entry points for use with the original experiment assets, not one-click public demos.

Typical full-research requirements are MATLAB R2024a+, Deep Learning Toolbox, and Signal Processing Toolbox. Simulating `models/PMSM.slx` additionally requires Simulink and the products referenced by its blocks, which may include Simscape Electrical. Original experiment initialization and fault-injection scripts must also be supplied. Opening this archived model alone does not reproduce the saved CSV results.

Raw input records use `timeAbsolute` (N-by-1 increasing seconds), `iabc` (N-by-3 unnormalized currents), and metadata including fault type, speed, torque, pole pairs, and event time. Prefer measured electrical angle or measured speed for angle-domain features. Nominal-speed fallback is only a constant-speed assumption; it must not be presented as variable-speed validation. The feature routine uses current measurements and angle information, not fault labels, for its prediction inputs.

## Original export sources

| Public file | Original export |
|---|---|
| `open_circuit_records.csv` | `TEST_RECORDS_DEFAULT_VS_SELECTED.csv` |
| `open_circuit_summary.csv` | `TEST_SUMMARY.csv` |
| `validation_threshold_grid.csv` | `VALIDATION_THRESHOLD_GRID.csv` |
| `cross_role_source_groups.csv` | `CROSS_ROLE_SOURCE_GROUPS.csv` |
| `sensor_gain_records.csv` | `GAIN_test_records.csv` |
| `sensor_gain_parents.csv` | `GAIN_parent_summary.csv` |

The open-circuit exports belong to paired run `20261026_161433_031` and validation replay `VALIDATION_1MS_20261026_164038_265`. Sensor exports belong to `fast_gain_20261019_151950_766`. The source manifest records SHA-256 hashes for the exact copied source/model/CSV/PDF files, using relative source locations rather than machine-specific absolute paths.

## Ownership and assistance

Shubo Zhang reports the research activities and individual contributions described in the project overview. The archived model/source files retain their original content and metadata. The public README, presentation figures, CSV reproduction helper, and portfolio demo were prepared with AI assistance from the supplied project materials; these additions are not separate research results. No external paper's implementation or performance is claimed as an independently replicated result.
