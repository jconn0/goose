import XCTest

extension XCTestCase {
  var goosedApp: XCUIApplication {
    XCUIApplication()
  }

  func launchAppForUITesting() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing"]
    app.launch()
    return app
  }

  func launchAppForUITesting(seeded: Bool) -> XCUIApplication {
    let app = XCUIApplication()
    var args = ["--ui-testing"]
    if seeded {
      args.append("--ui-testing-seed-db")
    }
    app.launchArguments = args
    app.launch()
    return app
  }
}
