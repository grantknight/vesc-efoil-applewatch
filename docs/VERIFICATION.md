# Verification record

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
