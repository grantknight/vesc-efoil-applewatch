//
//  FoilingTelemetryWidget.swift
//  FoilingComplication (Widget Extension — add target in Xcode, see WIDGET_SETUP.md)
//

import WidgetKit
import SwiftUI

struct FoilingTelemetryEntry: TimelineEntry {
    let date: Date
    let snapshot: TelemetrySnapshot
}

struct FoilingTelemetryProvider: TimelineProvider {
    func placeholder(in context: Context) -> FoilingTelemetryEntry {
        FoilingTelemetryEntry(date: .now, snapshot: TelemetrySnapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (FoilingTelemetryEntry) -> Void) {
        completion(FoilingTelemetryEntry(date: .now, snapshot: TelemetrySnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FoilingTelemetryEntry>) -> Void) {
        let entry = FoilingTelemetryEntry(date: .now, snapshot: TelemetrySnapshot.load())
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30)))
        completion(timeline)
    }
}

struct FoilingTelemetryWidgetView: View {
    var entry: FoilingTelemetryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "%.1f %@", entry.snapshot.speed, entry.snapshot.speedUnit))
                .font(.headline)
            Text(String(format: "%.0f W", entry.snapshot.watts))
            Text(String(format: "%.0f%%", entry.snapshot.batteryPercent))
            Text(String(format: "MOS %.0f° MTR %.0f°", entry.snapshot.mosTempC, entry.snapshot.motorTempC))
                .font(.caption2)
        }
    }
}

@main
struct FoilingTelemetryWidget: Widget {
    let kind = "FoilingTelemetryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FoilingTelemetryProvider()) { entry in
            FoilingTelemetryWidgetView(entry: entry)
        }
        .configurationDisplayName("Foiling VESC")
        .description("Speed, power, battery, and temperatures.")
        .supportedFamilies([
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner
        ])
    }
}
