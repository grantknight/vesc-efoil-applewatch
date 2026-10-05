# Build and install on your Mac

## Open and preview

1. Clone or download the repository's current `main` branch. Read `MASTER_PROMPT.md` for intent and unfinished work; `codex/watch-ready` contains the development history from PR #3.
2. Install Xcode with a watchOS SDK supporting watchOS 10.6 or newer. Open `MyWatchOSApp.xcodeproj`.
3. Choose scheme **FoilingVESC** and a Watch simulator. Build and run. The app's **Preview** button opens clearly labelled synthetic screens without a VESC connection. Preview never records synthetic values in your ride history.
4. The browser preview is `preview/watch-preview.html`. It demonstrates the layout and controls with simulated values; it is separate from the native SwiftUI app.

## Install on a real Watch

1. Add your Apple account in Xcode Settings and enable Developer Mode on your paired devices as required by Xcode.
2. Under Signing & Capabilities select your development team on **all three targets**. Replace default bundle identifiers if your team needs unique registered identifiers. The supplied identifiers share `com.grantknight.vescfoil`.
3. Provision the same App Group for the watch app and complication. See `WIDGET_SETUP.md` for all places to change a group identifier.
4. Select your paired Watch as the run destination, build, and run. Allow Bluetooth and location access on the Watch.
5. Select the VESC BLE UART device from the scan list. The app expects Nordic UART service UUID `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` and the standard VESC packet protocol. Verify your BLE adapter advertises that service. The app only polls telemetry; it sends no throttle or drive commands.
6. In Settings set the battery series cell count and decide whether to use VESC's reported battery level or the voltage estimate. New installations default to the confirmed 12S pack; existing saved settings are retained. Confirm the voltage curve against your pack chemistry and controller configuration.
7. Use **Connect battery BMS** for the separate battery BLE device. Choosing it preserves the VESC connection. The client can read standard device identity and Battery Service percentage when exposed; cell readings need the BMS brand/model and a supported vendor decoder. A successful BLE link alone is not cell-data compatibility. The 12-cell page stays unavailable until complete, fresh measurements exist.

## Ride logging

Start a ride explicitly, then save it at the end. Valid live observations are checkpointed atomically in Application Support. A Bluetooth disconnect keeps the same active ride; energy and GPS distance exclude disconnected/stale gaps. On app process restart, the last checkpoint becomes a recovered interrupted ride in history. Start a new ride when ready.

Each ride retains the most recent 1,800 observations and full lifetime summary totals. Older individual observations roll off that ride; saved rides are never automatically deleted. Energy is observed positive electrical consumption integrated from voltage/current, not a prediction of remaining range. Distance is observed GPS distance and can undercount missing GPS or Bluetooth periods. History deletion requires confirmation.

If storage fails, the UI displays the error. The previous successful checkpoint is preserved. Do not interpret the recording indicator as a guarantee that the latest sample reached disk while an error is shown.

## Required hardware acceptance

Before relying on the readings, verify:

- Voltage, current and ESC temperature agree with VESC Tool for your firmware and sensor; battery percent agrees with your known pack state. Motor temperature is not polled or displayed.
- Compare VESC fault status with VESC Tool: no fault, a known reported error and an unfamiliar code must remain distinct. Disconnect or stop packets and confirm fault status becomes unavailable rather than a live all-clear.
- Select the battery/BMS while the VESC is connected and confirm both links independently. Verify detected maker/model against your battery. Until the correct cell protocol is implemented, C1–C12 and spread must stay unavailable; a standard battery percentage must not populate cell voltages. After adding that driver, compare all 12 cells/min/max/spread with the BMS phone app, then disconnect/reconnect and verify freshness. Actual BMS compatibility and dual-link behavior remain hardware checks.
- Mark a launch/beach point, save a separate finish using decimal coordinates and the map center pin, restart the app and switch between both saved targets. Verify arrow direction against a known bearing outdoors, and confirm GPS or heading loss removes unavailable guidance.
- Check distance and straight-line ETA against a known course. Choose a 20% arrival reserve, observe a stable battery decline for at least a minute, and check estimated arrival, reserve shortfall and exhaustion warnings. Confirm source/pack changes, target changes, GPS/BLE gaps and unstable/flat readings invalidate the estimate.
- GPS speed is displayed only with fresh valid location data; propeller RPM is never treated as speed over water.
- Start, ride, save, quit and reopen preserves history. Confirm the recovered label after terminating during recording.
- Turn off or move out of range of the BLE adapter, reconnect and confirm the same ride continues with a gap rather than fabricated data.
- Let the Watch screen sleep, lower your wrist, use Water Lock, and reopen. Background runtime and reconnect timing must be measured on your Watch. Continuous logging while suspended is not promised.
- Add the complication, inspect its timestamp/freshness, and tap to reopen the app. Compare displayed cached values to the live screen.
- Check readability outdoors, wet-hand/crown navigation, GPS battery use, and endurance on an actual ride.

Code tests, simulator builds and Jev evidence decisions do not replace those measurements or Apple signing. No app-store publication or installed-device acceptance is implied by this handoff.
