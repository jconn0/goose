import Foundation
import SwiftUI

// Display model for a single day's nutrition totals.
struct NutritionDayItem: Identifiable {
  let id: String               // "YYYY-MM-DD"
  let date: String
  let source: String
  let calories: Double
  let proteinG: Double?
  let carbsG: Double?
  let fatG: Double?
  let fiberG: Double?
  let sugarG: Double?
  let saturatedFatG: Double?
  let sodiumMg: Double?
  let cholesterolMg: Double?
  let micronutrients: [String: Double]  // name → amount

  // Convenience accessors.
  var proteinPercent: Double { macroPercent(grams: proteinG ?? 0, kcalPerGram: 4) }
  var carbsPercent: Double { macroPercent(grams: carbsG ?? 0, kcalPerGram: 4) }
  var fatPercent: Double { macroPercent(grams: fatG ?? 0, kcalPerGram: 9) }

  private func macroPercent(grams: Double, kcalPerGram: Double) -> Double {
    let kcal = grams * kcalPerGram
    guard calories > 0 else { return 0 }
    return kcal / calories
  }

  var formattedCalories: String {
    calories > 0 ? "\(Int(calories.rounded()))" : "--"
  }

  var formattedProtein: String {
    if let p = proteinG, p > 0 { return "\(Int(p.rounded()))g" }
    return "--"
  }

  var formattedCarbs: String {
    if let c = carbsG, c > 0 { return "\(Int(c.rounded()))g" }
    return "--"
  }

  var formattedFat: String {
    if let f = fatG, f > 0 { return "\(Int(f.rounded()))g" }
    return "--"
  }

  var dateLabel: String {
    guard let d = ISO8601DateFormatter().date(from: "\(date)T00:00:00Z") else {
      return date
    }
    return d.formatted(.dateTime.weekday(.abbreviated).day())
  }
}

// Lightweight summary computed from the NutritionDayItem array.
struct NutritionWeeklySummary {
  let avgCalories: Double
  let avgProtein: Double
  let avgCarbs: Double
  let avgFat: Double
  let dayCount: Int

  var formattedAvgCalories: String {
    dayCount > 0 ? "\(Int(avgCalories.rounded()))" : "--"
  }
}

extension HealthDataStore {

  // Fetch nutrition data from the Goose server for a date range.
  // Falls back to local metric_series if the server is unavailable.
  func fetchNutritionRange(from startDate: String, to endDate: String) async {
    nutritionStatus = "Fetching..."

    // Try server first.
    let serverURL = UserDefaults.standard.string(forKey: RemoteServerStorage.serverURL) ?? ""
    if !serverURL.isEmpty,
       let token = try? RemoteServerKeychain.loadToken(), let token, !token.isEmpty {
      if let serverDays = await fetchFromServer(baseURL: serverURL, token: token,
                                                from: startDate, to: endDate) {
        nutritionDays = serverDays
        nutritionStatus = "Synced (server)"
        nutritionLatestDate = serverDays.last?.date
        return
      }
    }

    // Fall back to local metric_series.
    let localDays = await fetchFromLocalMetricSeries(from: startDate, to: endDate)
    if !localDays.isEmpty {
      nutritionDays = localDays
      nutritionStatus = "Local only"
      nutritionLatestDate = localDays.last?.date
    } else {
      nutritionStatus = "No nutrition data"
    }
  }

  func fetchTodayNutrition() async {
    let today = dateKey(for: Date())
    await fetchNutritionRange(from: today, to: today)
  }

  func fetchWeekNutrition() async {
    let cal = Calendar.current
    let today = Date()
    guard let weekAgo = cal.date(byAdding: .day, value: -6, to: today) else { return }
    await fetchNutritionRange(from: dateKey(for: weekAgo), to: dateKey(for: today))
  }

  // Compute a weekly summary from the in-memory nutritionDays.
  func buildWeeklySummary() -> NutritionWeeklySummary {
    let days = nutritionDays
    guard !days.isEmpty else {
      return NutritionWeeklySummary(avgCalories: 0, avgProtein: 0, avgCarbs: 0, avgFat: 0, dayCount: 0)
    }
    let count = days.count
    let totalCal = days.reduce(0) { $0 + $1.calories }
    let totalProtein = days.reduce(0) { $0 + ($1.proteinG ?? 0) }
    let totalCarbs = days.reduce(0) { $0 + ($1.carbsG ?? 0) }
    let totalFat = days.reduce(0) { $0 + ($1.fatG ?? 0) }
    return NutritionWeeklySummary(
      avgCalories: totalCal / Double(count),
      avgProtein: totalProtein / Double(count),
      avgCarbs: totalCarbs / Double(count),
      avgFat: totalFat / Double(count),
      dayCount: count
    )
  }

  // Fetch nutrition rows from the server's /v1/nutrition/range endpoint.
  private func fetchFromServer(baseURL: String, token: String,
                               from: String, to: String) async -> [NutritionDayItem]? {
    guard var components = URLComponents(string: "\(baseURL)/v1/nutrition/range") else {
      return nil
    }
    // Use a generic device query — the server returns rows for the caller's device.
    // The iOS app passes a device identifier; the server filters by it.
    // Until we wire up the device UUID to nutrition queries, use a sentinel.
    components.queryItems = [
      URLQueryItem(name: "device", value: deviceIDForNutrition()),
      URLQueryItem(name: "from", value: from),
      URLQueryItem(name: "to", value: to),
    ]
    guard let url = components.url else { return nil }

    var request = URLRequest(url: url)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.timeoutInterval = 10

    let session = URLSession(configuration: .ephemeral)
    do {
      let (data, response) = try await session.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode),
            let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        return nil
      }
      return rows.compactMap { parseNutritionRow($0) }
    } catch {
      return nil
    }
  }

  // Fetch nutrition from local metric_series table via Rust bridge.
  private func fetchFromLocalMetricSeries(from startDate: String, to endDate: String) async -> [NutritionDayItem] {
    // Query all known nutrition metric names for the date range.
    let metricNames = [
      "nutrition.calories", "nutrition.protein_g", "nutrition.carbs_g",
      "nutrition.fat_g", "nutrition.fiber_g", "nutrition.sugar_g",
      "nutrition.saturated_fat_g", "nutrition.sodium_mg", "nutrition.cholesterol_mg",
    ]

    // Collect dates in range.
    let cal = Calendar.current
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd"
    guard let start = fmt.date(from: startDate),
          let end = fmt.date(from: endDate) else {
      return []
    }
    var dates: [String] = []
    var cursor = start
    while cursor <= end {
      dates.append(fmt.string(from: cursor))
      guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
      cursor = next
    }

    // For each date, query all metrics and assemble NutritionDayItem.
    var items: [NutritionDayItem] = []
    for date in dates {
      var values: [String: Double] = [:]
      for name in metricNames {
        do {
          let result = try await bridge.requestAsync(
            method: "metric_series.query_range",
            args: [
              "database_path": databasePath,
              "metric_name": name,
              "start_date": date,
              "end_date": date,
              "source": "cronometer",
            ]
          )
          if let rows = result["rows"] as? [[String: Any]],
             let firstRow = rows.first,
             let value = firstRow["value"] as? Double {
            values[name] = value
          }
        } catch {
          // Skip individual metric errors.
        }
      }
      guard let calories = values["nutrition.calories"], calories > 0 else { continue }
      items.append(NutritionDayItem(
        id: date, date: date, source: "cronometer",
        calories: calories,
        proteinG: values["nutrition.protein_g"],
        carbsG: values["nutrition.carbs_g"],
        fatG: values["nutrition.fat_g"],
        fiberG: values["nutrition.fiber_g"],
        sugarG: values["nutrition.sugar_g"],
        saturatedFatG: values["nutrition.saturated_fat_g"],
        sodiumMg: values["nutrition.sodium_mg"],
        cholesterolMg: values["nutrition.cholesterol_mg"],
        micronutrients: [:]
      ))
    }
    return items.sorted { $0.date < $1.date }
  }

  private func parseNutritionRow(_ row: [String: Any]) -> NutritionDayItem? {
    guard let date = row["date"] as? String else { return nil }
    let calories = row["calories"] as? Double ?? 0
    return NutritionDayItem(
      id: date,
      date: date,
      source: row["source"] as? String ?? "cronometer",
      calories: calories,
      proteinG: row["protein_g"] as? Double,
      carbsG: row["carbs_g"] as? Double,
      fatG: row["fat_g"] as? Double,
      fiberG: row["fiber_g"] as? Double,
      sugarG: row["sugar_g"] as? Double,
      saturatedFatG: row["saturated_fat_g"] as? Double,
      sodiumMg: row["sodium_mg"] as? Double,
      cholesterolMg: row["cholesterol_mg"] as? Double,
      micronutrients: row["micronutrients"] as? [String: Double] ?? [:]
    )
  }

  private func dateKey(for date: Date) -> String {
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd"
    return fmt.string(from: date)
  }

  // Returns a stable device identifier for nutrition queries.
  // Uses a persistent identifier stored in UserDefaults.
  private func deviceIDForNutrition() -> String {
    if let stored = UserDefaults.standard.string(forKey: "goose.nutrition.deviceID"),
       !stored.isEmpty {
      return stored
    }
    let generated = UUID().uuidString
    UserDefaults.standard.set(generated, forKey: "goose.nutrition.deviceID")
    return generated
  }

  // Build the nutrition landing snapshot for the Health tab grid.
  func nutritionSnapshot(base snapshot: HealthMetricSnapshot) -> HealthMetricSnapshot {
    let latest = nutritionDays.last ?? nutritionDays.first
    if let day = latest, day.calories > 0 {
      return Self.replacingHealthMonitorSnapshot(
        snapshot,
        value: "\(Int(day.calories.rounded()))",
        unit: "kcal",
        status: day.dateLabel,
        freshness: nutritionStatus == "Synced (server)" ? "Synced" : "Local",
        provenance: "cronometer",
        source: .live("cronometer sync"),
        trend: Self.emptyTrend(from: snapshot.trend, packetCount: 0)
      )
    }
    return Self.replacingHealthMonitorSnapshot(
      snapshot,
      value: "--",
      unit: "kcal",
      status: nutritionStatus,
      freshness: nutritionStatus,
      provenance: "cronometer",
      source: .unavailable("connect Cronometer in Settings to sync nutrition data"),
      trend: Self.emptyTrend(from: snapshot.trend, packetCount: 0)
    )
  }
}
