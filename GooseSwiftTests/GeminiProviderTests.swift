import XCTest
@testable import GooseSwift

@MainActor
final class GeminiProviderTests: XCTestCase {

  // MARK: - Keychain roundtrip

  func testGeminiKeychainRoundtrip() throws {
    let key = "test-api-key-12345"

    try? GeminiCredentialStore.delete()

    try GeminiCredentialStore.save(key)

    let loaded = try GeminiCredentialStore.load()
    XCTAssertNotNil(loaded, "Loaded key must not be nil after save")
    XCTAssertEqual(loaded, key, "Loaded key must match saved key")

    try GeminiCredentialStore.delete()
    let afterDelete = try GeminiCredentialStore.load()
    XCTAssertNil(afterDelete, "Loaded key must be nil after delete")
  }

  // MARK: - SSE delta extraction

  func testGeminiDeltaExtraction() throws {
    let provider = GeminiCoachProvider()

    let validLine = #"data: {"candidates":[{"content":{"parts":[{"text":"Hello"}]}}]}"#
    let result = provider.extractGeminiDelta(from: validLine)
    XCTAssertEqual(result, "Hello", "extractGeminiDelta must return 'Hello' for a valid candidates line")

    let emptyCandidates = #"data: {"candidates":[]}"#
    let resultEmpty = provider.extractGeminiDelta(from: emptyCandidates)
    XCTAssertNil(resultEmpty, "extractGeminiDelta must return nil for empty candidates array")

    let noPrefix = #"{"candidates":[{"content":{"parts":[{"text":"Hello"}]}}]}"#
    let resultNoPrefix = provider.extractGeminiDelta(from: noPrefix)
    XCTAssertNil(resultNoPrefix, "extractGeminiDelta must return nil for line without data: prefix")

    let noText = #"data: {"candidates":[{"content":{"parts":[{"image":"abc"}]}}]}"#
    let resultNoText = provider.extractGeminiDelta(from: noText)
    XCTAssertNil(resultNoText, "extractGeminiDelta must return nil when text key is absent")
  }

  // MARK: - Available presets

  func testAvailablePresetsEmpty() throws {
    let provider = GeminiCoachProvider()
    let presets = provider.availablePresets

    XCTAssertTrue(presets.isEmpty, "Gemini provider must have empty availablePresets (dynamic models)")
  }

  // MARK: - API key save and auth state

  func testSaveAPIKeySetsAuthenticated() throws {
    let provider = GeminiCoachProvider()
    try? GeminiCredentialStore.delete()
    provider.signOut()

    XCTAssertFalse(provider.isAuthenticated, "Provider must not be authenticated before saving key")

    try provider.saveAPIKey("test-key")
    XCTAssertTrue(provider.isAuthenticated, "Provider must be authenticated after saving key")

    provider.signOut()
    XCTAssertFalse(provider.isAuthenticated, "Provider must not be authenticated after sign out")
  }

  // MARK: - No model selected error

  func testSendThrowsWhenNoModelSelected() async throws {
    let provider = GeminiCoachProvider()
    try? GeminiCredentialStore.delete()
    try provider.saveAPIKey("test-key")
    provider.selectedModelID = ""

    do {
      _ = try await provider.send(
        messages: [CoachChatMessage(role: .user, text: "Hello")],
        systemPrompt: "You are helpful.",
        preset: .defaultValue
      )
      XCTFail("send() must throw when no model is selected")
    } catch GeminiProviderError.noModelSelected {
    } catch {
      XCTFail("send() must throw noModelSelected, got \(error)")
    }

    provider.signOut()
  }

  // MARK: - Error descriptions

  func testStreamErrorDescription() {
    let error = GeminiProviderError.streamError("Test error message")
    XCTAssertEqual(error.errorDescription, "Test error message")
  }

  func testMissingAPIKeyErrorDescription() {
    let error = GeminiProviderError.missingAPIKey
    XCTAssertNotNil(error.errorDescription)
  }

  // MARK: - Sign out clears error state

  func testSignOutClearsModelFetchError() throws {
    let provider = GeminiCoachProvider()
    provider.signOut()

    XCTAssertNil(provider.modelFetchError, "modelFetchError must be nil after sign out")
    XCTAssertTrue(provider.availableModels.isEmpty, "availableModels must be empty after sign out")
  }
}
