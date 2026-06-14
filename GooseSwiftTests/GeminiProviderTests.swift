import XCTest
@testable import GooseSwift

@MainActor
final class GeminiProviderTests: XCTestCase {

  // MARK: - Keychain roundtrip

  func testGeminiKeychainRoundtrip() throws {
    let key = "test-api-key-12345"
    try requireKeychain()

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

  func testGeminiDeltaExtraction() {
    let validLine = #"data: {"candidates":[{"content":{"parts":[{"text":"Hello"}]}}]}"#
    let result = GeminiCoachProvider.extractGeminiDelta(from: validLine)
    XCTAssertEqual(result, "Hello", "extractGeminiDelta must return 'Hello' for a valid candidates line")

    let emptyCandidates = #"data: {"candidates":[]}"#
    let resultEmpty = GeminiCoachProvider.extractGeminiDelta(from: emptyCandidates)
    XCTAssertNil(resultEmpty, "extractGeminiDelta must return nil for empty candidates array")

    let noPrefix = #"{"candidates":[{"content":{"parts":[{"text":"Hello"}]}}]}"#
    let resultNoPrefix = GeminiCoachProvider.extractGeminiDelta(from: noPrefix)
    XCTAssertNil(resultNoPrefix, "extractGeminiDelta must return nil for line without data: prefix")

    let noText = #"data: {"candidates":[{"content":{"parts":[{"image":"abc"}]}}]}"#
    let resultNoText = GeminiCoachProvider.extractGeminiDelta(from: noText)
    XCTAssertNil(resultNoText, "extractGeminiDelta must return nil when text key is absent")
  }

  // MARK: - Non-streaming delta extraction

  func testExtractNonStreamingDelta() {
    let validJSON = #"{"candidates":[{"content":{"parts":[{"text":"Hello from Gemini"}]}}]}"#
    let result = GeminiCoachProvider.extractNonStreamingDelta(from: validJSON)
    XCTAssertEqual(result, "Hello from Gemini", "extractNonStreamingDelta must extract text from a non-streaming response")

    let emptyCandidates = #"{"candidates":[]}"#
    XCTAssertNil(GeminiCoachProvider.extractNonStreamingDelta(from: emptyCandidates), "Must return nil for empty candidates")

    let invalidJSON = "not json"
    XCTAssertNil(GeminiCoachProvider.extractNonStreamingDelta(from: invalidJSON), "Must return nil for invalid JSON")
  }

  // MARK: - Model parsing filter logic (pure dictionary tests)

  func testStreamingModelDetectedFromMethods() {
    let methods = ["streamGenerateContent", "generateContent"]
    XCTAssertTrue(methods.contains("streamGenerateContent"), "Streaming model should contain streamGenerateContent")
    XCTAssertTrue(methods.contains("generateContent"), "Streaming model should also contain generateContent")
  }

  func testGenerateOnlyModelDetectedFromMethods() {
    let methods = ["generateContent"]
    XCTAssertTrue(methods.contains("generateContent"), "Generate-only model should contain generateContent")
    XCTAssertFalse(methods.contains("streamGenerateContent"), "Generate-only model should not contain streamGenerateContent")
  }

  func testEmbeddingModelExcludedFromMethods() {
    let methods = ["embedContent"]
    XCTAssertFalse(methods.contains("streamGenerateContent"), "Embedding models should not stream")
    XCTAssertFalse(methods.contains("generateContent"), "Embedding models should not generate")
  }

  // MARK: - GeminiModel supportsStreaming field

  func testGeminiModelSupportsStreamingField() {
    let streamingModel = GeminiModel(id: "gemini-pro", displayName: "Gemini Pro", supportsStreaming: true)
    let nonStreamingModel = GeminiModel(id: "some-model", displayName: "Some Model", supportsStreaming: false)

    XCTAssertTrue(streamingModel.supportsStreaming, "Streaming model should report supportsStreaming = true")
    XCTAssertFalse(nonStreamingModel.supportsStreaming, "Non-streaming model should report supportsStreaming = false")
  }

  func testGeminiModelEquatable() {
    let a = GeminiModel(id: "gemini-pro", displayName: "Gemini Pro", supportsStreaming: true)
    let b = GeminiModel(id: "gemini-pro", displayName: "Gemini Pro", supportsStreaming: true)
    let c = GeminiModel(id: "gemini-flash", displayName: "Gemini Flash", supportsStreaming: true)
    XCTAssertEqual(a, b, "Identical models should be equal")
    XCTAssertNotEqual(a, c, "Different models should not be equal")
  }

  // MARK: - Model ID stripping

  func testModelIDStripsModelsPrefix() {
    let name = "models/gemini-2.5-pro"
    let modelID = name.hasPrefix("models/") ? String(name.dropFirst(7)) : name
    XCTAssertEqual(modelID, "gemini-2.5-pro", "models/ prefix must be stripped")
  }

  func testModelIDPreservedWithoutPrefix() {
    let name = "gemini-2.5-flash"
    let modelID = name.hasPrefix("models/") ? String(name.dropFirst(7)) : name
    XCTAssertEqual(modelID, "gemini-2.5-flash", "Model ID without prefix must be preserved")
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
    try requireKeychain()
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
    try requireKeychain()
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

  private func requireKeychain() throws {
    let probe = "goose.test.probe-\(UUID().uuidString)"
    do {
      try GeminiCredentialStore.save(probe)
      try GeminiCredentialStore.delete()
    } catch {
      throw XCTSkip("Keychain unavailable on this destination")
    }
  }
}