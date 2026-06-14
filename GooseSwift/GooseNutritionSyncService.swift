import Foundation
import OSLog

private let logger = Logger(subsystem: "com.goose.swift", category: "nutrition-sync")

struct NutritionSyncStatus {
  var lastSyncTimestamp: Date?
  var lastSyncDate: String?
  var isSyncing: Bool = false
  var lastError: String?
  var daysAvailable: Int = 0
}

final class GooseNutritionSyncService: @unchecked Sendable {
  private let cronometer = GooseCronometerAuth()
  private let databasePath: String
  private let session: URLSession
  private let stateLock = NSLock()

  private var _status = NutritionSyncStatus()
  private(set) var status: NutritionSyncStatus {
    get { stateLock.withLock { _status } }
    set { stateLock.withLock { _status = newValue } }
  }

  var onStatusUpdate: (@MainActor (NutritionSyncStatus) -> Void)?

  init(databasePath: String) {
    self.databasePath = databasePath
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 15
    self.session = URLSession(configuration: config)
  }

  // Initiate a nutrition sync cycle: fetch yesterday's totals from Cronometer,
  // upload to Goose server, and store locally for offline access.
  func sync(deviceID: String) async {
    guard CronometerKeychain.hasCredentials() else {
      logger.info("Nutrition sync skipped — no Cronometer credentials stored")
      return
    }

    stateLock.withLock { _status.isSyncing = true }
    publishStatus()
    defer {
      stateLock.withLock { _status.isSyncing = false }
      publishStatus()
    }

    // 1. Authenticate with Cronometer (if not already authenticated).
    do {
      if !cronometer.isAuthenticated {
        try await cronometer.login()
      }
    } catch {
      logger.warning("Cronometer login failed: \(error.localizedDescription)")
      stateLock.withLock { _status.lastError = "Cronometer login failed: \(error.localizedDescription)" }
      publishStatus()
      return
    }

    // 2. Fetch yesterday's nutrition data from Cronometer.
    let nutritionData: [String: Any]
    do {
      nutritionData = try await cronometer.fetchDailyNutrition()
    } catch {
      logger.warning("Cronometer fetch failed: \(error.localizedDescription)")
      stateLock.withLock { _status.lastError = "Cronometer fetch failed: \(error.localizedDescription)" }
      publishStatus()
      return
    }

    let dateStr = nutritionData["date"] as? String ?? ""

    // 3. Upload to Goose server (if configured).
    let serverURL = UserDefaults.standard.string(forKey: RemoteServerStorage.serverURL) ?? ""
    let uploadEnabled = UserDefaults.standard.bool(forKey: RemoteServerStorage.uploadEnabled)
    if !serverURL.isEmpty && uploadEnabled {
      if let token = try? RemoteServerKeychain.loadToken(), let token, !token.isEmpty {
        let entry = buildNutritionPayload(deviceID: deviceID, date: dateStr, data: nutritionData)
        do {
          try await postToServer(baseURL: serverURL, token: token, payload: entry)
          logger.info("Nutrition upload to server succeeded for \(dateStr)")
        } catch {
          logger.warning("Nutrition upload to server failed: \(error.localizedDescription)")
          // Non-fatal — local storage still proceeds.
        }
      }
    }

    // 4. Write to local metric_series for offline access + Coach queries.
    let bridge = GooseRustBridge()
    await writeToMetricSeries(bridge: bridge, dateStr: dateStr, data: nutritionData)

    // 5. Update status.
    stateLock.withLock {
      _status.lastSyncTimestamp = Date()
      _status.lastSyncDate = dateStr
      _status.lastError = nil
    }
    publishStatus()
  }

  // Fetch the last N days of nutrition from Cronometer (for backfill / first sync).
  func backfill(deviceID: String, days: Int = 30) async {
    guard CronometerKeychain.hasCredentials() else { return }

    stateLock.withLock { _status.isSyncing = true }
    publishStatus()
    defer {
      stateLock.withLock { _status.isSyncing = false }
      publishStatus()
    }

    do {
      if !cronometer.isAuthenticated {
        try await cronometer.login()
      }
    } catch {
      logger.warning("Cronometer backfill login failed: \(error.localizedDescription)")
      return
    }

    let serverURL = UserDefaults.standard.string(forKey: RemoteServerStorage.serverURL) ?? ""
    let uploadEnabled = UserDefaults.standard.bool(forKey: RemoteServerStorage.uploadEnabled)
    let token = (try? RemoteServerKeychain.loadToken()) ?? nil

    let cal = Calendar.current
    let today = Date()
    let bridge = GooseRustBridge()

    for offset in 1...days {
      guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
      let dateStr = "\(cal.component(.year, from: date))-\(cal.component(.month, from: date))-\(cal.component(.day, from: date))"

      let nutritionData: [String: Any]
      do {
        nutritionData = try await cronometer.fetchDailyNutrition(dateStr: dateStr)
      } catch {
        logger.info("Cronometer backfill fetch failed for \(dateStr): \(error.localizedDescription)")
        continue
      }

      if !serverURL.isEmpty && uploadEnabled, let token, !token.isEmpty {
        let entry = buildNutritionPayload(deviceID: deviceID, date: dateStr, data: nutritionData)
        try? await postToServer(baseURL: serverURL, token: token, payload: entry)
      }

      await writeToMetricSeries(bridge: bridge, dateStr: dateStr, data: nutritionData)
    }

    stateLock.withLock {
      _status.lastSyncTimestamp = Date()
      _status.daysAvailable = days
      _status.lastError = nil
    }
    publishStatus()
  }

  // Build the JSON payload for POST /v1/nutrition.
  private func buildNutritionPayload(deviceID: String, date: String, data: [String: Any]) -> [String: Any] {
    var payload: [String: Any] = [
      "device": deviceID,
      "date": date,
      "source": "cronometer",
    ]
    payload["calories"] = data["calories"]
    payload["protein_g"] = data["protein_g"]
    payload["carbs_g"] = data["carbs_g"]
    payload["fat_g"] = data["fat_g"]
    payload["fiber_g"] = data["fiber_g"]
    payload["sugar_g"] = data["sugar_g"]
    payload["saturated_fat_g"] = data["saturated_fat_g"]
    payload["sodium_mg"] = data["sodium_mg"]
    payload["cholesterol_mg"] = data["cholesterol_mg"]
    payload["micronutrients"] = data["micronutrients"]
    return payload
  }

  // POST to the Goose ingest server's /v1/nutrition endpoint.
  private func postToServer(baseURL: String, token: String, payload: [String: Any]) async throws {
    guard let url = URL(string: "\(baseURL)/v1/nutrition") else {
      throw URLError(.badURL)
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: payload)

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse,
          (200...299).contains(httpResponse.statusCode) else {
      throw URLError(.badServerResponse)
    }
  }

  // Write daily nutrition totals to local SQLite metric_series table via Rust bridge.
  // Uses the existing metric_series.upsert method — no Rust core changes needed.
  private func writeToMetricSeries(bridge: GooseRustBridge, dateStr: String, data: [String: Any]) async {
    let metrics: [(String, Double?)] = [
      ("nutrition.calories", data["calories"] as? Double),
      ("nutrition.protein_g", data["protein_g"] as? Double),
      ("nutrition.carbs_g", data["carbs_g"] as? Double),
      ("nutrition.fat_g", data["fat_g"] as? Double),
      ("nutrition.fiber_g", data["fiber_g"] as? Double),
      ("nutrition.sugar_g", data["sugar_g"] as? Double),
      ("nutrition.saturated_fat_g", data["saturated_fat_g"] as? Double),
      ("nutrition.sodium_mg", data["sodium_mg"] as? Double),
      ("nutrition.cholesterol_mg", data["cholesterol_mg"] as? Double),
    ]

    for (metricName, value) in metrics {
      guard let value else { continue }
      do {
        _ = try await bridge.requestAsync(
          method: "metric_series.upsert",
          args: [
            "database_path": databasePath,
            "source": "cronometer",
            "metric_name": metricName,
            "date": dateStr,
            "value": value,
          ]
        )
      } catch {
        logger.info("metric_series.upsert failed for \(metricName): \(error.localizedDescription)")
      }
    }

    // Write micronutrients as individual metric_series rows too.
    if let micros = data["micronutrients"] as? [String: Double] {
      for (name, amount) in micros {
        do {
          _ = try await bridge.requestAsync(
            method: "metric_series.upsert",
            args: [
              "database_path": databasePath,
              "source": "cronometer",
              "metric_name": "nutrition.\(name.lowercased())",
              "date": dateStr,
              "value": amount,
            ]
          )
        } catch {
          // Best-effort — skip individual micronutrient write failures.
        }
      }
    }
  }

  private func publishStatus() {
    let s = stateLock.withLock { _status }
    Task { @MainActor [onStatusUpdate] in
      onStatusUpdate?(s)
    }
  }
}
