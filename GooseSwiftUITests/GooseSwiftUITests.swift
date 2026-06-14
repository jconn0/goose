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

  // MARK: - Gemini AI Studio provider (known bug: Config section doesn't re-render in sheet)

  func testGeminiProviderRowSelectable() {
    app = launchAppForUITesting()

    navigateToCoachSettings()

    // Verify Gemini row exists and can be tapped (reported as "active")
    let geminiPred = NSPredicate(format: "label CONTAINS %@", "Gemini")
    let geminiRow = app.buttons.matching(geminiPred).firstMatch
    XCTAssertTrue(geminiRow.waitForExistence(timeout: 5), "Gemini provider row should exist")
    geminiRow.tap()
    sleep(3)

    let activePred = NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Gemini", "active")
    let activeGeminiRow = app.buttons.matching(activePred).firstMatch
    XCTAssertTrue(activeGeminiRow.waitForExistence(timeout: 5), "Gemini row should show active after selection")
  }

  func testGeminiConfigDoesNotRenderAfterSwitch() {
    // Documented bug: After selecting Gemini in the settings sheet, the Configuration
    // section (API key field, save button, AI Studio link) does not render.
    // This is a SwiftUI .sheet() + @Bindable rendering issue.
    // The settings sheet opens and the provider row is selectable, but the config
    // section never updates to reflect the Gemini provider.
    XCTExpectFailure("Known: Gemini config doesn't re-render in sheet after provider switch")

    app = launchAppForUITesting()
    navigateToCoachSettings()

    let geminiRow = app.buttons["coach_provider_gemini"]
    if geminiRow.waitForExistence(timeout: 5) {
      geminiRow.tap()
      sleep(3)
    }

    let apiKeyField = app.secureTextFields["gemini_api_key_field"]
    XCTAssertTrue(apiKeyField.waitForExistence(timeout: 8), "Gemini API key field should appear")
  }

  // MARK: - Coach overview

  func testCoachTabShowsChatStatusCard() {
    app = launchAppForUITesting()

    navigateToCoachTab()

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

  private func navigateToCoachSettings() {
    navigateToCoachTab()

    let signInButton = app.buttons["Sign In"]
    if signInButton.waitForExistence(timeout: 3) {
      signInButton.tap()
      sleep(2)
      if waitForCoachSettingsSheet(timeout: 3) {
        return
      }
    }

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
