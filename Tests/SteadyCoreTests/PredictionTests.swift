import XCTest
import simd
@testable import SteadyCore

final class PredictionTests: XCTestCase {
    func testConstantTurnPredictsOnlyTheNextEightMilliseconds() {
        var state = MotionState(); state.mode = .pinned
        for _ in 0..<500 { state.ingest(radiansPerSecond: SIMD3(0, 0.5, 0), dt: 0.002) }
        let forward = state.predictedCompensation(seconds: 0.008).act(SIMD3<Float>(0, 0, -1))
        XCTAssertEqual(forward.x, sin(0.504), accuracy: 0.0001)
        XCTAssertEqual(forward.z, -cos(0.504), accuracy: 0.0001)
        let capped = state.predictedCompensation(seconds: 1).act(SIMD3<Float>(0, 0, -1))
        XCTAssertEqual(capped.x, forward.x, accuracy: 0.000001)
    }
    func testFastTurnPredictionIsBoundedToHalfADegree() {
        var state = MotionState(); state.mode = .pinned
        for _ in 0..<100 { state.ingest(radiansPerSecond: SIMD3(0, 10, 0), dt: 0.002) }
        let difference = state.predictedCompensation(seconds: 0.008) * state.compensation.inverse
        XCTAssertEqual(difference.angle, .pi / 360, accuracy: 0.00005)
    }
    func testPredictionCannotChangeThePinnedAnchor() {
        var state = MotionState(); state.mode = .pinned
        state.ingest(radiansPerSecond: SIMD3(0, 1, 0), dt: 0.01)
        let baseline = state.compensation.vector
        for _ in 0..<100 { _ = state.predictedCompensation(seconds: 0.008) }
        XCTAssertEqual(state.compensation.vector, baseline)
        state.recenter()
        XCTAssertEqual(state.predictedCompensation(seconds: 0.008).angle, 0, accuracy: 0.00001)
    }
    func testPredictionSettlesAfterMotionStopsAndOffRemainsOff() {
        var state = MotionState(); state.mode = .pinned
        for _ in 0..<100 { state.ingest(radiansPerSecond: SIMD3(0, 1, 0), dt: 0.002) }
        for _ in 0..<20 { state.ingest(radiansPerSecond: .zero, dt: 0.002) }
        let difference = state.predictedCompensation(seconds: 0.008) * state.compensation.inverse
        XCTAssertLessThan(difference.angle, 0.0001)
        state.mode = .off
        XCTAssertEqual(state.predictedCompensation(seconds: 0.008).angle, 0, accuracy: 0.00001)
    }
}
