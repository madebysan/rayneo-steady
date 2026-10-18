import Foundation

struct RenderTimingSnapshot {
    var fps: Double = 0
    var meanLatencyMS: Double = 0
    var p95LatencyMS: Double = 0
    var p95IntervalMS: Double = 0
}

/// Bounded local measurements from Metal's actual presentation callbacks.
final class RenderTiming {
    private let lock = NSLock()
    private var previousPresentation: Double?
    private var intervals: [Double] = []
    private var latencies: [Double] = []
    func reset() {
        lock.lock(); defer { lock.unlock() }
        previousPresentation = nil; intervals.removeAll(keepingCapacity: true); latencies.removeAll(keepingCapacity: true)
    }
    func record(sampledAt: Double, presentedAt: Double) {
        let latency = presentedAt - sampledAt
        guard latency >= 0, latency < 0.2 else { return }
        lock.lock(); defer { lock.unlock() }
        if let previousPresentation {
            let interval = presentedAt - previousPresentation
            if interval > 0, interval < 0.2 { intervals.append(interval) }
        }
        previousPresentation = presentedAt
        latencies.append(latency)
        if intervals.count > 180 { intervals.removeFirst(intervals.count - 180) }
        if latencies.count > 180 { latencies.removeFirst(latencies.count - 180) }
    }
    var snapshot: RenderTimingSnapshot {
        lock.lock(); let durations = intervals, delays = latencies; lock.unlock()
        func mean(_ values: [Double]) -> Double { values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count) }
        func percentile(_ values: [Double]) -> Double {
            guard !values.isEmpty else { return 0 }
            let sorted = values.sorted(); return sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        }
        let frameDuration = mean(durations)
        return RenderTimingSnapshot(fps: frameDuration > 0 ? 1 / frameDuration : 0,
                                    meanLatencyMS: mean(delays) * 1000,
                                    p95LatencyMS: percentile(delays) * 1000,
                                    p95IntervalMS: percentile(durations) * 1000)
    }
}
