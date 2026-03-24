import XCTest
@testable import Whippet

final class WhippetTests: XCTestCase {

    func testAppDelegateExists() throws {
        // Verify the AppDelegate class can be instantiated
        let delegate = AppDelegate()
        XCTAssertNotNil(delegate)
    }
}
