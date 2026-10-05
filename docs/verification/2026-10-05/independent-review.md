# Independent review summary, 5 October 2026

Scope: diff of `codex/review-and-ui-refinement` at `a8bded5` against `main` (`8c43c20`). The reviewer was a separate Claude agent given only the diff, the surrounding source and the review criteria (compile safety, freshness/fault honesty, demo isolation, small-Watch layout, preview parity, tests). It did not author any of the changes. It had no Swift compiler: its compile verdict is from reading, and it ran `node preview/test_preview.cjs` only.

**Verdict: APPROVE WITH NITS.** Nothing blocking; no compile or data-safety regressions found.

## Findings and disposition (fixed in `58352ba`)

| ID | Finding | Disposition |
|---|---|---|
| S1 | "Change VESC" used `restart()`, which keeps the saved controller, so the old VESC reconnects before another can be chosen. | Fixed: uses `restart(withNewDevice: true)`; alert says the active ride is saved. |
| S2 | Wrist-down state greyed tiles only; speed, destination lines and a green "ESC faults: None" stayed in live colours. | Fixed in native and preview: secondary colour, fault strip reads "raise wrist to check" in caution colour unless a fault is active. |
| S3 | Dashboard judged freshness with `Date()` rather than `timeline.date`. | Fixed. |
| S4 | Connection screen said "reconnecting" after a user cancel. | Fixed: "VESC not connected" when idle. |
| S5 | Snapshot unit fallback `.mph` while the app defaults to km/h. | Fixed: `.kph`. |
| S6 | Heading smoothing continuity window 3 s was stricter than the 10 s heading freshness. | Fixed: 10 s. |
| L1–L2 | Small-geometry layout arithmetic tight in gaps. | Adjusted dial and line sizing. |
| L3 | Native destination caption can fall below 9.5 pt on the smallest geometry (minimum scale 0.8). | Open; needs inspection of real 40 mm native render. |
| P1, P3 | Preview parity nits. | Fixed. |
| P2 | JS vs Swift rounding of exact .5 ties. | Not fixed; negligible. |
| Doc | MASTER_PROMPT test count stale. | Fixed. |

The reviewer's output was not used as Jev evidence and this summary is not a council PASS.
