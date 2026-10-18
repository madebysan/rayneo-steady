import Foundation
import simd

public enum MotionMode: Int {
    case off, pinned, follow
}

/// Returns a rotation which places a world-oriented screen in the current head frame.
/// Capture and rendering run independently; the renderer can reuse an unchanged desktop frame.
public struct MotionState {
    public private(set) var head = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
    private var anchor = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    private var predictionRate = SIMD3<Float>.zero
    public var mode: MotionMode = .follow
    public var followTime: Float = 0.8

    public init() {}
    public mutating func recenter() { anchor = head; predictionRate = .zero }
    public mutating func ingest(radiansPerSecond rate: SIMD3<Float>, dt: Float) {
        guard dt > 0, dt <= 0.05, rate.x.isFinite, rate.y.isFinite, rate.z.isFinite else { return }
        let speed = simd_length(rate)
        guard speed < 35 else { return }
        // Filter velocity only for the short prediction. Never damp the integrated pose:
        // real small head rotations still need an equal and opposite screen correction.
        let alpha = 1 - exp(-2 * Float.pi * 40 * dt)
        predictionRate += (rate - predictionRate) * alpha
        if speed > 0.000001 {
            head = simd_normalize(head * simd_quatf(angle: speed * dt, axis: rate / speed))
        }
        if mode == .off { anchor = head }
        if mode == .follow {
            let alpha = 1 - exp(-dt / max(0.05, followTime))
            anchor = simd_normalize(simd_slerp(anchor, head, alpha))
        }
    }
    public var compensation: simd_quatf {
        mode == .off ? simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)) : simd_normalize(head.inverse * anchor)
    }
    public func predictedCompensation(seconds: Float) -> simd_quatf {
        guard mode != .off, seconds.isFinite, seconds > 0 else { return compensation }
        let speed = simd_length(predictionRate)
        guard speed > 0.000001 else { return compensation }
        // Prediction is temporary: it never changes the integrated head pose or saved anchor.
        let horizon = min(seconds, 0.008)
        let angle = min(speed * horizon, .pi / 360)
        let futureHead = simd_normalize(head * simd_quatf(angle: angle, axis: predictionRate / speed))
        let futureAnchor = mode == .follow
            ? simd_slerp(anchor, futureHead, 1 - exp(-horizon / max(0.05, followTime)))
            : anchor
        return simd_normalize(futureHead.inverse * futureAnchor)
    }
}

/// Measured on Air 4 Pro: 50,000 device ticks in 5.001 wall-clock seconds (100 µs/tick).
/// Wall-clock gaps never become large rotations.
public struct SampleClock {
    private var lastTick: UInt32?
    private var lastTime: Double?
    public init() {}
    public mutating func advance(tick: UInt32, time: Double) -> Float? {
        defer { lastTick = tick; lastTime = time }
        guard let oldTick = lastTick, let oldTime = lastTime else { return nil }
        let wall = time - oldTime
        guard wall >= 0, wall < 0.25 else { return nil }
        let elapsed = Double(tick &- oldTick) / 10_000
        // Duplicate, out-of-order, or implausible ticks are dropped, not integrated twice.
        guard elapsed > 0, elapsed <= 0.05 else { return nil }
        return Float(elapsed)
    }
}

/// Explicit, stationary calibration; no bias learning while the wearer is moving.
public struct BiasCalibration {
    private var start: Double?
    private var mean = SIMD3<Float>.zero
    private var m2 = SIMD3<Float>.zero
    private var count = 0
    public private(set) var progress: Double = 0
    public private(set) var bias: SIMD3<Float>?
    public init() {}
    public mutating func add(dps: SIMD3<Float>, time: Double) {
        guard bias == nil else { return }
        guard dps.x.isFinite, dps.y.isFinite, dps.z.isFinite, simd_length(dps) < 3 else {
            self = BiasCalibration(); return
        }
        if start == nil { start = time }
        count += 1
        let delta = dps - mean
        mean += delta / Float(count)
        m2 += delta * (dps - mean)
        if count > 20, (m2 / Float(count - 1)).max() > 0.04 {
            self = BiasCalibration(); return
        }
        progress = min(1, (time - (start ?? time)) / 2)
        if progress >= 1, count >= 50 { bias = mean }
    }
}

public struct SensorOptions {
    public var tiltedSensor = false
    public var reverseYaw = false
    public var reversePitch = false
    public var trackRoll = true
    public init() {}
    public func radians(fromDPS v: SIMD3<Float>) -> SIMD3<Float> {
        let yaw = tiltedSensor ? (v.y + v.z) * Float(0.5).squareRoot() : v.y
        let roll = tiltedSensor ? (v.z - v.y) * Float(0.5).squareRoot() : v.z
        return SIMD3(v.x * (reversePitch ? -1 : 1), yaw * (reverseYaw ? -1 : 1), trackRoll ? roll : 0) * (.pi / 180)
    }
}
