//
//  SessionLogger.swift
//  MyWatchOSApp Watch App
//

import Foundation

struct LogEntry: Codable {
    let timestamp: Date
    let batteryVoltage: Double
    let mosTemperature: Double
    let rpm: Double
    let inputCurrent: Double
    let wattHours: Double
    let gpsSpeed: Double?
}

struct SessionLog: Codable, Identifiable {
    let id: UUID
    let startDate: Date
    var endDate: Date?
    var entries: [LogEntry]

    var duration: TimeInterval {
        (endDate ?? Date()).timeIntervalSince(startDate)
    }

    var entryCount: Int { entries.count }

    var peakRPM: Double { entries.map(\.rpm).max() ?? 0 }
    var peakCurrent: Double { entries.map(\.inputCurrent).max() ?? 0 }
    var maxTemp: Double { entries.map(\.mosTemperature).max() ?? 0 }
    var lastWattHours: Double { entries.last?.wattHours ?? 0 }
}

class SessionLogger: ObservableObject {
    @Published var isRecording = false
    @Published private(set) var currentSession: SessionLog?
    @Published private(set) var savedSessions: [SessionLog] = []

    private let fileManager = FileManager.default

    private var sessionsDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("VESCSessions", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    init() {
        loadSavedSessions()
    }

    func startSession() {
        currentSession = SessionLog(id: UUID(), startDate: Date(), entries: [])
        isRecording = true
        print("SessionLogger: started session \(currentSession!.id)")
    }

    func stopSession() {
        guard var session = currentSession else { return }
        session.endDate = Date()
        isRecording = false
        save(session: session)
        currentSession = nil
        loadSavedSessions()
        print("SessionLogger: stopped session \(session.id), \(session.entryCount) entries")
    }

    func logReading(batteryVoltage: Double, mosTemperature: Double, rpm: Double, inputCurrent: Double, wattHours: Double, gpsSpeed: Double? = nil) {
        guard isRecording, currentSession != nil else { return }

        let entry = LogEntry(
            timestamp: Date(),
            batteryVoltage: batteryVoltage,
            mosTemperature: mosTemperature,
            rpm: rpm,
            inputCurrent: inputCurrent,
            wattHours: wattHours,
            gpsSpeed: gpsSpeed
        )
        currentSession!.entries.append(entry)
    }

    func deleteSession(id: UUID) {
        let file = sessionsDirectory.appendingPathComponent("\(id.uuidString).json")
        try? fileManager.removeItem(at: file)
        savedSessions.removeAll { $0.id == id }
    }

    func deleteAllSessions() {
        for session in savedSessions {
            let file = sessionsDirectory.appendingPathComponent("\(session.id.uuidString).json")
            try? fileManager.removeItem(at: file)
        }
        savedSessions.removeAll()
    }

    private func save(session: SessionLog) {
        let file = sessionsDirectory.appendingPathComponent("\(session.id.uuidString).json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(session) {
            try? data.write(to: file, options: .atomic)
        }
    }

    private func loadSavedSessions() {
        guard let files = try? fileManager.contentsOfDirectory(at: sessionsDirectory, includingPropertiesForKeys: [.creationDateKey]) else {
            savedSessions = []
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        savedSessions = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> SessionLog? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(SessionLog.self, from: data)
            }
            .sorted { $0.startDate > $1.startDate }
    }
}
