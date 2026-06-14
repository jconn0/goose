import XCTest
@testable import GooseSwift

final class CoachKeychainTests: XCTestCase {

  override func setUp() {
    super.setUp()
    try? ClaudeCredentialStore.delete()
    try? CustomEndpointCredentialStore.delete()
  }

  override func tearDown() {
    try? ClaudeCredentialStore.delete()
    try? CustomEndpointCredentialStore.delete()
    super.tearDown()
  }

  func testClaudeKeychainRoundtrip() throws {
    let testKey = "test-key-\(UUID().uuidString)"
    try requireKeychain()
    try ClaudeCredentialStore.save(testKey)
    let loaded = try ClaudeCredentialStore.load()
    XCTAssertEqual(loaded, testKey, "Loaded key must match the saved key")
    try ClaudeCredentialStore.delete()
    let afterDelete = try ClaudeCredentialStore.load()
    XCTAssertNil(afterDelete, "Key must be nil after deletion")
  }

  func testCustomEndpointKeychainRoundtrip() throws {
    let testKey = "custom-test-key-\(UUID().uuidString)"
    try requireKeychain()
    try CustomEndpointCredentialStore.save(testKey)
    let loaded = try CustomEndpointCredentialStore.load()
    XCTAssertEqual(loaded, testKey, "Loaded custom endpoint key must match the saved key")
    try CustomEndpointCredentialStore.delete()
    let afterDelete = try CustomEndpointCredentialStore.load()
    XCTAssertNil(afterDelete, "Custom endpoint key must be nil after deletion")
  }

  private func requireKeychain() throws {
    let probe = "goose.test.probe-\(UUID().uuidString)"
    do {
      try ClaudeCredentialStore.save(probe)
      try ClaudeCredentialStore.delete()
    } catch {
      throw XCTSkip("Keychain unavailable on this destination")
    }
  }
}
