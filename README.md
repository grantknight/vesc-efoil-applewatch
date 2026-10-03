# Foil Assist for Apple Watch

A standalone SwiftUI watchOS app for read-only VESC telemetry over Bluetooth LE. No phone is needed during use. The project includes the Watch app, a WidgetKit complication extension, a persistent ride store, portable Swift core tests and a clearly labelled demo.

## Features

- Readable dashboard: fresh GPS ground speed, input power, battery percentage/source, voltage and controller/motor temperatures.
- Protocol validation: framed CRC-checked packets, strict response masks/lengths and invalid-value rejection. Stale telemetry is hidden instead of shown as current.
- Connection recovery: saved device discovery, notification readiness, bounded retry delays and no-response watchdog.
- Ride recording: explicit start/save, atomic checkpoints, interrupted-ride recovery, reconnect gaps, observed energy/GPS-distance summaries and confirmed history deletion.
- Navigation: pinned destination, bearing, straight-line distance and approximate ETA. This is not routed marine navigation.
- Complication: shared App Group snapshot with cached-reading expiry; WidgetKit controls update timing.
- Native demo: launch with `--demo` or use Preview app. Synthetic values never become real ride observations.

## Preview

Open `preview/watch-preview.html` in a browser. Explore the screens, connection states, GPS units, sample recording and history. This browser demonstration is independent of the native app and stores only demo data.

## Build and install

Open `MyWatchOSApp.xcodeproj` in Xcode on a Mac, choose the shared **FoilingVESC** scheme and a Watch simulator. For device installation choose your signing team and provision the shared App Group. Complete instructions and the required hardware acceptance checklist are in [MAC_HANDOFF.md](MAC_HANDOFF.md). Complication details are in [WIDGET_SETUP.md](WIDGET_SETUP.md).

Default battery cell count is 14S; that is not a verified description of your pack. Configure it before using voltage-based percentage. VESC-reported battery level also depends on its firmware and configured battery model; it is not necessarily a BMS measurement.

## Verification

`swift test` runs the Foundation-only protocol and persistence suite, including 3,000 seeded packet-fragmentation cases. `TEST_SEED=101`, `202` and `303` exercise different reproducible inputs. GitHub Actions performs three independent clean core-test, Watch/complication simulator-build and simulator-launch runs on the same commit. `node Tests/jev-gate.test.mjs` tests the evidence gate without a network request. Browser behavior checks are in `scripts/preview-test.mjs` and `preview/test_preview.cjs`.

Jev assessments use OpenRouter's Decisions API and an existing `OPENROUTER_API_KEY` environment variable. Jev classifies recorded executed evidence; it does not execute tests, inspect screenshots or replace hardware validation. `scripts/jev-gate.mjs` requires named category results at one revision and never allows a model decision to override a failed local gate. Results are saved under ignored `verification/`; no API credential is stored in the repository.

A simulator build or preview does not establish uninterrupted background operation, on-water BLE range, outdoor GPS accuracy, signing or installed Watch acceptance. Those remain explicit checks in the Mac handoff checklist.

## Ride data

Checkpoints live in Application Support/Foiling/Rides on the Watch. Each ride retains up to 1,800 recent raw observations plus full lifetime summaries; rides have no automatic expiration. Consumption integrates positive electrical draw only across observed contiguous samples. GPS distance can undercount missing data. The app never fills disconnected periods with fabricated measurements.

This project builds on [gregd72002/vesc-efoil-applewatch](https://github.com/gregd72002/vesc-efoil-applewatch). Protocol behavior is checked against the primary VESC firmware implementation in [commands.c](https://github.com/vedderb/bldc/blob/master/comm/commands.c) and [buffer.c](https://github.com/vedderb/bldc/blob/master/util/buffer.c). See LICENSE for the repository's license.
