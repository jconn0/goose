import Foundation
import OSLog
import Security

private let logger = Logger(subsystem: "com.goose.swift", category: "cronometer")

enum CronometerAuthError: Error, LocalizedError {
  case missingCredentials
  case loginFailed(String)
  case keychainError(OSStatus)

  var errorDescription: String? {
    switch self {
    case .missingCredentials:
      return "Cronometer email and password are required"
    case .loginFailed(let message):
      return "Cronometer login failed: \(message)"
    case .keychainError(let status):
      return "Cronometer Keychain error: \(status)"
    }
  }
}

// Stores Cronometer email/password in the iOS Keychain (never on the server).
// Session tokens are kept in-memory and auto-refreshed when they expire.
enum CronometerKeychain {
  private static let service = "goose.cronometer"
  private static let emailAccount = "email"
  private static let passwordAccount = "password"

  static func saveCredentials(email: String, password: String) throws {
    try save(account: emailAccount, value: email)
    try save(account: passwordAccount, value: password)
  }

  static func loadCredentials() -> (email: String, password: String)? {
    guard let email = load(account: emailAccount),
          let password = load(account: passwordAccount),
          !email.isEmpty, !password.isEmpty else {
      return nil
    }
    return (email, password)
  }

  static func deleteCredentials() throws {
    try delete(account: emailAccount)
    try delete(account: passwordAccount)
  }

  static func hasCredentials() -> Bool {
    loadCredentials() != nil
  }

  private static func save(account: String, value: String) throws {
    let data = Data(value.utf8)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    SecItemDelete(query as CFDictionary)
    var attributes = query
    attributes[kSecValueData as String] = data
    attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let status = SecItemAdd(attributes as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw CronometerAuthError.keychainError(status)
    }
  }

  private static func load(account: String) -> String? {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  private static func delete(account: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw CronometerAuthError.keychainError(status)
    }
  }
}

final class GooseCronometerAuth: @unchecked Sendable {
  private let session: URLSession
  private var userId: Int?
  private var sessionToken: String?
  private let stateLock = NSLock()
  private let baseURL = "https://mobile.cronometer.com"

  init() {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 30
    self.session = URLSession(configuration: config)
  }

  var isAuthenticated: Bool {
    stateLock.withLock { sessionToken != nil }
  }

  func hasStoredCredentials() -> Bool {
    CronometerKeychain.hasCredentials()
  }

  // Authenticate with Cronometer and cache the session token in memory.
  func login() async throws {
    guard let creds = CronometerKeychain.loadCredentials() else {
      throw CronometerAuthError.missingCredentials
    }

    let payload: [String: Any] = [
      "email": creds.email,
      "password": creds.password,
      "timezone": TimeZone.current.identifier,
      "userCode": NSNull(),
      "build": "4.48.2 b2807-a",
      "device": "iPhone",
      "firebaseToken": "",
      "features": [
        "food_search_config": "{\"newSearch\": true, \"newSpellcheck\": true}",
        "use_gpt_autofill": "true",
      ],
      "auth": [
        "userId": NSNull(),
        "token": NSNull(),
        "api": 3,
        "os": "iOS",
        "build": "2807",
        "flavour": "free",
      ],
      "lastSeen": 0,
      "config": ["call_version": 2],
    ]

    let data: [String: Any] = try await postJSON(path: "/api/v2/login", body: payload, authRequired: false)

    guard let token = data["sessionKey"] as? String,
          let uid = data["id"] as? Int else {
      throw CronometerAuthError.loginFailed("Unexpected response: \(data)")
    }

    stateLock.withLock {
      self.userId = uid
      self.sessionToken = token
    }
    logger.info("Cronometer login successful (userId=\(uid))")
  }

  // Fetch consumed nutrition totals for a given date (YYYY-M-D format).
  func fetchDailyNutrition(dateStr: String? = nil) async throws -> [String: Any] {
    let day = dateStr ?? cronometerDayString(for: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())

    // Fetch nutrients summary for the day.
    let nutrientsPayload: [String: Any] = [
      "day": day,
      "config": ["call_version": 1],
    ]
    let nutrientsData: [String: Any] = try await postJSON(path: "/api/v2/get_nutrients", body: nutrientsPayload)

    // Build a flat summary of macros + all tracked nutrients.
    var result: [String: Any] = ["date": day]

    // Extract nutrient definitions (name, unit) from the response.
    let nutrientDefs = nutrientsData["nutrients"] as? [[String: Any]] ?? []
    var defsById: [Int: [String: Any]] = [:]
    for n in nutrientDefs {
      guard let nid = n["id"] as? Int else { continue }
      defsById[nid] = n
    }

    // Build consumed amounts map from nutrient targets (these carry the actual consumed amounts).
    let groups = nutrientsData["groups"] as? [[String: Any]] ?? []
    var consumedByNutrientId: [Int: Double] = [:]
    for group in groups {
      for target in group["targets"] as? [[String: Any]] ?? [] {
        guard let nid = target["nutrientId"] as? Int,
              let consumed = target["consumed"] as? Double else { continue }
        consumedByNutrientId[nid] = consumed
      }
    }

    // Map known macro IDs to flat fields.
    // Cronometer nutrient IDs: 208=energy, 203=protein, 205=carbs, 204=fat, 291=fiber, 269=sugar, 606=sat_fat, 307=sodium, 601=cholesterol
    result["calories"] = consumedByNutrientId[208]
    result["protein_g"] = consumedByNutrientId[203]
    result["carbs_g"] = consumedByNutrientId[205]
    result["fat_g"] = consumedByNutrientId[204]
    result["fiber_g"] = consumedByNutrientId[291]
    result["sugar_g"] = consumedByNutrientId[269]
    result["saturated_fat_g"] = consumedByNutrientId[606]
    result["sodium_mg"] = consumedByNutrientId[307]
    result["cholesterol_mg"] = consumedByNutrientId[601]

    // Collect remaining tracked nutrients as micronutrients dict.
    let knownIds: Set<Int> = [208, 203, 205, 204, 291, 269, 606, 307, 601]
    var micros: [String: Double] = [:]
    for (nid, amount) in consumedByNutrientId {
      if knownIds.contains(nid) { continue }
      guard let def = defsById[nid],
            let name = def["name"] as? String else { continue }
      micros[name] = amount
    }
    result["micronutrients"] = micros

    logger.info("Fetched Cronometer nutrition for \(day): \(consumedByNutrientId[208] ?? 0) kcal")
    return result
  }

  // Get diary entries for a given date.
  func fetchDiary(dateStr: String? = nil) async throws -> [String: Any] {
    let day = dateStr ?? cronometerDayString(for: Date())
    let payload: [String: Any] = [
      "day": day,
      "config": ["call_version": 1],
    ]
    return try await postJSON(path: "/api/v2/get_diary", body: payload)
  }

  // POST JSON to Cronometer API with auth injection. Retries once on 401/403.
  private func postJSON(path: String, body: [String: Any], authRequired: Bool = true, retried: Bool = false) async throws -> [String: Any] {
    guard let url = URL(string: "\(baseURL)\(path)") else {
      throw CronometerAuthError.loginFailed("Invalid URL: \(path)")
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Dart/3.9 (dart:io)", forHTTPHeaderField: "User-Agent")
    request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
    request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")

    var fullBody = body
    if authRequired {
      stateLock.lock()
      let token = sessionToken
      let uid = userId
      stateLock.unlock()

      guard let token, let uid else {
        if !retried {
          try await login()
          return try await postJSON(path: path, body: body, authRequired: true, retried: true)
        }
        throw CronometerAuthError.missingCredentials
      }
      fullBody["auth"] = [
        "userId": uid,
        "token": token,
        "api": 3,
        "os": "iOS",
        "build": "2807",
        "flavour": "free",
      ]
    }
    fullBody["lastSeen"] = fullBody["lastSeen"] ?? 0

    request.httpBody = try JSONSerialization.data(withJSONObject: fullBody)

    let (data, response) = try await session.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw CronometerAuthError.loginFailed("No HTTP response")
    }

    if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
      if !retried {
        stateLock.withLock { self.sessionToken = nil }
        try await login()
        return try await postJSON(path: path, body: body, authRequired: true, retried: true)
      }
      throw CronometerAuthError.loginFailed("Authentication rejected (status \(httpResponse.statusCode))")
    }

    guard (200...299).contains(httpResponse.statusCode) else {
      let bodyText = String(data: data, encoding: .utf8) ?? ""
      throw CronometerAuthError.loginFailed("HTTP \(httpResponse.statusCode): \(bodyText.prefix(200))")
    }

    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw CronometerAuthError.loginFailed("Response is not JSON")
    }

    return json
  }

  private func cronometerDayString(for date: Date) -> String {
    let cal = Calendar.current
    return "\(cal.component(.year, from: date))-\(cal.component(.month, from: date))-\(cal.component(.day, from: date))"
  }
}

// One-shot helper: given a Cronometer email + password, test the login and return the user's display info.
extension GooseCronometerAuth {
  static func verifyCredentials(email: String, password: String) async throws -> [String: Any] {
    let auth = GooseCronometerAuth()
    try CronometerKeychain.saveCredentials(email: email, password: password)
    defer { try? CronometerKeychain.deleteCredentials() }

    try await auth.login()

    // Fetch today's diary as a smoke test — confirms the token is valid for data access.
    let today = auth.cronometerDayString(for: Date())
    let diary = try await auth.fetchDiary(dateStr: today)
    let name = (diary["profile"] as? [String: Any])?["name"] as? String ?? email
    return ["connected": true, "name": name, "date": today]
  }
}
