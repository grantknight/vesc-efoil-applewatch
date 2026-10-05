import SwiftUI
import Foundation

/// This independent link never sends controller commands or invents per-cell data.
struct BMSConnectionView: View {
    @ObservedObject var manager: BMSManager
    let excludedVESC: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Battery BMS · 12S").font(.headline).foregroundStyle(.mint)
                    Text(manager.statusMessage).font(.caption2).foregroundStyle(.secondary)
                    NavigationLink("12 cell voltages") {
                        BMSLiveCellsView(manager: manager)
                    }.tint(.mint)
                    if let name = manager.linkedDeviceName { Text(name).font(.caption.bold()) }
                    if let manufacturer = manager.manufacturer { Text("Maker: " + manufacturer).font(.caption2) }
                    if let model = manager.model { Text("Model: " + model).font(.caption2) }
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        if let percent = manager.standardBatteryPercent,
                           manager.hasFreshStandardBatteryPercent(at: Date()) {
                            Text("Standard battery service: \(percent)%").font(.caption)
                        } else {
                            Text("Standard battery service: unavailable").font(.caption2)
                        }
                    }
                    Text("This percentage is separate from the 12 cell voltages.").font(.caption2).foregroundStyle(.secondary)
                    Button(manager.state == .scanning ? "Scan again" : "Connect battery BMS") {
                        manager.excludePeripheral(excludedVESC)
                        manager.scan()
                    }.tint(.mint)
                    ForEach(manager.devices) { device in
                        Button(device.name) {
                            manager.excludePeripheral(excludedVESC)
                            manager.connect(to: device.id)
                        }
                    }
                    if manager.state == .connecting { ProgressView() }
                    if manager.state == .linked || manager.state == .connecting {
                        Button("Disconnect BMS") { manager.disconnect() }
                    }
                    Text("Read-only. Cell voltages require an identified, compatible BMS protocol. Supply the BMS model to enable its driver.")
                        .font(.caption2).foregroundStyle(.secondary)
                    if !manager.discoveredServiceUUIDs.isEmpty {
                        Text("Detected services").font(.caption2.bold())
                        Text(manager.discoveredServiceUUIDs.joined(separator: "\n")).font(.system(size: 8)).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 6)
            }
        }.onAppear { manager.excludePeripheral(excludedVESC) }
    }
}

private struct BMSLiveCellsView: View {
    @ObservedObject var manager: BMSManager

    var body: some View { BMSCellsView(snapshot: manager.cellSnapshot) }
}

struct BMSCellsView: View {
    let snapshot: BMSCellSnapshot?
    var usesSampleData = false
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            GeometryReader { geometry in
                let currentSnapshot = snapshot.flatMap { value in
                    value.cellCount == 12 && (usesSampleData || value.isFresh(at: Date())) ? value : nil
                }
                let rowHeight = max(21, min(30, (geometry.size.height - 18) / 4 - 2))
                ScrollView {
                    VStack(spacing: 3) {
                        Text("12S · cell voltages").font(.system(size: 10, weight: .bold)).foregroundStyle(.mint)
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(0..<12) { index in
                                let voltage = currentSnapshot?.cellVoltages[index]
                                // The lowest cell limits the pack, so it is outlined (matching the preview).
                                let isLowest = voltage != nil && voltage == currentSnapshot?.minVoltage
                                VStack(spacing: 0) {
                                    Text("C\(index + 1)").font(.system(size: 8, weight: .bold)).foregroundStyle(Color(white: 0.72))
                                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                                        Text(voltage.map { String(format: "%.3f", $0) } ?? "—")
                                            .font(.system(size: min(14, max(10, rowHeight * 0.44)), weight: .bold, design: .rounded)).monospacedDigit()
                                        Text("V").font(.system(size: 8, weight: .semibold))
                                    }.lineLimit(1).minimumScaleFactor(0.8)
                                }.frame(maxWidth: .infinity).frame(height: rowHeight)
                                    .background(Color.mint.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
                                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(isLowest ? SportPalette.caution : .clear, lineWidth: 1))
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel("Cell \(index + 1), \(voltage.map { String(format: "%.3f volts", $0) } ?? "unavailable")\(isLowest ? ", lowest" : "")")
                            }
                        }
                        if let currentSnapshot {
                            Text(String(format: "Min %.3f · max %.3f V", currentSnapshot.minVoltage, currentSnapshot.maxVoltage))
                                .font(.system(size: 9)).monospacedDigit()
                            Text(String(format: "Cell spread %.0f mV", currentSnapshot.deltaMillivolts))
                                .font(.system(size: 9, weight: .semibold)).monospacedDigit()
                        } else {
                            Text(snapshot == nil ? "Cell protocol not identified" : (snapshot?.cellCount != 12 ? "Expected 12 cells · readings unavailable" : "Cell data stale · readings unavailable"))
                                .font(.system(size: 9)).foregroundStyle(.orange)
                        }
                        Text(usesSampleData ? "Synthetic cells. No BMS is connected." : "Read-only cells from the separate battery BMS. Standard battery percentage is not cell data.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }.padding(.horizontal, 4)
                }
            }
        }.accessibilityIdentifier("bms-cells")
    }
}

/// Fixture data has no manager, Bluetooth connection or persistence path.
struct BMSDemoView: View {
    var unavailable = false
    private let sample = BMSCellSnapshot(deviceID: UUID(), cellVoltages: [3.817, 3.821, 3.814, 3.820, 3.818, 3.816, 3.822, 3.819, 3.815, 3.820, 3.817, 3.818], measuredAt: Date())

    var body: some View {
        BMSCellsView(snapshot: unavailable ? nil : sample, usesSampleData: true)
    }
}
