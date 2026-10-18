import XCTest
import simd
@testable import SteadyCore

final class MotionTests: XCTestCase {
    func testAir4ProMeasuredTickRateProducesRealElapsedTime() {
        // Live Air 4 Pro stream: 500 samples/s and a median tick delta of 20.
        var clock = SampleClock()
        XCTAssertNil(clock.advance(tick: 1000, time: 0))
        XCTAssertEqual(clock.advance(tick: 1020, time: 0.002)!, 0.002, accuracy: 0.00001)
    }

    func testMeasuredClockAndMotionTogetherDoNotMultiplyRotationByTen() {
        var clock = SampleClock()
        var motion = MotionState(); motion.mode = .pinned
        _ = clock.advance(tick: 0, time: 0)
        for i in 1...500 {
            if let dt = clock.advance(tick: UInt32(i * 20), time: Double(i) * 0.002) {
                motion.ingest(radiansPerSecond: SIMD3(0, 1, 0), dt: dt)
            }
        }
        let forward = motion.compensation.act(SIMD3<Float>(0, 0, -1))
        XCTAssertEqual(forward.x, sin(1), accuracy: 0.001)
        XCTAssertEqual(forward.z, -cos(1), accuracy: 0.001)
    }
    func testPinnedCompensatesRotationAndRecenterReturnsToIdentity() {
        var motion = MotionState()
        motion.mode = .pinned
        for _ in 0..<100 { motion.ingest(radiansPerSecond: SIMD3(0, .pi / 2, 0), dt: 0.01) }
        let forward = motion.compensation.act(SIMD3<Float>(0, 0, -1))
        XCTAssertEqual(forward.x, 1, accuracy: 0.001)
        XCTAssertEqual(forward.z, 0, accuracy: 0.001)
        motion.recenter()
        XCTAssertEqual(motion.compensation.angle, 0, accuracy: 0.001)
    }
    func testFollowCompensatesFastMotionThenSettles() {
        var motion = MotionState()
        motion.ingest(radiansPerSecond: SIMD3(0, 1, 0), dt: 0.01)
        XCTAssertGreaterThan(motion.compensation.angle, 0.009)
        for _ in 0..<800 { motion.ingest(radiansPerSecond: .zero, dt: 0.01) }
        XCTAssertLessThan(motion.compensation.angle, 0.001)
    }
    func testInvalidSamplesAndLongGapsCannotRotateScreen() {
        var motion = MotionState()
        motion.mode = .pinned
        motion.ingest(radiansPerSecond: SIMD3(0, 1, 0), dt: 5)
        motion.ingest(radiansPerSecond: SIMD3(.nan, 0, 0), dt: 0.01)
        XCTAssertEqual(motion.compensation.angle, 0, accuracy: 0.001)
    }
    func testClockHandlesWrapAndDropsDuplicateAndSleepGap() {
        var clock = SampleClock()
        XCTAssertNil(clock.advance(tick: UInt32.max - 19, time: 0))
        XCTAssertEqual(clock.advance(tick: 0, time: 0.002)!, 0.002, accuracy: 0.00001)
        XCTAssertNil(clock.advance(tick: 0, time: 0.003))
        XCTAssertNil(clock.advance(tick: 20, time: 10))
        XCTAssertEqual(clock.advance(tick: 40, time: 10.002)!, 0.002, accuracy: 0.00001)
    }
    func testStationaryBiasAndMovementReset() {
        var calibration = BiasCalibration()
        for i in 0..<250 { calibration.add(dps: SIMD3(0.2, -0.1, 0.05), time: Double(i) * 0.01) }
        XCTAssertNotNil(calibration.bias)
        XCTAssertEqual(calibration.bias!.x, 0.2, accuracy: 0.001)
        var moving = BiasCalibration()
        for i in 0..<250 { moving.add(dps: SIMD3(0, 30, 0), time: Double(i) * 0.01) }
        XCTAssertNil(moving.bias)
        XCTAssertEqual(moving.progress, 0)
    }
    func testOffDoesNotMoveOutput() {
        var motion = MotionState(); motion.mode = .off
        for _ in 0..<100 { motion.ingest(radiansPerSecond: SIMD3(1, 2, 0), dt: 0.01) }
        XCTAssertEqual(motion.compensation.angle, 0, accuracy: 0.001)
    }
}
