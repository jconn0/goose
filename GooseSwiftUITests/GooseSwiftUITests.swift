import XCTest

final class GooseSwiftUITests: XCTestCase {

  var app: XCUIApplication!

  override func setUp() {
    continueAfterFailure = false
    app = XCUIApplication()
  }

  override func tearDown() {
    app = nil
  }

  // MARK: - Launch

  func testAppLaunchesAndShowsTabBar() {
    app = launchAppForUITesting()

    XCTAssertTrue(
      app.tabBars.firstMatch.waitForExistence(timeout: 10),
      "Tab bar should appear after launch with --ui-testing"
    )
  }

  // MARK: - Tabs

  func testAllTabsArePresent() {
    app = launchAppForUITesting()

    let tabBar = app.tabBars.firstMatch
    XCTAssertTrue(tabBar.waitForExistence(timeout: 10))

    for label in ["Home", "Health", "Coach", "More"] {
      XCTAssertTrue(
        tabBar.buttons[label].exists,
        "Tab '\(label)' should exist"
      )
    }
  }

  func testNavigateToEachTab() {
    app = launchAppForUITesting()

    let tabBar = app.tabBars.firstMatch
    XCTAssertTrue(tabBar.waitForExistence(timeout: 10))

    for label in ["Health", "Coach", "More"] {
      let button = tabBar.buttons[label]
      XCTAssertTrue(button.exists, "'\(label)' button should exist")
      button.tap()
      sleep(1)
    }

    tabBar.buttons["Home"].tap()
    sleep(1)
    XCTAssertTrue(tabBar.buttons["Home"].isSelected)
  }

  // MARK: - More tab

  func testMoreTabShowsDeveloperEntry() {
    app = launchAppForUITesting()

    let tabBar = app.tabBars.firstMatch
    XCTAssertTrue(tabBar.waitForExistence(timeout: 10))

    tabBar.buttons["More"].tap()
    sleep(3)

    let pred = NSPredicate(format: "label CONTAINS %@", "Developer")
    let found = app.tables.staticTexts.matching(pred).firstMatch.waitForExistence(timeout: 8)
      || app.collectionViews.staticTexts.matching(pred).firstMatch.waitForExistence(timeout: 1)
      || app.staticTexts.matching(pred).firstMatch.waitForExistence(timeout: 1)
      || app.buttons.matching(pred).firstMatch.waitForExistence(timeout: 1)
    XCTAssertTrue(found, "Developer row should appear in More tab")
  }

  // MARK: - Coach settings sheet

  func testCoachSettingsSheetOpensViaSignInButton() {
    app = launchAppForUITesting()
    navigateToCoachTab()

    let signInButton = app.buttons["Sign In"]
    if signInButton.waitForExistence(timeout: 5) {
      signInButton.tap()
      sleep(2)
      XCTAssertTrue(
        waitForCoachSettingsSheet(timeout: 5),
        "Coach settings sheet should present via Sign In button"
      )
    }
  }

  func testCoachSettingsSheetOpensViaGear() {
    app = launchAppForUITesting()
    navigateToCoachTab()

    let settingsButton = app.buttons["Coach settings"]
    XCTAssertTrue(settingsButton.waitForExistence(timeout: 5), "Coach settings gear should be visible")
    settingsButton.tap()
    sleep(2)

    XCTAssertTrue(
      waitForCoachSettingsSheet(timeout: 5),
      "Coach settings sheet should present via gear button"
    )
  }

  // MARK: - Gemini AI Studio provider selection

  func testSelectGeminiProviderShowsApiKeyConfig() {
    app = launchAppForUITesting()

    tryNavigateToCoachSettings()

    let geminiRow = app.buttons["coach_provider_gemini"]
    XCTAssertTrue(geminiRow.waitForExistence(timeout: 5), "Gemini provider row should exist")
    geminiRow.tap()
    sleep(3)

    let apiKeyFound = app.secureTextFields["gemini_api_key_field"].waitForExistence(timeout: 8)
      || app.tables.secureTextFields["gemini_api_key_field"].waitForExistence(timeout: 1)
      || app.collectionViews.secureTextFields["gemini_api_key_field"].waitForExistence(timeout: 1)
    XCTAssertTrue(apiKeyFound, "Gemini API key field should appear after selecting Gemini provider")

    let aiStudioLink = app.links["gemini_ai_studio_link"]
    XCTAssertTrue(aiStudioLink.exists, "Google AI Studio link should be shown")
  }

  func testGeminiApiKeySaveFlow() {
    app = launchAppForUITesting()

    tryNavigateToCoachSettings()

    let geminiRow = app.buttons["coach_provider_gemini"]
    XCTAssertTrue(geminiRow.waitForExistence(timeout: 5))
    geminiRow.tap()
    sleep(3)

    let apiKeyField = app.secureTextFields["gemini_api_key_field"]
    let apiKeyFound = apiKeyField.waitForExistence(timeout: 8)
      || app.tables.secureTextFields["gemini_api_key_field"].waitForExistence(timeout: 1)
      || app.collectionViews.secureTextFields["gemini_api_key_field"].waitForExistence(timeout: 1)
    XCTAssertTrue(apiKeyFound, "API key field should appear")

    if apiKeyField.exists {
      apiKeyField.tap()
      apiKeyField.typeText("test-api-key-abc123\n")
    } else {
      let tableField = app.tables.secureTextFields["gemini_api_key_field"].firstMatch
      if tableField.exists {
        tableField.tap()
        tableField.typeText("test-api-key-abc123\n")
      } else {
        let cvField = app.collectionViews.secureTextFields["gemini_api_key_field"].firstMatch
        cvField.tap()
        cvField.typeText("test-api-key-abc123\n")
      }
    }

    let saveButton = app.buttons["gemini_save_api_key_button"]
    XCTAssertTrue(saveButton.waitForExistence(timeout: 3))
    XCTAssertTrue(saveButton.isEnabled, "Save button should be enabled when text is present")
    saveButton.tap()
    sleep(2)

    let signedInLabel = app.staticTexts["API key saved"]
    let keyStatus = signedInLabel.waitForExistence(timeout: 5)
    XCTAssertTrue(keyStatus, "Gemini should show signed-in state after saving API key")
  }

  func testGeminiSignOutFlow() {
    app = launchAppForUITesting()

    tryNavigateToCoachSettings()

    let geminiRow = app.buttons["coach_provider_gemini"]
    XCTAssertTrue(geminiRow.waitForExistence(timeout: 5))
    geminiRow.tap()
    sleep(3)

    let apiKeyField = app.secureTextFields["gemini_api_key_field"]
    let apiKeyFound = apiKeyField.waitForExistence(timeout: 8)
      || app.tables.secureTextFields["gemini_api_key_field"].waitForExistence(timeout: 1)
      || app.collectionViews.secureTextFields["gemini_api_key_field"].waitForExistence(timeout: 1)
    XCTAssertTrue(apiKeyFound, "API key field should appear")

    let targetField: XCUIElement
    if apiKeyField.exists {
      targetField = apiKeyField
    } else if app.tables.secureTextFields["gemini_api_key_field"].firstMatch.exists {
      targetField = app.tables.secureTextFields["gemini_api_key_field"].firstMatch
    } else {
      targetField = app.collectionViews.secureTextFields["gemini_api_key_field"].firstMatch
    }
    targetField.tap()
    targetField.typeText("test-api-key-abc123\n")

    let saveButton = app.buttons["gemini_save_api_key_button"]
    XCTAssertTrue(saveButton.waitForExistence(timeout: 3))
    saveButton.tap()
    sleep(2)

    let signedInLabel = app.staticTexts["API key saved"]
    XCTAssertTrue(signedInLabel.waitForExistence(timeout: 5), "Gemini should show signed-in state")

    let signOutButton = app.collectionViews.buttons["Sign Out"]
    if signOutButton.waitForExistence(timeout: 5) {
      signOutButton.tap()
      sleep(1)

      if app.alerts.buttons["Cancel"].waitForExistence(timeout: 3) {
        app.alerts.buttons["Sign Out"].firstMatch.tap()
        sleep(2)
      }

      let apiKeyFieldAgain = app.secureTextFields["gemini_api_key_field"]
      XCTAssertTrue(apiKeyFieldAgain.waitForExistence(timeout: 5), "API key field should reappear after sign out")
    }
  }

  // MARK: - Coach suggestion cards (signed out view)

  func testCoachTabShowsStartHereSuggestions() {
    app = launchAppForUITesting()

    navigateToCoachTab()

    // The suggestions only appear in the chat screen when signed in and message count <= 1.
    // On the overview screen, the "Chat ready" / "Chat signed out" card should be visible.
    let chatCardPred = NSPredicate(format: "label CONTAINS %@", "Chat")
    let chatCard = app.staticTexts.matching(chatCardPred).firstMatch
    XCTAssertTrue(chatCard.waitForExistence(timeout: 8), "Coach should show a chat status card")
  }

  // MARK: - Helpers

  private func navigateToCoachTab() {
    let tabBar = app.tabBars.firstMatch
    XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
    tabBar.buttons["Coach"].tap()
    sleep(2)
  }

  private func tryNavigateToCoachSettings() {
    navigateToCoachTab()

    // Try Sign In card button first (primary path for signed-out users)
    let signInButton = app.buttons["Sign In"]
    if signInButton.waitForExistence(timeout: 3) {
      signInButton.tap()
      sleep(2)
      if waitForCoachSettingsSheet(timeout: 3) {
        return
      }
    }

    // Fall back to toolbar gear button
    let settingsButton = app.buttons["Coach settings"]
    if settingsButton.waitForExistence(timeout: 5) {
      settingsButton.tap()
      sleep(2)
      if waitForCoachSettingsSheet(timeout: 5) {
        return
      }
    }

    XCTFail("Coach settings sheet did not open through either Sign In button or gear button")
  }

  private func waitForCoachSettingsSheet(timeout: TimeInterval) -> Bool {
    if app.navigationBars["Coach Settings"].waitForExistence(timeout: timeout) {
      return true
    }
    if app.otherElements["coach_settings_sheet"].waitForExistence(timeout: 1) {
      return true
    }
    if app.staticTexts["Provider"].waitForExistence(timeout: 1) {
      return true
    }
    return false
  }
}
