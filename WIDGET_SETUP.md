# Watch-face complication

The project includes a built FoilingComplication WidgetKit extension and shared App Group `group.com.grantknight.vescfoil`. Both targets have matching entitlements, and the Watch app embeds the extension.

On a Mac, open MyWatchOSApp.xcodeproj, choose the FoilingVESC scheme, and select your signing team for the container, Watch app and complication targets. Provision the supplied App Group, or register a unique one for your team and replace its name in both entitlement files and TelemetrySnapshot.swift. Keep the identifier identical in all three places.

After installation, edit a compatible watch face and select VESC Foil Assist in a supported complication slot (rectangular, circular, inline or corner). Tap it to open the app.

The complication shows the last cached reading and its age. It never starts Bluetooth or records rides. Its 60-second cache expiry is separate from the app's 6-second live-telemetry freshness check. WidgetKit controls refresh scheduling and may update later than requested; open the app for current readings. Unknown battery percentage displays a dash rather than zero.
