# Public snapshot verification

Checked on 4 November 2026.

- The Python standard-library reproduction script completed successfully. It recalculated the 66-record selected Angle9 results, matched the original summary counts, checked the 108 sensor cases and their three parents, and reproduced the reported median delays.
- `RUN_PORTFOLIO_DEMO` executed successfully in local MATLAB R2024a. CSV assertions, the original `gt_fast_lock_1ms` confidence-reset/irreversibility/normal/causality checks, and the 22-class label-count check passed.
- Both figures were exported by MATLAB from the saved CSVs and visually reviewed.
- Copied source/model/CSV/PDF files are hashed in `evidence/source_manifest.json`. The model is an intact SLX ZIP archive; source files were copied without changing their algorithm implementations.
- Public Markdown links and text files were checked for broken local references, machine-specific user paths, and credential-like strings.

These checks validate the public summary, demonstration, and selected lock behavior. They do not rerun Simulink, train the classifier, establish full source-disjoint generalization, or validate real-time/hardware performance. Sensor statistics remain a separate exploratory replay result.
