import Foundation

@MainActor
final class ECGSessionController: ObservableObject {
  static let shared = ECGSessionController()

  @Published private(set) var activeSession: ECGSession?
  @Published private(set) var isRecording = false
  @Published private(set) var recordingElapsed: TimeInterval = 0
  @Published private(set) var liveSamples: [ECGSamplePoint] = []
  @Published private(set) var currentHeartRate: Int?
  @Published private(set) var signalQuality: ECGSignalQuality = .unknown
  @Published private(set) var recentSessions: [ECGSession] = []
  @Published private(set) var isLoadingSessions = false

  private let bridge = GooseRustBridge()
  private var recordingStartTime: Date?
  private var recordingTimer: Timer?
  private let recordingDuration: TimeInterval = 30.0
  private let slideWindowDuration: TimeInterval = 10.0

  private init() {}

  func loadRecentSessions() async {
    isLoadingSessions = true
    defer { isLoadingSessions = false }

    do {
      let dbPath = HealthDataStore.defaultDatabasePath()
      let result = try bridge.request(
        method: "ecg.list_sessions",
        args: ["database_path": dbPath]
      )
      if let sessionsJson = result["sessions"] as? [[String: Any]] {
        let data = try JSONSerialization.data(withJSONObject: sessionsJson)
        recentSessions = try JSONDecoder().decode([ECGSession].self, from: data)
      }
    } catch {
      return
    }
  }

  func startRecording() async -> Bool {
    guard !isRecording else { return false }
    guard let dbPath = databasePath() else { return false }

    let sessionId = "ecg-\(UUID().uuidString)"
    let startedAt = ISO8601DateFormatter().string(from: Date())

    do {
      let result = try bridge.request(
        method: "ecg.create_session",
        args: [
          "database_path": dbPath,
          "session_id": sessionId,
          "started_at": startedAt,
        ]
      )
      guard let sessionJson = result["session"] as? [String: Any] else { return false }
      let data = try JSONSerialization.data(withJSONObject: sessionJson)
      let session = try JSONDecoder().decode(ECGSession.self, from: data)

      activeSession = session
      isRecording = true
      liveSamples = []
      currentHeartRate = nil
      signalQuality = .good
      recordingStartTime = Date()
      recordingElapsed = 0

      startTimer()
      return true
    } catch {
      return false
    }
  }

  func stopRecording() async -> Bool {
    guard let session = activeSession, isRecording else { return false }
    guard let dbPath = databasePath() else { return false }

    stopTimer()

    let finishedAt = ISO8601DateFormatter().string(from: Date())

    do {
      let classification = basicClassificationFromCurrentState()

      let finishResult = try bridge.request(
        method: "ecg.finish_session",
        args: [
          "database_path": dbPath,
          "session_id": session.sessionId,
          "finished_at": finishedAt,
          "avg_heart_rate_bpm": currentHeartRate as Any,
          "classification": classification,
        ]
      )
      if let updatedJson = finishResult["session"] as? [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: updatedJson)
        activeSession = try JSONDecoder().decode(ECGSession.self, from: data)
      }

      isRecording = false
      await loadRecentSessions()
      return true
    } catch {
      isRecording = false
      return false
    }
  }

  func cancelRecording() async {
    stopTimer()
    if let session = activeSession, let dbPath = databasePath() {
      _ = try? bridge.request(
        method: "ecg.delete_session",
        args: [
          "database_path": dbPath,
          "session_id": session.sessionId,
        ]
      )
    }
    activeSession = nil
    isRecording = false
    liveSamples = []
    currentHeartRate = nil
    signalQuality = .unknown
    recordingElapsed = 0
  }

  func ingestFrame(packetK: Int, hexPayload: String, capturedAt: Date) {
    guard isRecording, let session = activeSession, let dbPath = databasePath() else { return }

    Task.detached(priority: .utility) { [weak self] in
      guard let self else { return }
      let bridge = GooseRustBridge()

      do {
        let samplesResult = try bridge.request(
          method: "ecg.extract_samples",
          args: ["hex_payload": hexPayload]
        )

        let sampleData = try JSONSerialization.data(withJSONObject: samplesResult)
        let labradorSamples = try JSONDecoder().decode(ECGLabradorSamples.self, from: sampleData)

        let frameId = "frame-\(UUID().uuidString)"
        let channelsGainHex = labradorSamples.channelsOrGain
          .map { String(format: "%02x", $0) }
          .joined()

        _ = try? bridge.request(
          method: "ecg.record_frame",
          args: [
            "database_path": dbPath,
            "session_id": session.sessionId,
            "frame_id": frameId,
            "packet_type": packetK,
            "sample_count": labradorSamples.parsedCount,
            "flags": labradorSamples.flags as Any,
            "channels_gain": channelsGainHex,
            "captured_at": ISO8601DateFormatter().string(from: capturedAt),
          ]
        )

        let newPoints = labradorSamples.samples.enumerated().map { index, value in
          ECGSamplePoint(
            id: "\(frameId)-\(index)",
            value: value,
            capturedAt: capturedAt.addingTimeInterval(TimeInterval(index) * (1.0 / 250.0)),
            packetType: packetK
          )
        }

        await MainActor.run { [newPoints] in
          self.liveSamples.append(contentsOf: newPoints)
          self.pruneOldSamples()
          self.updateHeartRateEstimate()
        }
      } catch {
        return
      }
    }
  }

  func setClassification(_ classification: String) async {
    guard let session = activeSession ?? recentSessions.first,
          let dbPath = databasePath() else { return }
    do {
      let result = try bridge.request(
        method: "ecg.set_classification",
        args: [
          "database_path": dbPath,
          "session_id": session.sessionId,
          "classification": classification,
        ]
      )
      if let updatedJson = result["session"] as? [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: updatedJson)
        let updated = try JSONDecoder().decode(ECGSession.self, from: data)
        if activeSession?.sessionId == updated.sessionId {
          activeSession = updated
        }
        if let idx = recentSessions.firstIndex(where: { $0.sessionId == updated.sessionId }) {
          recentSessions[idx] = updated
        }
      }
    } catch {
      return
    }
  }

  func setSymptomsAndNotes(symptoms: [String], notes: String?) async {
    guard let session = activeSession ?? recentSessions.first,
          let dbPath = databasePath() else { return }
    do {
      let symptomsData = try JSONEncoder().encode(symptoms)
      let symptomsStr = String(data: symptomsData, encoding: .utf8) ?? "[]"
      let result = try bridge.request(
        method: "ecg.set_symptoms_notes",
        args: [
          "database_path": dbPath,
          "session_id": session.sessionId,
          "symptoms_json": symptomsStr,
          "notes": notes as Any,
        ]
      )
      if let updatedJson = result["session"] as? [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: updatedJson)
        let updated = try JSONDecoder().decode(ECGSession.self, from: data)
        if activeSession?.sessionId == updated.sessionId {
          activeSession = updated
        }
        if let idx = recentSessions.firstIndex(where: { $0.sessionId == updated.sessionId }) {
          recentSessions[idx] = updated
        }
      }
    } catch {
      return
    }
  }

  func deleteSession(_ sessionId: String) async -> Bool {
    guard let dbPath = databasePath() else { return false }
    do {
      _ = try bridge.request(
        method: "ecg.delete_session",
        args: [
          "database_path": dbPath,
          "session_id": sessionId,
        ]
      )
      recentSessions.removeAll { $0.sessionId == sessionId }
      if activeSession?.sessionId == sessionId {
        activeSession = nil
        isRecording = false
      }
      return true
    } catch {
      return false
    }
  }

  func getSessionDetail(_ sessionId: String) async -> ECGSessionDetail? {
    guard let dbPath = databasePath() else { return nil }
    do {
      let result = try bridge.request(
        method: "ecg.get_session",
        args: [
          "database_path": dbPath,
          "session_id": sessionId,
        ]
      )
      let data = try JSONSerialization.data(withJSONObject: result)
      return try JSONDecoder().decode(ECGSessionDetail.self, from: data)
    } catch {
      return nil
    }
  }

  private func databasePath() -> String? {
    HealthDataStore.defaultDatabasePath()
  }

  private func startTimer() {
    recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, let start = self.recordingStartTime else { return }
        let elapsed = Date().timeIntervalSince(start)
        self.recordingElapsed = elapsed
        if elapsed >= self.recordingDuration {
          _ = await self.stopRecording()
        }
      }
    }
  }

  private func stopTimer() {
    recordingTimer?.invalidate()
    recordingTimer = nil
  }

  private func pruneOldSamples() {
    let cutoff = Date().addingTimeInterval(-slideWindowDuration)
    liveSamples = liveSamples.filter { $0.capturedAt > cutoff }
  }

  private func updateHeartRateEstimate() {
    guard liveSamples.count >= 250 else { return }
    let recent = liveSamples.suffix(500)
    let values = recent.map(\.value)
    guard let minVal = values.min(), let maxVal = values.max(), maxVal > minVal else { return }
    let threshold = minVal + (maxVal - minVal) / 2
    let crossings = zip(values, values.dropFirst()).filter { a, b in
      (a < threshold && b >= threshold) || (a >= threshold && b < threshold)
    }
    guard !crossings.isEmpty else { return }
    let avgCrossings = Double(crossings.count) / 2.0
    let durationSec = Double(recent.count) / 250.0
    let bpm = (avgCrossings / durationSec) * 60.0
    currentHeartRate = Int(bpm)
  }

  private func basicClassificationFromCurrentState() -> String {
    guard let hr = currentHeartRate else { return "inconclusive" }
    if hr < 50 { return "low_hr" }
    if hr > 100 { return "high_hr" }
    return "sinus_rhythm"
  }
}

enum ECGSignalQuality: String {
  case unknown
  case poor
  case fair
  case good

  var label: String {
    switch self {
    case .unknown: "Unknown"
    case .poor: "Poor"
    case .fair: "Fair"
    case .good: "Good"
    }
  }
}
