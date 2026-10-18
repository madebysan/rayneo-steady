import AppKit
import ScreenCaptureKit
import CoreMedia

struct CaptureStatus {
    var frames = 0
    var width = 0
    var height = 0
}

final class DesktopCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let stateLock = NSLock()
    private var cancelled = false
    private var captureStatus = CaptureStatus()
    private let captureQueue = DispatchQueue(label: "com.san.rayneosteady.capture", qos: .userInteractive)
    var onFrame: ((CVPixelBuffer) -> Void)?
    var onError: ((Error) -> Void)?
    var status: CaptureStatus { stateLock.withLock { captureStatus } }

    func start(displayID: CGDirectDisplayID) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        if stateLock.withLock({ cancelled }) { throw CancellationError() }
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw NSError(domain: "Steady", code: 1, userInfo: [NSLocalizedDescriptionKey: "The source screen is no longer connected."])
        }
        let ownApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        let ratio = Double(display.width) / Double(display.height)
        configuration.width = min(2560, display.width * 2)
        configuration.height = Int(Double(configuration.width) / ratio)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 3
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = true
        configuration.capturesAudio = false
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
        let canStart = stateLock.withLock {
            if cancelled { return false }
            self.stream = stream
            return true
        }
        guard canStart else { throw CancellationError() }
        try await stream.startCapture()
        if stateLock.withLock({ cancelled }) {
            try? await stream.stopCapture()
            throw CancellationError()
        }
    }
    func stop() async {
        let stream = stateLock.withLock {
            cancelled = true
            let current = self.stream
            self.stream = nil
            return current
        }
        guard let stream else { return }
        try? await stream.stopCapture()
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        if !stateLock.withLock({ cancelled }) { onError?(error) }
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let buffer = sampleBuffer.imageBuffer else { return }
        let deliver = stateLock.withLock {
            if cancelled { return false }
            captureStatus.frames += 1
            captureStatus.width = CVPixelBufferGetWidth(buffer)
            captureStatus.height = CVPixelBufferGetHeight(buffer)
            return true
        }
        guard deliver else { return }
        onFrame?(buffer)
    }
}
