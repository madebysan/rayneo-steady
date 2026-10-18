import Foundation
import simd
import CRayNeo
import SteadyCore

struct SensorSnapshot {
    var message = "Tracking starts with your screen"
    var connected = false
    var calibrated = false
    var sampleRate: Double = 0
    var samples = 0
    var integratedSamples = 0
    var rejectedTimingSamples = 0
    var lastSampleTime: Double = 0
    var rotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    var rawDPS = SIMD3<Float>.zero
    var predictionState: MotionState?
}

final class SensorService {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.san.rayneosteady.sensors", qos: .userInteractive)
    private let workerGroup = DispatchGroup()
    private var generation = 0
    private var state = SensorSnapshot()
    private var selectedMode: MotionMode = .follow
    private var options = SensorOptions()
    private var centerRequested = false
    private var calibrationRequested = false

    var snapshot: SensorSnapshot { lock.lock(); defer { lock.unlock() }; return state }
    func rotationForDisplay(targetTime: Double?) -> simd_quatf {
        let sample = snapshot
        guard let targetTime, targetTime.isFinite, sample.connected, sample.calibrated,
              let motion = sample.predictionState else { return sample.rotation }
        let age = ProcessInfo.processInfo.systemUptime - sample.lastSampleTime
        guard age >= 0, age < 0.02 else { return sample.rotation }
        return motion.predictedCompensation(seconds: Float(max(0, min(0.008, targetTime - sample.lastSampleTime))))
    }
    func configure(mode: MotionMode, options: SensorOptions) {
        lock.lock(); selectedMode = mode; self.options = options; centerRequested = true; lock.unlock()
    }
    func recenter() { lock.lock(); centerRequested = true; lock.unlock() }
    func calibrate() { lock.lock(); calibrationRequested = true; lock.unlock() }
    private func current(_ token: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }; return token == generation
    }
    private func publish(_ snapshot: SensorSnapshot, token: Int) {
        lock.lock(); defer { lock.unlock() }
        if generation == token { state = snapshot }
    }
    func start() {
        lock.lock()
        generation += 1
        let token = generation
        state = SensorSnapshot(message: "Connecting to motion sensors…")
        centerRequested = false; calibrationRequested = false
        lock.unlock()
        workerGroup.enter()
        queue.async { [self] in
            defer { workerGroup.leave() }
            guard current(token) else { return }
            var context: RAYNEO_Context?
            guard Rayneo_Create(&context) == RAYNEO_OK, let context else {
                publish(SensorSnapshot(message: "Could not initialize sensors. Size controls still work."), token: token)
                return
            }
            defer { Rayneo_Destroy(context) }
            Rayneo_SetTargetVidPid(context, 0x1BBB, 0xAF50)
            let result = Rayneo_Start(context, 0)
            guard result == RAYNEO_OK else {
                publish(SensorSnapshot(message: "No sensor connection. Plug in RayNeo and close other glasses apps."), token: token)
                return
            }
            defer { Rayneo_DisableImu(context); Rayneo_Stop(context) }
            guard Rayneo_EnableImu(context) == RAYNEO_OK else {
                publish(SensorSnapshot(message: "Sensors could not start. Reconnect the glasses and try again."), token: token)
                return
            }
            var motion = MotionState()
            var clock = SampleClock()
            var calibration = BiasCalibration()
            var bias = SIMD3<Float>.zero
            var ready = false
            var status = SensorSnapshot(message: "Rest glasses on a still surface for 2 seconds", connected: true)
            var event = RAYNEO_Event()
            var lastSample = ProcessInfo.processInfo.systemUptime
            var rateStart = lastSample
            var rateCount = 0
            publish(status, token: token)
            while current(token) {
                let rc = Rayneo_PollEvent(context, &event, 20)
                let now = ProcessInfo.processInfo.systemUptime
                if now - lastSample > 2 {
                    status.connected = false
                    status.rotation = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
                    status.message = "Motion data stopped. Reconnect glasses, then Stop and Start."
                    publish(status, token: token)
                    break
                }
                guard rc == RAYNEO_OK else { continue }
                if event.type == RAYNEO_EVENT_DEVICE_DETACHED {
                    status.connected = false
                    status.rotation = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
                    status.message = "Glasses disconnected. Stop and Start after reconnecting."
                    publish(status, token: token)
                    break
                }
                guard event.type == RAYNEO_EVENT_IMU_SAMPLE, event.data.imu.valid != 0 else { continue }
                let imu = event.data.imu
                let dps = SIMD3(imu.gyroDps.0, imu.gyroDps.1, imu.gyroDps.2)
                guard dps.x.isFinite, dps.y.isFinite, dps.z.isFinite else { continue }
                lastSample = now
                lock.lock()
                let mode = selectedMode, sensorOptions = options
                let shouldCenter = centerRequested, shouldCalibrate = calibrationRequested
                centerRequested = false; calibrationRequested = false
                lock.unlock()
                if shouldCalibrate {
                    calibration = BiasCalibration(); ready = false
                    motion = MotionState(); clock = SampleClock()
                }
                motion.mode = mode
                if shouldCenter { motion.recenter() }
                let dt = clock.advance(tick: imu.tick, time: now)
                if !ready {
                    calibration.add(dps: dps, time: now)
                    status.message = "Keep glasses still · \(Int(calibration.progress * 100))%"
                    if let calibrated = calibration.bias {
                        bias = calibrated; ready = true
                        motion.recenter()
                    }
                } else if let dt {
                    motion.ingest(radiansPerSecond: sensorOptions.radians(fromDPS: dps - bias), dt: dt)
                    status.integratedSamples += 1
                } else {
                    status.rejectedTimingSamples += 1
                }
                status.samples += 1; rateCount += 1
                if now - rateStart >= 1 {
                    status.sampleRate = Double(rateCount) / (now - rateStart)
                    rateStart = now; rateCount = 0
                }
                status.lastSampleTime = now
                status.rawDPS = dps
                status.calibrated = ready
                status.rotation = ready ? motion.compensation : simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
                status.predictionState = ready ? motion : nil
                if ready {
                    if mode == .off { status.message = "Size only · stabilization is off" }
                    else if status.integratedSamples == 0 { status.message = "Calibrated · waiting for valid motion timing" }
                    else { status.message = "Tracking ready · \(Int(status.sampleRate.rounded())) samples/s" }
                }
                publish(status, token: token)
            }
        }
    }
    func stop() {
        lock.lock(); generation += 1; state = SensorSnapshot(); lock.unlock()
    }
    func shutDown() {
        stop()
        _ = workerGroup.wait(timeout: .now() + 1.5)
    }
}
