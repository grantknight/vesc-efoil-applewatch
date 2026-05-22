//
//  DashboardView.swift
//  MyWatchOSApp Watch App
//
//  Large-type glance screen: speed, watts, battery, VESC + motor temps.
//

import SwiftUI

struct DashboardView: View {
    @ObservedObject var rtStats: VESCRtStats
    let displaySpeed: Double
    let speedUnit: GPSSpeedUnit
    let connectionMessage: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 2) {
                if !connectionMessage.isEmpty {
                    Text(connectionMessage)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.orange)
                        .lineLimit(1)
                }

                Text(String(format: "%.1f", displaySpeed))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Text(speedUnit.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.gray)

                HStack(spacing: 10) {
                    metricColumn(title: "W", value: String(format: "%.0f", rtStats.instantWatts))
                    metricColumn(
                        title: "V",
                        value: String(format: "%.0f%%", rtStats.batteryPercent)
                    )
                }
                .padding(.top, 4)

                HStack(spacing: 10) {
                    metricColumn(
                        title: "MOS",
                        value: String(format: "%.0f°", rtStats.mosTemperature)
                    )
                    metricColumn(
                        title: "MTR",
                        value: String(format: "%.0f°", rtStats.motorTemperature)
                    )
                }

                Text(String(format: "%.1f V", rtStats.batteryVoltage))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)
        }
    }

    private func metricColumn(title: String, value: String) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}
