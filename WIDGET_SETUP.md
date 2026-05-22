# Watch complication setup (optional)

The main app already includes a **large-type dashboard** as the first in-app tab. To add a **watch face complication**, create a Widget Extension in Xcode:

1. Open `MyWatchOSApp.xcodeproj` on a Mac.
2. **File → New → Target → Widget Extension** (watchOS).
3. Name it `FoilingComplication`.
4. Add `FoilingComplication/FoilingTelemetryWidget.swift` to the extension target.
5. Add `MyWatchOSApp Watch App/TelemetrySnapshot.swift` and `BatteryConfig.swift` to **both** targets (or duplicate the snapshot types in the extension).
6. Enable an **App Group** on the watch app and widget extension, then change `TelemetrySnapshot` to use `UserDefaults(suiteName: "group.YOUR_BUNDLE")` so the widget reads live data.

Until the extension target exists, complications are not built; the in-app dashboard is the supported glance UI.
