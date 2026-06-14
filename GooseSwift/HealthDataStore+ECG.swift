import Foundation

extension HealthDataStore {

  func classifyECGSession(_ sessionId: String) async -> String? {
    let dbPath: String = Self.defaultDatabasePath()
    do {
      let result = try await bridge.requestAsync(
        method: "ecg.classify_basic",
        args: [
          "database_path": dbPath,
          "session_id": sessionId,
        ]
      )
      return result["classification"] as? String
    } catch {
      return nil
    }
  }

  func fetchECGSessionDetail(_ sessionId: String) async -> [String: Any]? {
    let dbPath: String = Self.defaultDatabasePath()
    do {
      return try await bridge.requestAsync(
        method: "ecg.get_session",
        args: [
          "database_path": dbPath,
          "session_id": sessionId,
        ]
      )
    } catch {
      return nil
    }
  }
}
