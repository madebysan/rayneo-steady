import XCTest
@testable import SteadyCore

final class ScreenSizeTests: XCTestCase {
    func testOnePointStepsStayWithinUsableRange() {
        var size = ScreenSize(85)
        size.step(-1)
        XCTAssertEqual(size.percent, 84)
        size.step(1)
        XCTAssertEqual(size.percent, 85)
        size.step(200)
        XCTAssertEqual(size.percent, 100)
        size.step(-200)
        XCTAssertEqual(size.percent, 40)
    }
}
