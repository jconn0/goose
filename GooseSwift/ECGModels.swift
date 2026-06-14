import Foundation

struct ECGSession: Codable, Identifiable, Equatable {
  var id: String { sessionId }
  let sessionId: String
  var status: String
  let startedAt: String
  var finishedAt: String?
  var durationSeconds: Double?
  var avgHeartRateBpm: Int?
  var classification: String?
  var symptomsJson: String
  var notes: String?

  var symptoms: [String] {
    guard let data = symptomsJson.data(using: .utf8),
          let decoded = try? JSONDecoder().decode([String].self, from: data) else {
      return []
    }
    return decoded
  }

  var startedDate: Date? {
    ISO8601DateFormatter().date(from: startedAt)
  }

  var finishedDate: Date? {
    finishedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
  }

  var durationFormatted: String {
    guard let duration = durationSeconds else { return "--" }
    let minutes = Int(duration) / 60
    let seconds = Int(duration) % 60
    return "\(minutes):\(String(format: "%02d", seconds))"
  }

  var classificationLabel: String {
    guard let c = classification else { return "Pending" }
    switch c {
    case "sinus_rhythm": "Sinus Rhythm"
    case "inconclusive": "Inconclusive"
    case "unreadable": "Unreadable"
    case "low_hr": "Low Heart Rate"
    case "high_hr": "High Heart Rate"
    case "inconclusive_no_frames": "No Data"
    default: c
    }
  }
}

struct ECGSessionFrame: Codable, Identifiable, Equatable {
  var id: String { "\(sessionId)-\(frameId)" }
  let sessionId: String
  let frameId: String
  let packetType: Int
  let sampleCount: Int
  let flags: Int?
  let channelsGain: String?
  let capturedAt: String
}

struct ECGSessionDetail: Codable {
  let session: ECGSession
  let frames: [ECGSessionFrame]
  let sampleCountTotal: Int
}

struct ECGLabradorSamples: Codable {
  let samples: [Int]
  let flags: Int
  let channelsOrGain: [Int]
  let sampleCount: Int
  let parsedCount: Int

  enum CodingKeys: String, CodingKey {
    case samples, flags
    case channelsOrGain = "channels_or_gain"
    case sampleCount = "sample_count"
    case parsedCount = "parsed_count"
  }
}

struct ECGSamplePoint: Identifiable, Equatable {
  let id: String
  let value: Int
  let capturedAt: Date
  let packetType: Int
}

enum ECGClassification: String, CaseIterable, Identifiable {
  case sinusRhythm = "sinus_rhythm"
  case inconclusive
  case unreadable
  case lowHR = "low_hr"
  case highHR = "high_hr"

  var id: String { rawValue }

  var label: String {
    switch self {
    case .sinusRhythm: "Sinus Rhythm"
    case .inconclusive: "Inconclusive"
    case .unreadable: "Unreadable"
    case .lowHR: "Low Heart Rate"
    case .highHR: "High Heart Rate"
    }
  }
}

enum ECGSymptom: String, CaseIterable, Identifiable {
  case chestPain = "chest_pain"
  case dizziness
  case palpitations
  case shortnessOfBreath = "shortness_of_breath"
  case fatigue
  case lightheaded
  case skippedBeat = "skipped_beat"
  case rapidHeartbeat = "rapid_heartbeat"

  var id: String { rawValue }

  var label: String {
    switch self {
    case .chestPain: "Chest Pain"
    case .dizziness: "Dizziness"
    case .palpitations: "Palpitations"
    case .shortnessOfBreath: "Shortness of Breath"
    case .fatigue: "Fatigue"
    case .lightheaded: "Lightheaded"
    case .skippedBeat: "Skipped Beat"
    case .rapidHeartbeat: "Rapid Heartbeat"
    }
  }
}

enum ECGOnboardingStorage {
  private static let key = "goose.ecg.onboardingComplete"

  static var isComplete: Bool {
    get { UserDefaults.standard.bool(forKey: key) }
    set { UserDefaults.standard.set(newValue, forKey: key) }
  }
}
