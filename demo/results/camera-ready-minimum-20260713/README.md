# Camera-ready benchmark results

`runs.csv` contains the three complete trials used in the paper, and
`summary.md` is generated from those rows by `demo/summarize-results.py`.
The matching complete logs are `run-1.log`, `run-2.log`, and
`run-3-rerun.log`.

The first attempt at trial 3 was interrupted after the outer two-hour command
timeout expired. Its log is retained as `run-3-interrupted.log`. An estimated
row was briefly reconstructed from metric snapshots, then rejected because
the exact post-warm-up baseline could not be recovered. It is preserved only
in `runs-with-recovered-row.csv` for auditability and is not used by the paper
or the aggregate summary. Trial 3 was subsequently rerun in full.
