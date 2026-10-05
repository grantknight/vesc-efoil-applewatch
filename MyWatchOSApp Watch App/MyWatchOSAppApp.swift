//
//  MyWatchOSAppApp.swift
//  MyWatchOSApp Watch App
//
//  Created by Gregory Dymarek on 09/07/2025.
//

import SwiftUI

@main
struct MyWatchOSApp_Watch_AppApp: App {
    init() {
        // Background running follows real ride recording only; demo data never records.
        RideWorkoutSession.shared.follow(SessionLogger.shared)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
