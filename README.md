# Foil Assist for Apple Watch

A standalone SwiftUI watchOS app for read-only VESC telemetry over Bluetooth LE. No phone is needed during use. The project includes the Watch app, a WidgetKit complication extension, a persistent ride store, portable Swift core tests and a clearly labelled demo.

## Project handover and current status

**AI/developer entry point:** read [MASTER_PROMPT.md](MASTER_PROMPT.md) for the complete product brief, accepted Sport design, architecture, gotchas and remaining work. [AGENTS.md](AGENTS.md) directs coding agents there. The [verification record](docs/VERIFICATION.md) retains dated test/review receipts and all 18 native screenshots.

The application at `97d32aa` passed three clean Mac builds/test/launch runs, 300 browser assertions, independent review and three Jev evidence assessments. Live vendor-specific BMS cell decoding still needs the battery/BMS identity; physical Watch installation and on-water hardware acceptance remain unfinished. The handover documentation was updated on 5 October 2026 without changing application behavior. Later on 5 October, branch `claude/nifty-bohr-hou2sb` (application commit `c75abfc`) added reviewed fixes and Sport-layout refinements that passed three-seed Mac CI and the browser suite but have no Jev decisions and no visually reviewed native screenshots yet; see the [verification record](docs/VERIFICATION.md).

## Features

- Sport dashboard: fresh GPS ground speed, input power, battery percentage/source, voltage and ESC temperature. A tappable direction arrow sits beside the GPS speed unit.
- VESC faults: poll the controller's reported fault code, show a fresh error label and numeric code, and retain unknown firmware codes. A stale link never reports a live all-clear.
- Protocol validation: framed CRC-checked packets, strict response masks/lengths and invalid-value rejection. Stale telemetry is hidden instead of shown as current.
- Connection recovery: saved device discovery, notification readiness, bounded retry delays and no-response watchdog.
- Ride recording: explicit start/save, atomic checkpoints, interrupted-ride recovery, reconnect gaps, observed energy/GPS-distance summaries and confirmed history deletion.
- Navigation: independently saved launch/beach and downwind finish, manual decimal coordinates or pan-to-pin Apple Maps, direction, straight-line distance and approximate ETA.
- Arrival battery: recent observed percentage decline predicts remaining battery at the destination; configurable reserve defaults to 20%. Insufficient, stale or unstable measurements show an unavailable estimate.
- Complication: shared App Group snapshot with cached-reading expiry; WidgetKit controls update timing.
- Separate battery BMS connection: independent read-only BLE discovery/link, standard device identity and Battery Service percentage when available. A 12S page shows C1–C12, min/max and cell spread; live cell measurements require an identified, supported BMS protocol and otherwise remain unavailable.
- Native demo: launch with `--demo` or use Preview app. `--demo-navigation`, `--demo-fault` and `--demo-destination` expose additional simulator fixtures. Synthetic values never become real ride observations or saved destination settings.

## Preview

Open `preview/watch-preview.html` in a browser. Explore the screens, connection states, GPS units, sample recording and history. This browser demonstration is independent of the native app and stores only demo data.

## Build and install

Open `MyWatchOSApp.xcodeproj` in Xcode on a Mac, choose the shared **FoilingVESC** scheme and a Watch simulator. For device installation choose your signing team and provision the shared App Group. Complete instructions and the required hardware acceptance checklist are in [MAC_HANDOFF.md](MAC_HANDOFF.md). Complication details are in [WIDGET_SETUP.md](WIDGET_SETUP.md).

New installations default to the user's confirmed 12S pack; existing saved cell-count settings are preserved. Confirm the cell count, chemistry and voltage curve before using voltage-based percentage. VESC-reported battery level also depends on its firmware and configured battery model; it is not necessarily a BMS measurement.

## Separate battery BMS

Use **Connect battery BMS** from the initial connection screen, Home menu or Settings. This creates a second BLE session without replacing the VESC. The current/saved VESC device is excluded from the BMS picker. Discovery, connection and read operations have deadlines, and disconnect clears readings. The client performs only standard Bluetooth device-information and battery-percentage reads; it sends no vendor commands or configuration writes.

The **12 cell voltages** page always shows C1–C12. Without a compatible cell decoder, readings and imbalance remain unavailable even when the BLE link succeeds. Battery brand/BMS model, firmware and the current phone-app name are needed to implement that decoder. Pack percentage or pack voltage is never used to invent individual cells. Standard Battery Service percentage is shown separately and does not replace the VESC dashboard/arrival estimate.

`--demo-bms` and `--demo-bms-unavailable` provide clearly labelled, radio-free populated and unknown 12-cell fixtures. No sample readings or device selections enter real ride storage, destination settings or shared snapshots. The browser BMS device picker is a simulation and cannot connect to hardware.

## Destination and arrival reserve

Tap the arrow beside GPS to mark your current launch point, choose the saved beach, enter named decimal latitude/longitude, or pan the map and place its center pin. Launch and finish remain separate when switching targets. Navigation uses straight-line distance and current GPS ground speed; it does not route around land or account for waves, wind or currents.

The native arrival estimate uses a bounded three-minute window of fresh battery observations. It requires at least 60 continuous seconds, eight samples, a 0.5 percentage-point decline, 50 metres of approach and a sufficiently stable trend. Link/GPS gaps, target or battery-source changes discard that trend. Flat, rising, unknown or stale battery percentages produce no prediction. Estimated arrival below the selected reserve is highlighted; projected exhaustion is stated explicitly rather than hidden by clamping to zero. Navigation details also show estimated battery time to empty and to the selected reserve. It estimates recent consumption continuing at current ground speed, not a guaranteed remaining range.

Motor temperature is no longer polled or displayed. Legacy ride and snapshot fields remain readable for archive compatibility. Controller fault names can still include motor-related errors reported by VESC firmware.

## Verification

`swift test` runs the Foundation-only protocol and persistence suite, including 3,000 seeded packet-fragmentation cases. `TEST_SEED=101`, `202` and `303` exercise different reproducible inputs. GitHub Actions performs three independent clean core-test, Watch/complication simulator-build and simulator-launch runs on the same commit. `node Tests/jev-gate.test.mjs` tests the evidence gate without a network request. Browser behavior checks are in `scripts/preview-test.mjs` and `preview/test_preview.cjs`.

Jev assessments use OpenRouter's Decisions API and an existing `OPENROUTER_API_KEY` environment variable. Jev classifies recorded executed evidence; it does not execute tests, inspect screenshots or replace hardware validation. `scripts/jev-gate.mjs` requires named category results at one revision and never allows a model decision to override a failed local gate. Results are saved under ignored `verification/`; no API credential is stored in the repository.

A simulator build or preview does not establish uninterrupted background operation, on-water BLE range, outdoor GPS accuracy, signing or installed Watch acceptance. Those remain explicit checks in the Mac handoff checklist.

## Ride data

Checkpoints live in Application Support/Foiling/Rides on the Watch. Each ride retains up to 1,800 recent raw observations plus full lifetime summaries; rides have no automatic expiration. Consumption integrates positive electrical draw only across observed contiguous samples. GPS distance can undercount missing data. The app never fills disconnected periods with fabricated measurements.

This project builds on [gregd72002/vesc-efoil-applewatch](https://github.com/gregd72002/vesc-efoil-applewatch). Protocol behavior is checked against the primary VESC firmware implementation in [commands.c](https://github.com/vedderb/bldc/blob/master/comm/commands.c) and [buffer.c](https://github.com/vedderb/bldc/blob/master/util/buffer.c). See LICENSE for the repository's license.
