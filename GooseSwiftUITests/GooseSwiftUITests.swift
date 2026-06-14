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

  func testAppLaunchesAndShowsTabBar() {
    app = launchAppForUITesting()

    XCTAssertTrue(
      app.tabBars.firstMatch.waitForExistence(timeout: 10),
      "Tab bar should appear after launch with --ui-testing"
    )
  }

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
}
