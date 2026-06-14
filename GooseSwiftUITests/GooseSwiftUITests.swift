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
    sleep(1)

    let developerText = app.staticTexts["Developer"]
    XCTAssertTrue(
      developerText.waitForExistence(timeout: 5),
      "Developer row should appear in More tab"
    )
  }

  // MARK: - Coach settings sheet

  func testCoachSettingsSheetOpens() {
    app = launchAppForUITesting()

    let tabBar = app.tabBars.firstMatch
    XCTAssertTrue(tabBar.waitForExistence(timeout: 10))

    tabBar.buttons["Coach"].tap()
    sleep(1)

    let settingsButton = app.buttons["Coach settings"]
    XCTAssertTrue(settingsButton.waitForExistence(timeout: 5), "Coach settings gear should be visible")
    settingsButton.tap()

    let settingsSheet = app.otherElements["coach_settings_sheet"]
    XCTAssertTrue(settingsSheet.waitForExistence(timeout: 5), "Coach settings sheet should present")
  }

  // MARK: - Gemini AI Studio provider selection

  func testSelectGeminiProviderShowsApiKeyConfig() {
    app = launchAppForUITesting()

    navigateToCoachSettings()

    let geminiRow = app.buttons["coach_provider_gemini"]
    XCTAssertTrue(geminiRow.waitForExistence(timeout: 5), "Gemini provider row should exist")
    geminiRow.tap()
    sleep(1)

    let geminiConfig = app.otherElements["gemini_config_view"]
    XCTAssertTrue(geminiConfig.waitForExistence(timeout: 5), "Gemini config view should appear after selection")

    let apiKeyField = app.secureTextFields["gemini_api_key_field"]
    XCTAssertTrue(apiKeyField.exists, "Gemini API key field should be shown")

    let aiStudioLink = app.links["gemini_ai_studio_link"]
    XCTAssertTrue(aiStudioLink.exists, "Google AI Studio link should be shown")
  }

  func testGeminiApiKeySaveFlow() {
    app = launchAppForUITesting()

    navigateToCoachSettings()

    let geminiRow = app.buttons["coach_provider_gemini"]
    XCTAssertTrue(geminiRow.waitForExistence(timeout: 5))
    geminiRow.tap()
    sleep(1)

    let apiKeyField = app.secureTextFields["gemini_api_key_field"]
    XCTAssertTrue(apiKeyField.waitForExistence(timeout: 5), "API key field should appear")
    apiKeyField.tap()
    apiKeyField.typeText("test-api-key-abc123\n")

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

    navigateToCoachSettings()

    let geminiRow = app.buttons["coach_provider_gemini"]
    XCTAssertTrue(geminiRow.waitForExistence(timeout: 5))
    geminiRow.tap()
    sleep(1)

    let apiKeyField = app.secureTextFields["gemini_api_key_field"]
    XCTAssertTrue(apiKeyField.waitForExistence(timeout: 5))
    apiKeyField.tap()
    apiKeyField.typeText("test-api-key-abc123\n")

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

      let dismissButton = app.alerts.buttons["Cancel"]
      if dismissButton.waitForExistence(timeout: 3) {
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

    let tabBar = app.tabBars.firstMatch
    XCTAssertTrue(tabBar.waitForExistence(timeout: 10))

    tabBar.buttons["Coach"].tap()
    sleep(2)

    let startHere = app.staticTexts["Start Here"]
    XCTAssertTrue(startHere.waitForExistence(timeout: 5), "Coach should show 'Start Here' heading")

    let pred = NSPredicate(format: "label CONTAINS %@", "Find blockers")
    let blockersButton = app.buttons.matching(pred).firstMatch
    XCTAssertTrue(blockersButton.waitForExistence(timeout: 5), "Coach suggestion 'Find blockers' button should be visible")
  }

  // MARK: - Helpers

  private func navigateToCoachSettings() {
    let tabBar = app.tabBars.firstMatch
    XCTAssertTrue(tabBar.waitForExistence(timeout: 10))

    tabBar.buttons["Coach"].tap()
    sleep(1)

    let settingsButton = app.buttons["Coach settings"]
    XCTAssertTrue(settingsButton.waitForExistence(timeout: 5), "Coach settings gear should be visible")
    settingsButton.tap()

    let settingsSheet = app.otherElements["coach_settings_sheet"]
    XCTAssertTrue(settingsSheet.waitForExistence(timeout: 5), "Coach settings sheet should present")
  }
}
