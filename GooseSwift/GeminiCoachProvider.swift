import Foundation
import Security

// MARK: - GeminiKeychainError

enum GeminiKeychainError: Error {
  case saveFailed(OSStatus)
  case deleteFailed(OSStatus)
}

// MARK: - GeminiKeychain

enum GeminiKeychain {
  private static let service = "com.goose.swift.gemini"
  private static let account = "api-key"

  static func save(_ key: String) throws {
    let data = Data(key.utf8)
    let query = baseQuery()
    SecItemDelete(query as CFDictionary)

    var attributes = query
    attributes[kSecValueData as String] = data
    attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    let status = SecItemAdd(attributes as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw GeminiKeychainError.saveFailed(status)
    }
  }

  static func load() throws -> String? {
    var query = baseQuery()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status != errSecItemNotFound else {
      return nil
    }
    guard status == errSecSuccess else {
      return nil
    }
    guard let data = result as? Data else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  static func delete() throws {
    let status = SecItemDelete(baseQuery() as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw GeminiKeychainError.deleteFailed(status)
    }
  }

  private static func baseQuery() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }
}

// MARK: - GeminiCredentialStore (internal facade for tests)

enum GeminiCredentialStore {
  static func save(_ key: String) throws {
    try GeminiKeychain.save(key)
  }

  static func load() throws -> String? {
    try GeminiKeychain.load()
  }

  static func delete() throws {
    try GeminiKeychain.delete()
  }
}

// MARK: - GeminiProviderError

enum GeminiProviderError: Error, LocalizedError {
  case missingAPIKey
  case invalidResponse
  case noModelSelected
  case modelFetchFailed(String)
  case streamError(String)

  var errorDescription: String? {
    switch self {
    case .missingAPIKey:
      return String(localized: "API key not found")
    case .invalidResponse:
      return String(localized: "Invalid response from server")
    case .noModelSelected:
      return String(localized: "No model selected")
    case .modelFetchFailed(let message):
      return message
    case .streamError(let message):
      return message
    }
  }
}

// MARK: - GeminiModel

struct GeminiModel: Identifiable, Equatable {
  let id: String
  let displayName: String
}

// MARK: - GeminiCoachProvider

@MainActor
@Observable
final class GeminiCoachProvider: CoachProvider {
  static let selectedModelIDKey = "goose.coach.gemini.selectedModelID"

  let id = "gemini"
  let displayName = "Gemini"
  let availablePresets: [CoachModelPreset] = []

  private(set) var isAuthenticated: Bool
  private(set) var isLoadingModels = false
  private(set) var availableModels: [GeminiModel] = []
  private(set) var modelFetchError: String?

  init() {
    isAuthenticated = (try? GeminiKeychain.load()) != nil
  }

  var selectedModelID: String {
    get { UserDefaults.standard.string(forKey: Self.selectedModelIDKey) ?? "" }
    set { UserDefaults.standard.set(newValue, forKey: Self.selectedModelIDKey) }
  }

  func saveAPIKey(_ key: String) throws {
    try GeminiKeychain.save(key)
    isAuthenticated = true
  }

  func signOut() {
    try? GeminiKeychain.delete()
    UserDefaults.standard.removeObject(forKey: Self.selectedModelIDKey)
    isAuthenticated = false
    availableModels = []
    modelFetchError = nil
  }

  func fetchAvailableModels() async {
    isLoadingModels = true
    modelFetchError = nil
    defer { isLoadingModels = false }

    guard let apiKey = try? GeminiKeychain.load(), !apiKey.isEmpty else {
      modelFetchError = String(localized: "API key not found")
      return
    }

    do {
      let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)")!
      var request = URLRequest(url: url)
      request.httpMethod = "GET"
      request.timeoutInterval = 30

      let (data, response) = try await URLSession.shared.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse else {
        modelFetchError = String(localized: "Invalid response from server")
        return
      }
      guard (200..<300).contains(httpResponse.statusCode) else {
        modelFetchError = String(localized: "Server returned error \(httpResponse.statusCode)")
        return
      }

      guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let models = json["models"] as? [[String: Any]] else {
        modelFetchError = String(localized: "Failed to parse models list")
        return
      }

      let parsedModels = models.compactMap { model -> GeminiModel? in
        guard let name = model["name"] as? String,
              let displayName = model["displayName"] as? String,
              let methods = model["supportedGenerationMethods"] as? [String],
              methods.contains("streamGenerateContent") else {
          return nil
        }
        let modelID = name.hasPrefix("models/") ? String(name.dropFirst(7)) : name
        return GeminiModel(id: modelID, displayName: displayName)
      }

      guard !parsedModels.isEmpty else {
        modelFetchError = String(localized: "No streaming-capable models found")
        return
      }

      availableModels = parsedModels

      let currentID = selectedModelID
      if currentID.isEmpty {
        selectedModelID = parsedModels[0].id
      } else if !parsedModels.contains(where: { $0.id == currentID }) {
        selectedModelID = parsedModels[0].id
      }
    } catch {
      modelFetchError = String(localized: "Network error: \(error.localizedDescription)")
    }
  }

  func send(
    messages: [CoachChatMessage],
    systemPrompt: String,
    preset: CoachModelPreset
  ) async throws -> AsyncStream<String> {
    guard let apiKey = try GeminiKeychain.load(), !apiKey.isEmpty else {
      throw GeminiProviderError.missingAPIKey
    }

    let modelID = selectedModelID
    guard !modelID.isEmpty else {
      throw GeminiProviderError.noModelSelected
    }

    let request = try buildRequest(
      messages: messages,
      systemPrompt: systemPrompt,
      modelID: modelID,
      apiKey: apiKey
    )

    let (initialBytes, initialResponse) = try await URLSession.shared.bytes(for: request)
    guard let httpResponse = initialResponse as? HTTPURLResponse else {
      throw GeminiProviderError.invalidResponse
    }

    guard (200..<300).contains(httpResponse.statusCode) else {
      var errorBody = ""
      for try await line in initialBytes.lines {
        errorBody += line
      }
      let message: String
      switch httpResponse.statusCode {
      case 401:
        message = String(localized: "Authentication failed. Check your API key.")
      case 403:
        message = String(localized: "Access forbidden. Your API key may lack permissions.")
      case 429:
        message = String(localized: "Rate limit exceeded. Please try again later.")
      default:
        message = errorBody.isEmpty
          ? String(localized: "Server returned error \(httpResponse.statusCode)")
          : String(localized: "Error \(httpResponse.statusCode): \(errorBody)")
      }
      throw GeminiProviderError.streamError(message)
    }

    return AsyncStream { continuation in
      Task {
        do {
          for try await line in initialBytes.lines {
            try Task.checkCancellation()
            if let delta = self.extractGeminiDelta(from: line) {
              continuation.yield(delta)
            }
          }
          continuation.finish()
        } catch {
          continuation.finish()
        }
      }
    }
  }

  // MARK: - Internal helpers

  nonisolated func extractGeminiDelta(from line: String) -> String? {
    guard line.hasPrefix("data:") else { return nil }
    let jsonString = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
    guard let data = jsonString.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let candidates = obj["candidates"] as? [[String: Any]],
          let first = candidates.first,
          let content = first["content"] as? [String: Any],
          let parts = content["parts"] as? [[String: Any]],
          let text = parts.first?["text"] as? String else { return nil }
    return text
  }

  private func buildRequest(
    messages: [CoachChatMessage],
    systemPrompt: String,
    modelID: String,
    apiKey: String
  ) throws -> URLRequest {
    let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(modelID):streamGenerateContent?key=\(apiKey)&alt=sse"
    guard let url = URL(string: urlString) else {
      throw GeminiProviderError.invalidResponse
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 180

    let body: [String: Any] = [
      "systemInstruction": ["parts": [["text": systemPrompt]]],
      "contents": messages.map { msg -> [String: Any] in
        let role = msg.role == .user ? "user" : "model"
        return ["role": role, "parts": [["text": msg.text]]]
      },
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    return request
  }
}
