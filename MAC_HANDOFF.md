# Build and install on your Mac

## Open and preview

1. Download this branch or clone the repository and check out `codex/watch-ready`.
2. Install Xcode with a watchOS SDK supporting watchOS 10.6 or newer. Open `MyWatchOSApp.xcodeproj`.
3. Choose scheme **FoilingVESC** and a Watch simulator. Build and run. The app's **Preview** button opens clearly labelled synthetic screens without a VESC connection. Preview never records synthetic values in your ride history.
4. The browser preview is `preview/watch-preview.html`. It demonstrates the layout and controls with simulated values; it is separate from the native SwiftUI app.

## Install on a real Watch

1. Add your Apple account in Xcode Settings and enable Developer Mode on your paired devices as required by Xcode.
2. Under Signing & Capabilities select your development team on **all three targets**. Replace default bundle identifiers if your team needs unique registered identifiers. The supplied identifiers share `com.grantknight.vescfoil`.
3. Provision the same App Group for the watch app and complication. See `WIDGET_SETUP.md` for all places to change a group identifier.
4. Select your paired Watch as the run destination, build, and run. Allow Bluetooth and location access on the Watch.
5. Select the VESC BLE UART device from the scan list. The app expects Nordic UART service UUID `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` and the standard VESC packet protocol. Verify your BLE adapter advertises that service. The app only polls telemetry; it sends no throttle or drive commands.
6. In Settings set the battery series cell count and decide whether to use VESC's reported battery level or the voltage estimate. Confirm against your actual pack and controller configuration; the default 14S is an app setting, not a statement about your hardware.

## Ride logging

Start a ride explicitly, then save it at the end. Valid live observations are checkpointed atomically in Application Support. A Bluetooth disconnect keeps the same active ride; energy and GPS distance exclude disconnected/stale gaps. On app process restart, the last checkpoint becomes a recovered interrupted ride in history. Start a new ride when ready.

Each ride retains the most recent 1,800 observations and full lifetime summary totals. Older individual observations roll off that ride; saved rides are never automatically deleted. Energy is observed positive electrical consumption integrated from voltage/current, not a prediction of remaining range. Distance is observed GPS distance and can undercount missing GPS or Bluetooth periods. History deletion requires confirmation.

If storage fails, the UI displays the error. The previous successful checkpoint is preserved. Do not interpret the recording indicator as a guarantee that the latest sample reached disk while an error is shown.

## Required hardware acceptance

Before relying on the readings, verify:

- Voltage, current, controller and motor temperatures agree with VESC Tool for your firmware and sensors; battery percent agrees with your known pack state.
- GPS speed is displayed only with fresh valid location data; propeller RPM is never treated as speed over water.
- Start, ride, save, quit and reopen preserves history. Confirm the recovered label after terminating during recording.
- Turn off or move out of range of the BLE adapter, reconnect and confirm the same ride continues with a gap rather than fabricated data.
- Let the Watch screen sleep, lower your wrist, use Water Lock, and reopen. Background runtime and reconnect timing must be measured on your Watch. Continuous logging while suspended is not promised.
- Add the complication, inspect its timestamp/freshness, and tap to reopen the app. Compare displayed cached values to the live screen.
- Check readability outdoors, wet-hand/crown navigation, GPS battery use, and endurance on an actual ride.

Code tests, simulator builds and Jev evidence decisions do not replace those measurements or Apple signing. No app-store publication or installed-device acceptance is implied by this handoff.
