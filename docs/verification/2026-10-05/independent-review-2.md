# Independent review summary, battle testing and interface (5 October 2026)

Scope: `8fdfac3..f53f19c` (stress tests, distance rounding, wrist-down workout session, BMS reconnect, compass accuracy, map pin guard, complication small slots, connection-screen save confirmation, wrist-down demo scene), then the fixes in `f9b815a`. The reviewer was a separate Claude agent given the diff, the repository read-only and the review criteria. It did not write any of the changes and had no Swift compiler; compile verdicts are from reading. CI provides the actual compile and test evidence.

**First pass: CHANGES REQUESTED** (no blockers, no safety-rule violations).

| ID | Finding | Disposition |
|---|---|---|
| S1 | Workout session shipped while the brief still listed it as an open decision; brief not updated. | Brief updated. Grant asked for all work to be finished before he is involved; the design is recorded as unverified on hardware. Kept on PR #4. |
| S2 | One stress test iterated Dictionary keys (per-process hash order), so it was not reproducible from its seed. | Fixed: keys sorted. |
| S3 | Ride page claimed background running before HealthKit confirmed it. | Fixed: status turns running only on the `.running` state callback. |
| S4 | Health permission sheet first appeared at ride start; an unanswered sheet left "Starting…" indefinitely. | Fixed: Settings offers the permission ahead of a ride; start times out after 30 s; a late answer still starts the session. |
| S5 | Background location enabled whether or not a ride was recording. | Fixed: enabled only while recording. |
| S6 | BMS page could keep "Reconnecting (attempt 6 of 6)" after retries stopped. | Fixed: final "did not reconnect" message and unavailable state. |
| N1 | Native vs preview rounding differed at exact binary ties (1125 m). | Fixed in both, with a native test. |
| N2 | Map hint said "No GPS fix" when merely zoomed out. | Fixed. |
| N3 | No visible control to stop a pending BMS reconnect. | Open (documented). |
| N4 | A link that connects then drops immediately is retried indefinitely. | Open (documented). |
| N5 | Workout edge cases: back-to-back sessions, crash recovery, App Review framing. | Open (documented; hardware check). |
| N6 | Wall-clock assertion in a stress test. | Removed. |
| N7 | `battery.0` symbol name. | Changed to `battery.0percent`. |

**Second pass on `f9b815a`: APPROVE WITH NITS.** Two nits were fixed in `3707a2c` (a late permission answer still starts the session; a denied permission is explained in Settings). One remains: an excluded-VESC edge case shows "did not reconnect" wording.

This summary is not a council PASS or a Jev decision.
