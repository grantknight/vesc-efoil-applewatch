# Foil Assist: master project brief and AI handover

Updated: **5 October 2026**. Owner: **Grant Knight**. Repository: **grantknight/vesc-efoil-applewatch**. This file records the user's accepted direction and the actual state of the project; it is not a claim of a completed hardware release.

## Start here

Continue developing this repository without requiring Grant to repeat the conversation. Read this brief, README, MAC_HANDOFF and WIDGET_SETUP. Inspect the working tree and current GitHub state before editing. This handover puts the implementation and documentation on the default `main` branch; the development history originated in `codex/watch-ready` and PR #3. Do not assume a local preview server, cloud runner, credentials or previous AI agents remain available in a new environment.

The most recently fully verified **application source** (CI, native screenshot review and three Jev PASS) is commit `97d32aa134fb9502c9b8b8948c6389d7db390dcc`, dated 4 October 2026. On 5 October a code review and UI refinement was made on branch `codex/review-and-ui-refinement` (application source `58352ba`, draft PR against `main`). It passed macOS CI, the browser suites and an independent diff review, but its native screenshots have not been visually reviewed and it has no Jev decisions; treat it as unaccepted until Grant merges it. See [the verification record](docs/VERIFICATION.md) for exact scope and immutable retained receipts.

## Purpose and intended outcome

Grant is building a full-drive e-foil/e-flow assist system using a VESC controller. Foil Assist is a standalone **Apple Watch** app for critical information while in the water, without needing a phone during use. Prioritize rapid outdoor readability, dependable freshness, clear controller errors, navigation back to a beach/launch point or toward a downwind finish, and useful persistent ride records.

The desired final outcome is a polished native Watch app that Grant can install, inspect and use on his Watch. His current development laptop is Windows; browser emulation and remote/cloud Mac builds were used to move development forward before he obtains an Apple laptop. No rented interactive Mac account, TestFlight upload, Apple signing team, App Store publication or installed physical Watch acceptance has been completed. The native app and complication have actually built and launched on cloud Mac Watch simulators.

The app is **read-only telemetry**. It sends telemetry requests, never throttle/drive commands. Do not add motor control or BMS configuration writes as part of this brief.

## Accepted visual direction and layout

Grant selected **Sport** from the proposed designs and approved the refined layout. The earlier local design carousel is optional historical material, not a dependency; the native code and tracked preview are the authoritative implementation.

- GPS ground speed and destination compass form two adjacent columns. The arrow belongs beside speed at a comparable visual height, rather than beside tiny text or at the bottom.
- Direction, distance to the selected point, approximate ETA and estimated arrival battery belong with the arrow; they are all destination information.
- Below that are four equally prominent readings: input power `W`, battery `%`, ESC temperature `°C`, pack voltage `V`. Use large inline values/units, not repetitive visible Power/Battery/ESC/Voltage captions. Preserve accessible spoken meanings.
- Voltage and ESC temperature are as critical to read in the water as power and battery. Do not shrink them into secondary footnotes.
- The bottom strip beneath temperature and voltage is permanently visible ESC fault status: fresh no-fault **None**, known/unknown reported error with its code, or **Unavailable** when no valid fresh sample exists. Stale data must never become a live all-clear.
- Use the same refined compass needle for dashboard/navigation rather than a basic inconsistent arrow.
- Motor temperature is neither displayed nor polled: the hardware has ESC temperature only. Legacy archive fields remain readable for backwards compatibility, and VESC fault names may legitimately mention motor-related errors.
- Refinements on 5 October, **approved by Grant on 5 October 2026 from the browser preview renders** (native renders still to be inspected): GPS speed is always drawn larger than the tile values; the dial sits beside three short lines (distance, ETA, flag + arrival battery such as `~64%` / `Empty` / `—`) at 9.5 pt or more; the dial has an explicit "ahead" index, a two-facet needle with a dim tail and a dashed ring with a dash when direction is unavailable. Arrival battery has four levels (above reserve, below reserve, exhausted before arrival, unavailable) carried by text and colour, built by `ArrivalBatterySummary` in `NavigationEstimate.swift`.
- Wrist-down (Always-On, `isLuminanceReduced`): status reads WRIST DOWN, values turn grey and the fault strip reads "ESC faults: raise wrist to check" unless a fault is active, because frames refresh only about once a minute.
- Start ride returns to the dashboard (Water Lock blocks swiping). Home's button reads "Change VESC" when connected, confirms, saves any active ride and forgets the saved controller; "Cancel connection" only stops the attempt.
- Battery BMS has its own connection control and 12S cell page. C1–C12, voltage units, min/max and spread must remain understandable at small Watch sizes; distinguish sample, fresh, stale and unsupported states.

## Implemented behavior

### VESC connection and measurements

`BluetoothManager.swift` owns the VESC BLE session, saved-device discovery/reconnect, notification readiness, bounded request handling and no-response watchdog. The expected adapter uses Nordic UART service `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` and VESC packet framing/CRC. Do not assume every BLE adapter or firmware is compatible without verification.

`Packet.swift`, `VByteArray.swift`, `VescTelemetryDecoder.swift`, `VescRequestQueue.swift` and `VescStats.swift` handle framing, CRC, strict mask/length/value validation, bounded requests and telemetry. Preserve unfamiliar firmware fault codes instead of treating them as no fault. Live primary telemetry expires after six seconds; field availability/fault state must follow the actual sample rather than connection status alone.

GPS speed comes from valid fresh Core Location data, not propeller/motor RPM and not speed through water. GPS/heading losses remove unavailable guidance. Dashboard battery can come from VESC firmware or configured pack-voltage estimation; neither automatically means measured BMS state of charge. New installs default to the confirmed **12S** pack, while existing saved cell-count settings survive. Chemistry, curve and firmware configuration still require hardware confirmation.

### Navigation and battery planning

Grant wants to mark where he enters the water so he can find the starting point/beach again, and optionally enter a separate downwind destination. `DestinationManager.swift` preserves launch/beach and finish separately, allows named decimal latitude/longitude, current-position marking and an Apple Maps center pin that is positioned by panning the map. Do not collapse the two points when switching targets.

`LocationManager.swift` and `NavigationEstimate.swift` supply bearing, straight-line distance, approximate ETA and recent measured battery-depletion forecasts. Default arrival reserve is **20%**; show whether projected arrival is below that reserve or battery exhaustion occurs before arrival. Do not silently clamp exhaustion into a reassuring zero. Details include estimated time to empty/reserve.

The arrival estimator uses a bounded three-minute window: at least 60 continuous seconds, eight samples, a 0.5 percentage-point decline, 50 m of approach and a sufficiently stable trend. BLE/GPS gaps, target/source/pack changes reset it. Unknown, flat, rising, stale or unstable data yields an unavailable forecast. Prediction assumes recent consumption/current GPS speed continue; it is not guaranteed range, navigable routing or a wind/current/wave model. Do not introduce a guessed battery capacity to manufacture an estimate.

### Ride persistence and history

`RideModels.swift`, `RideStore.swift`, `SessionLogger.swift` and `RideHistoryView.swift` implement explicit ride start/save, atomic checkpoints, history, interrupted-ride recovery, storage errors and reconnect gaps. Storage is Watch Application Support `Foiling/Rides`. A Bluetooth disconnect preserves the same active ride. On process restart, the last checkpoint becomes a recovered interrupted ride in history; a new ride can then start.

Keep up to 1,800 recent raw observations per ride while preserving lifetime summaries. Saved rides have no automatic expiry. Energy integrates positive observed electrical draw only across contiguous valid samples; GPS distance can undercount gaps. Never fill disconnected periods with fabricated measurements. Failed writes preserve the last successful checkpoint and surface an error. Deletion requires user confirmation. Synthetic observations must never enter this store.

### Separate 12S battery BMS: partly implemented, not finished

`BMSManager.swift` owns an independent second `CBCentralManager` session. It excludes the current/saved VESC peripheral, including disconnect gaps, so selecting a battery cannot replace the VESC connection. Connection controls are on the initial connection screen, Home menu and Settings. Scans/connect/discovery/serialized reads have bounds and deadlines; disconnect clears readings, and retired-session callbacks are rejected.

Currently supported reads are **only Bluetooth SIG standard values**: Device Information `180A` / manufacturer `2A29` / model `2A24`, and Battery Service `180F` / percentage `2A19`, where readable. Unknown service/characteristic UUIDs can be shown for diagnostics. There are no guessed vendor commands, BMS writes or notification subscriptions. A standard percentage is separate from the VESC dashboard and its arrival forecast.

**Live individual cell decoding is not implemented.** `cellSnapshot` remains nil for live devices until an identified vendor driver is added. A BLE link can succeed without compatible cell data. Never derive twelve cells from pack voltage or percentage. The page correctly shows twelve dashes and unavailable spread when protocol/data is unknown or stale.

`BMSCellSnapshot.swift` validates a complete declared count (12 for this UI), finite values and timestamps; the UI also guards the count before indexing. The generic model allows actual reported critical zero/low cell voltages (`0...6 V`), which must not be silently dropped. The future vendor decoder must reject that vendor's missing/sentinel values before making a snapshot. Do not confuse a missing sensor sentinel with a measured critically low cell. Cell/standard battery freshness is ten seconds, including rejection of future timestamps.

**Missing information already requested from Grant:** battery/BMS brand and model, firmware if available, and/or the phone app currently used to connect. He has confirmed 12S but has not supplied the protocol identity. Ask for this technical information when continuing the driver; this is not a request for permission to keep working. After identifying the protocol, implement and test the real decoder, then compare all twelve cells/min/max/spread against the vendor app and verify simultaneous VESC/BMS hardware connections.

### Complication

`FoilingComplication/FoilingTelemetryWidget.swift` is an embedded WidgetKit extension using App Group `group.com.grantknight.vescfoil` with `TelemetrySnapshot.swift` and matching entitlements. It shows a cached reading/age, does not start Bluetooth or record rides, and supports rectangular/circular/inline/corner slots. Snapshot expiry is 60 seconds, distinct from live telemetry's six seconds. WidgetKit controls refresh timing. Unknown percentage remains a dash. Follow WIDGET_SETUP for signing and all identifier changes.

### Native and browser demos

`ContentView.swift` / `DashboardView.swift` wire live state and labelled radio-free native fixtures. Flags: `--demo`, `--demo-navigation`, `--demo-fault`, `--demo-destination`, `--demo-bms`, `--demo-bms-unavailable`. All demos are visibly synthetic and isolated from live radio, ride data, destination settings and shared snapshots. The BMS fixture is not proof of a live BMS driver.

`preview/watch-preview.html` is a separate browser demonstration with seven screens (dashboard, controller, ride, navigation, history, settings, BMS). Its picker, maps and connection states are simulations. It has its own demo storage; it is not an Apple Watch emulator or SwiftUI runtime. Browser changes do not automatically change native UI: maintain parity in both implementations. Open the file directly, or serve the repo locally; earlier `127.0.0.1:8765` was temporary and may need restarting.

## Verification and continuation workflow

Grant asked for a conductor using councils for aesthetics/functionality/reliability and OpenRouter **Jev** for repeated evidence assessment, with at least **three to five clean passes** before continuing. The last implementation has three actual Jev PASS decisions and three independent scoped source reviews; reviewers excluded their own authored files. All eighteen native screenshots received independent visual review. Keep source, executed test, image-review and model-assessment claims distinct.

Use `swift test --parallel` for the portable Foundation package. Seeds `TEST_SEED=101/202/303` each exercise 3,000 deterministic packet-fragmentation cases. The 4 October application had 77 XCTest cases, including eight BMS outcome tests; the 5 October branch adds `NavigationFormatTests` (7) and `BatteryConfigTests` (1), 85 in total. `node Tests/jev-gate.test.mjs` verifies the gate offline. Browser checks: `node preview/test_preview.cjs` and `node scripts/preview-test.mjs`; the latter needs Playwright and a browser. Set `PLAYWRIGHT_PACKAGE` (path to the playwright module), and optionally `PLAYWRIGHT_CHANNEL` (e.g. `msedge`) or `PLAYWRIGHT_EXECUTABLE`; defaults keep the earlier Windows paths. The results JSON records the browser used.

`.github/workflows/watch-verification.yml` runs three macOS-15 jobs on main/codex pushes. Each records the exact revision, tests core, builds Watch plus complication with signing disabled, then runs `scripts/simulator-smoke.sh`: six scenes on 40/42/46 mm Watch simulators, still-running checks after eight seconds and actual PNGs. Same-repo PR-triggered duplicates are deliberately skipped; successful push jobs are the real verification. Artifacts expire after 14 days, hence selected receipts/screenshots are now retained in Git.

Jev is `scripts/jev-gate.mjs`: OpenRouter Decisions API, model alias `typesafe/jev-1.13`, currently pinned served model `typesafe/jev-1.13-20260917`. It consumes a bounded executed-evidence summary, not source/logs/screenshots. `OPENROUTER_API_KEY` must already be in the environment; never print it or commit it. The gate verifies clean exact HEAD, artifact hashes, actual successful GitHub jobs, browser source hash, independent review and no scoped open defects before three requests; cost cap $0.01, payload cap 20 KB, confidence/probability checks. It cannot override deterministic failure. If service/model changes, verify official service behavior before adapting the contract; do not bypass the checks to obtain PASS.

The user explicitly approved continuing after the specific request to send test summary/filenames/hashes to OpenRouter. No approval remains pending from that session. A new environment may enforce its own permissions; respect those and explain concrete failures. Do not copy credentials, private machine data or unrelated project files as handover material.

For future code changes: reproduce the affected outcome, implement, run appropriate tests, inspect actual native small-screen renders when layout changes, obtain independent reviews where applicable, bind fresh evidence to the new exact source revision, then obtain the requested clean Jev decisions. Fix any genuine failing check before repeating. Historical reports are not fresh evidence and cannot be passed directly to the current exact-HEAD gate. Documentation-only changes do not imply application tests were rerun against that documentation commit.

## Next work, in order

0. For the 5 October branch: inspect its CI simulator screenshots (40/42/46 mm) before the artifacts expire, especially the 40 mm destination caption; run Jev with credentials for three clean decisions; then Grant decides whether to merge. Grant also has an open decision on adding a water-sports `HKWorkoutSession` so telemetry and logging continue with the wrist down (review defect D5; proposed as a separate branch). Further suggestions from the review: a progress-based arrival estimate (battery used per metre of approach), quarantining an unreadable ride archive instead of blocking storage, rejecting poor compass accuracy.
1. Identify Grant's BMS using brand/model/firmware/current phone app. Obtain primary protocol documentation or authorized sample data. Add a bounded read-only vendor decoder and outcome tests for complete/malformed/stale/sentinel/critically low cell data, then connect it to the existing snapshot/UI without disturbing VESC or rides.
2. On a Mac, open `MyWatchOSApp.xcodeproj`, shared **FoilingVESC** scheme, watchOS 10.6+ SDK. For a physical Watch, set signing for all three targets, registered bundle IDs and the common App Group. No Windows tool can complete Apple's device signing/installation on its own.
3. Perform every hardware acceptance check in MAC_HANDOFF: real telemetry/fault agreement, both BLE links, cell comparison, outdoor bearing/ETA, reserve invalidation, ride recovery/write errors, Water Lock/wrist-down/background behavior, complication age, endurance and outdoor/wet-hand readability.
4. Refine any defects based on evidence; do not call this a hardware release before these pass. Publication/TestFlight or motor control are separate scope, not already completed work.

## Gotchas to preserve

- Connection is not freshness; connected stale sensors still show unavailable. Unknown fault is not no fault; unknown battery is not zero.
- Launch and finish are separate persistent targets. Target/source changes invalidate the measured battery trend.
- Critical cell zero can be real; missing vendor data must be rejected in its decoder. Complete twelve-cell count is mandatory before grid indexing.
- BMS standard SOC is neither individual cells nor an automatic replacement for VESC-derived SOC. A second link must never select the VESC peripheral.
- Logging while the Watch app is suspended is **not guaranteed**; no background endurance or on-water BLE claims were established by simulator smoke tests.
- Browser demo, native sample fixture, native simulator execution and physical hardware are distinct evidence levels.
- The synchronized Xcode Watch group includes new Swift files automatically, but portable Foundation files must also be added explicitly to Package.swift when relevant; keep UIKit/CoreBluetooth/SwiftUI out of the portable core target.
- Keep legacy motor-temperature fields readable for archives, but do not reintroduce display/polling.
- Generated ZIPs and working `verification/` are ignored. The tracked dated evidence archive is historical review material, not runtime state; preserve exact provenance.
- Use `codex/` for new development branches by default; do not overwrite unrelated `cursor/*` branches or assume their work belongs in this handover.

## Compact continuation prompt

> Continue Grant Knight's Foil Assist VESC Apple Watch project from this repository. Read AGENTS.md, MASTER_PROMPT.md, README.md, MAC_HANDOFF.md and docs/VERIFICATION.md first. Preserve the approved Sport dashboard, ESC-only temperature and permanent freshness-aware fault strip, adjacent GPS/destination compass with arrival reserve, atomic persistent ride history, complication, and independent 12S BMS connection. The native app is simulator-verified; live vendor cell decoding awaits BMS identity, and physical Watch/on-water acceptance is unfinished. Use actual evidence and independent review, keep demo/live data isolated, and obtain the requested three clean Jev evidence decisions for a changed implementation without inventing results. Update this handover when state changes.
