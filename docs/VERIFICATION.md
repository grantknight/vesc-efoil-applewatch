# Verification record

## Reviewed branch update, 5 October 2026

Branch `claude/nifty-bohr-hou2sb`. Application source: `c75abfc601c0e3eecab862273bd3589818f7c0e2`; later commits on the branch change documentation only. Changes: publish-time-fresh GPS speed in the shared snapshot, non-destructive connection cancel, restored hero speed dominance with the preview-parity compass dial (plus the review-driven dial-floor bound in `846a5f8`), removal of unused ETA smoothing, and a portable browser verification suite that records which browser ran.

### Executed evidence

- [GitHub Actions run 37272394018](https://github.com/grantknight/vesc-efoil-applewatch/actions/runs/37272394018) (`workflow_dispatch`, exact head `c75abfc`) completed successfully: three independent macOS-15 jobs (seeds 101/202/303) each passed the portable test step (`swift test --parallel`; the suite holds 77 XCTest functions and the step fails on any failure), built the Watch app and complication, launched all six demo scenes on 40/42/46 mm simulators with still-running checks, and uploaded 12 evidence files per seed including the six scene screenshots. Artifacts (14-day retention, expire 2026-10-19): `watch-verification-101` id 11329440980 sha256 `93c5ce509bbea11ff1ee3e5283deecbcc5e5fe2b0a14723128b26f9d8e17dc7a`, `watch-verification-202` id 11329480895 sha256 `77a72ce2936c26e803d9540bf146632298883517b1c2cf72631bc3641d8f1375`, `watch-verification-303` id 11328786504 sha256 `5b1dc11cddea4eb0a4573828ad770405bbd7646257f59e15eaa39a05bfc7d27b`. An earlier dispatch at intermediate commit `322625d` ([run 37271687921](https://github.com/grantknight/vesc-efoil-applewatch/actions/runs/37271687921)) also completed with every step green.
- Browser suite `scripts/preview-test.mjs` executed in the Linux work session at the same source: PASS, 3×100 assertions at widths 1280/736/320, zero page errors, Chromium 141.0.7390.37, preview source SHA-256 `4635bb607a6df58addddb293a9fe221e2e9b94dfce32aaae26758a7523faf782` (byte-identical to the 4 October preview). Receipt: [preview-results.json](verification/2026-10-05/preview-results.json). One scoped reviewer re-executed the suite independently with Playwright's own Chromium and reproduced PASS.
- `node preview/test_preview.cjs` PASS and `node Tests/jev-gate.test.mjs` PASS (seven offline deterministic-gate cases, zero network requests).
- Protocol spot-verification against a fresh shallow clone of upstream `vedderb/bldc`: `COMM_GET_VALUES_SELECTIVE` (50), `COMM_GET_VALUES_SETUP_SELECTIVE` (51) and `COMM_GET_STATS` (128) response mask echo, field order, widths and scales, and the 34-entry `mc_fault_code` table all match `VescTelemetryDecoder`, `VescRequestQueue` and `VescFaultCode` exactly.
- Three scoped reviews by independent AI reviewer contexts that did not author the changes (these are model contexts, not human reviewers): radio/state approved with two cosmetic notes (one fixed, one recorded below); UI/layout requested and received the dial-floor fix before approval conditions were met; scripts/cleanup requested the documentation updates and browser-identity recording delivered on this branch.

### Not executed and open notes

- **No Jev evidence decisions.** `OPENROUTER_API_KEY` is not present in this environment and the gate refuses without it; Grant's requested three clean Jev assessments for this changed implementation remain outstanding. The 4 October PASS decisions bind to `97d32aa` only.
- **Native screenshots not visually reviewed.** The work session's egress policy blocked downloading the run-35 artifacts, so the 18 new PNGs exist only in the Actions artifacts above. Inspect them (hero speed larger than the tiles, dial rendering including the facet seam, C1–C12 fit) from any environment with artifact access before the artifacts expire, and retain them here if they pass.
- No local `swift test` or Xcode build ran in the Linux session; all Swift execution evidence is the CI runs above. Physical Watch signing/installation, dual-link hardware BLE, outdoor GPS, Water Lock/background endurance and on-water acceptance remain unperformed.
- Precision notes from review: commit `91912dc`'s "cannot be pushed out of the hero row on any Watch size" only became true with `846a5f8`; its "at least five points above the tile value size" tapers to about three points below ~120 pt of geometry while speed remains strictly larger. Accepted cosmetic nit: with no speed provider the snapshot's stored unit falls back to `mph`; speed is nil then and nothing renders it.

## Verified implementation, 4 October 2026

Application source: `97d32aa134fb9502c9b8b8948c6389d7db390dcc`.

[GitHub Actions run 37205002808](https://github.com/grantknight/vesc-efoil-applewatch/actions/runs/37205002808) completed successfully. Three independent clean Mac jobs (101/202/303) each passed 77 XCTest cases and 3,000 differently seeded packet-fragmentation cases (9,000 total), built the Watch app and embedded complication, and launched six native scenes. The scenes were dashboard, navigation, fault, destination, BMS sample and BMS unavailable. Each remained running after eight seconds and produced a screenshot. Watch sizes were 40, 42 and 46 mm.

All 18 native screenshots received independent visual review, including C1–C12 fitting on the smallest Watch and the complete ESC strip beneath temperature/voltage. The browser preview passed 100 assertions at widths 1280, 736 and 320 (300 total), zero JavaScript errors; source SHA-256 was `4635bb607a6df58addddb293a9fe221e2e9b94dfce32aaae26758a7523faf782`.

Three independent scoped councils approved peer-authored work, excluding self-review. OpenRouter Jev then returned three actual PASS decisions for that exact revision, with confidence 0.95 / 0.92 / 0.94, using `typesafe/jev-1.13-20260917`. Its deterministic gate verified actual CI and artifact/source hashes first. Jev assessed the evidence; it did not execute tests or inspect images. Recorded total cost was $0.000722484.

## Retained evidence

[Dated archive](verification/2026-10-04/) contains the GitHub job receipt, browser results, three council reports, native visual review, executed-evidence summary, Jev response receipt and all 18 native screenshots. Original reports retain their original workspace-relative artifact paths and hashes for provenance. Their `verification/mac-ready-37205002808/watch-verification-SEED/` images map to the archive's `images/watch-verification-SEED/`; other original build/test logs remain in the GitHub run artifacts (14-day retention) and are not committed. These records describe the old exact implementation revision, not an assertion that every original working artifact is present forever.

Do not submit this historical summary directly to the current Jev gate: its exact-HEAD/clean-tree/artifact checks deliberately require newly executed evidence for a changed source revision. The 5 October handover changes documentation and copies historical receipts/screenshots only; no application behavior is changed and no fresh application test run is claimed for that documentation commit.

## Explicitly unfinished acceptance

- Actual BMS vendor-specific per-cell decoding, pending brand/model/firmware or current phone app. Live cell snapshot is nil; the populated screen is synthetic.
- Simultaneous VESC/BMS physical BLE compatibility and measured voltage/current/ESC/fault/cell agreement.
- Apple signing, physical Watch installation, outdoor GPS/bearing, Water Lock/background runtime, endurance and on-water use.
- App Store/TestFlight publication.

See [MAC_HANDOFF.md](../MAC_HANDOFF.md) for required device acceptance, and [MASTER_PROMPT.md](../MASTER_PROMPT.md) for full intent, architecture and continuation steps.
