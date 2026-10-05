import SwiftUI

func rideDuration(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return "—" }
    let total = Int(seconds)
    if total >= 3600 { return "\(total / 3600):" + String(format: "%02d:%02d", total % 3600 / 60, total % 60) }
    return String(format: "%02d:%02d", total / 60, total % 60)
}

struct RideHistoryView: View {
    @ObservedObject var logger: SessionLogger
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if let error = logger.storageError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                    Button("Retry storage") { logger.retryLoad() }
                }
                if logger.rides.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath").foregroundStyle(.cyan)
                        Text("No saved rides yet").font(.headline)
                        Text("Start a ride from the ride page, then save it here.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(logger.rides) { ride in
                    NavigationLink {
                        RideDetailView(ride: ride, logger: logger)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ride.startedAt, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.caption)
                            Text("\(rideDuration(ride.duration)) · \(String(format: "%.2f km", ride.distanceMeters / 1000))")
                                .font(.caption2).foregroundStyle(.cyan)
                            if ride.interrupted { Text("Recovered after interruption").font(.caption2).foregroundStyle(.orange) }
                        }
                    }
                }
                Button("Done") { dismiss() }
            }.navigationTitle("Ride history")
        }
    }
}

private struct RideDetailView: View {
    let ride: RideSession
    @ObservedObject var logger: SessionLogger
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @AppStorage("GPS_SPEEDUNIT") private var speedUnitRaw = GPSSpeedUnit.kph.rawValue
    private var speedUnit: GPSSpeedUnit { GPSSpeedUnit(rawValue: speedUnitRaw) ?? .kph }
    var body: some View {
        List {
            Text(ride.startedAt, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.caption)
            if ride.interrupted { Text("Recording recovered after app interruption.").font(.caption2).foregroundStyle(.orange) }
            row("Duration", rideDuration(ride.duration))
            row("GPS distance", String(format: "%.2f km", ride.distanceMeters / 1000))
            row("Energy used", String(format: "%.1f Wh", ride.energyWh))
            row("Peak GPS speed", String(format: "%.1f ", formatVescSpeed(ride.maxSpeedMs, unit: speedUnit)) + speedUnit.displayLabel)
            row("Peak power", String(format: "%.0f W", ride.maxWatts))
            row("Average power", String(format: "%.0f W", ride.averageWatts))
            row("Peak controller", String(format: "%.0f °C", ride.maxControllerTemperatureC))
            row("Connection gaps", "\(ride.disconnectionCount)")
            row("Samples", "\(ride.totalSampleCount)")
            Text("Distance uses valid GPS samples. Gaps are not extrapolated.").font(.caption2).foregroundStyle(.secondary)
            Button("Delete ride", role: .destructive) { confirmDelete = true }
        }.navigationTitle("Ride details")
            .alert("Delete this ride?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) {
                    logger.deleteRide(id: ride.id)
                    if logger.storageError == nil { dismiss() }
                }
                Button("Keep ride", role: .cancel) {}
            } message: { Text("This removes the saved ride from this Watch.") }
    }
    private func row(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption).monospacedDigit()
        }
    }
}
