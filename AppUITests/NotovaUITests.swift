import XCTest

@MainActor
final class NotovaUITests: XCTestCase {

    private let timeout: TimeInterval = 15

    override func setUp() {
        continueAfterFailure = false
    }

    /// Launches a fresh, UI-test-seeded app instance.
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-seed"]
        app.launch()
        return app
    }

    // MARK: - Launch & tabs

    func testAppLaunches() {
        let app = launchApp()
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testThreeTabsExist() {
        let app = launchApp()
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: timeout))
        XCTAssertTrue(app.buttons["Record"].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.buttons["Notes"].exists)
        XCTAssertTrue(app.buttons["Settings"].exists)
    }

    func testSwitchingTabsShowsEachScreen() {
        let app = launchApp()
        // Record (default) shows the record control.
        XCTAssertTrue(app.buttons["record.button"].waitForExistence(timeout: timeout))

        // Notes tab.
        app.buttons["Notes"].tap()
        let notesList = app.descendants(matching: .any)["notes.list"]
        let notesEmpty = app.descendants(matching: .any)["notes.empty"]
        XCTAssertTrue(notesList.waitForExistence(timeout: timeout) || notesEmpty.exists,
                      "Notes tab should show either the seeded list or the empty state")

        // Settings tab.
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings.form"].waitForExistence(timeout: timeout))

        // Back to Record.
        app.buttons["Record"].tap()
        XCTAssertTrue(app.buttons["record.button"].waitForExistence(timeout: timeout))
    }

    // MARK: - Record screen

    func testRecordControlIsPresent() {
        let app = launchApp()
        let recordButton = app.buttons["record.button"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: timeout))
        // The DesignSystem RecordButton labels itself by state.
        XCTAssertEqual(recordButton.label, "Start recording")
    }

    func testTappingRecordTogglesState() {
        let app = launchApp()
        let recordButton = app.buttons["record.button"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: timeout))
        XCTAssertEqual(recordButton.label, "Start recording")

        recordButton.tap()
        // The accessibility label flips to "Stop recording" once recording
        // starts (no real mic needed in the simulator).
        let started = NSPredicate(format: "label == %@", "Stop recording")
        expectation(for: started, evaluatedWith: recordButton)
        waitForExpectations(timeout: timeout)

        // Tapping again stops + processes, returning to "Start recording".
        recordButton.tap()
        let stopped = NSPredicate(format: "label == %@", "Start recording")
        expectation(for: stopped, evaluatedWith: recordButton)
        waitForExpectations(timeout: timeout)
    }

    func testImportEntryPointPresents() {
        let app = launchApp()
        let importButton = app.buttons["record.import"]
        XCTAssertTrue(importButton.waitForExistence(timeout: timeout))
        importButton.tap()

        // The system document picker presents. Its sheet contains a Cancel
        // button or a navigation bar; assert one of them appears, then dismiss.
        let cancel = app.buttons["Cancel"]
        let appeared = cancel.waitForExistence(timeout: timeout)
            || app.navigationBars.firstMatch.waitForExistence(timeout: 3)
        XCTAssertTrue(appeared, "file importer should present a picker UI")
        if cancel.exists { cancel.tap() }
    }

    // MARK: - Notes list + detail

    func testNotesListRendersSeededNoteAndDetailOpens() {
        let app = launchApp()
        app.buttons["Notes"].tap()

        // The seeded note's row should appear.
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Sample Standup")).firstMatch
        let staticRow = app.staticTexts["Sample Standup"]
        let rowExists = row.waitForExistence(timeout: timeout) || staticRow.waitForExistence(timeout: timeout)
        XCTAssertTrue(rowExists, "seeded 'Sample Standup' note should render in the list")

        // Open the detail.
        if row.exists { row.tap() } else { staticRow.tap() }
        XCTAssertTrue(app.descendants(matching: .any)["noteDetail.scroll"].waitForExistence(timeout: timeout),
                      "tapping a note should open its detail view")
    }
}
