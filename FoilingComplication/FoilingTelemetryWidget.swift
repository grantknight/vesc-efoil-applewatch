import WidgetKit
import SwiftUI

struct FoilingTelemetryEntry: TimelineEntry {
    let date: Date
    let snapshot: TelemetrySnapshot
    var isFresh: Bool { snapshot.isFresh(at: date) }
}
struct FoilingTelemetryProvider: TimelineProvider {
    func placeholder(in context: Context) -> FoilingTelemetryEntry {
        FoilingTelemetryEntry(date: .now, snapshot: TelemetrySnapshot())
    }
    func getSnapshot(in context: Context, completion: @escaping (FoilingTelemetryEntry) -> Void) {
        completion(FoilingTelemetryEntry(date: .now, snapshot: TelemetrySnapshot.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<FoilingTelemetryEntry>) -> Void) {
        let now = Date()
        let snapshot = TelemetrySnapshot.load()
        var entries = [FoilingTelemetryEntry(date: now, snapshot: snapshot)]
        // Explicit expiry hides cached readings even without a background app callback.
        let expires = snapshot.updatedAt.addingTimeInterval(TelemetrySnapshot.staleInterval)
        if expires > now { entries.append(FoilingTelemetryEntry(date: expires, snapshot: snapshot)) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(60))))
    }
}
struct FoilingTelemetryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FoilingTelemetryEntry
    private var battery: String { entry.snapshot.batteryPercent.map { String(format: "%.0f%%", $0) } ?? "�" }
    var body: some View {
        Group {
            if !entry.isFresh {
                Label("Open VESC · data stale", systemImage: "antenna.radiowaves.left.and.right.slash")
                    .font(.caption2)
            } else {
                switch family {
                case .accessoryInline:
                    Text("Last VESC \(battery) · \(Int(entry.snapshot.watts.rounded())) W")
                case .accessoryCircular:
                    Group {
                        if let percent = entry.snapshot.batteryPercent {
                            Gauge(value: min(100, max(0, percent)), in: 0...100) {
                                Image(systemName: "battery.100percent")
                            } currentValueLabel: { Text(battery).font(.caption2) }
                            .gaugeStyle(.accessoryCircular)
                        } else {
                            Text("Battery % unavailable").font(.system(size: 9)).multilineTextAlignment(.center)
                        }
                    }
                    .widgetLabel { Text("Last VESC reading") }
                case .accessoryCorner:
                    Text(battery).font(.headline)
                        .widgetLabel { Text("\(Int(entry.snapshot.watts.rounded())) W · VESC") }
                default:
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LAST  \(battery)").font(.headline)
                        Text("\(Int(entry.snapshot.watts.rounded())) W · \(entry.snapshot.batteryVoltage, specifier: "%.1f") V")
                            .font(.caption)
                        Text("ESC \(Int(entry.snapshot.mosTempC.rounded()))° · MOTOR \(Int(entry.snapshot.motorTempC.rounded()))°")
                            .font(.caption2)
                        Text(entry.snapshot.updatedAt, style: .relative)
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .containerBackground(.clear, for: .widget)
        .widgetURL(URL(string: "vescfoil://dashboard"))
    }
}
@main
struct FoilingTelemetryWidget: Widget {
    let kind = TelemetrySnapshot.widgetKind
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FoilingTelemetryProvider()) { entry in
            FoilingTelemetryWidgetView(entry: entry)
        }
        .configurationDisplayName("VESC Foil Assist")
        .description("Battery, power and temperatures from the latest telemetry. Open the app for live readings.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular, .accessoryCorner])
    }
}
