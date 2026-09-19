import AppKit
@preconcurrency import CoreMedia
import OSLog
// These Objective-C APIs lack Sendable annotations in the macOS 15 SDK.
// Our state/output stay on MainActor and all stream mutations are serialized.
@preconcurrency import ScreenCaptureKit

enum CaptureState: Equatable {
    case idle
    case waiting
    case live
    case paused
    case unavailable(String)
}

@MainActor
final class CaptureController: NSObject, WindowCapture {
    var onFrame: ((CMSampleBuffer) -> Void)?
    var onReset: (() -> Void)?
    var onSelection: ((CGSize, String?, Bool) -> Void)?
    var onStateChange: ((CaptureState) -> Void)?

    private(set) var state: CaptureState = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    var sourceApplicationProcessIdentifier: pid_t? {
        guard let application = sourceApplication, !application.isTerminated else { return nil }
        return application.processIdentifier
    }
    var streamForPicker: SCStream? { stream }
    var streamIdentifier: ObjectIdentifier? { stream.map(ObjectIdentifier.init) }
    private(set) var sourceWindowIdentifier: CGWindowID?
    private let logger = Logger(subsystem: "app.ontop.OnTop", category: "Capture")
    private let backgroundColor = CGColor(gray: 0, alpha: 1)
    private var stream: SCStream?
    private var sourceApplication: NSRunningApplication?
    private var sourceTitle: String?
    private var generation = 0
    private var frameGeneration: Int?
    private var operation: Task<Void, Never>?
    private var resizeTask: Task<Void, Never>?
    private var viewport = CGSize(width: 480, height: 300)
    private var backingScale: CGFloat = 2
    private var configuredSize = CGSize.zero
    private var isShuttingDown = false

    func stop() {
        generation += 1
        frameGeneration = nil
        resizeTask?.cancel()
        resizeTask = nil
        let previousStream = stream
        stream = nil
        sourceApplication = nil
        sourceTitle = nil
        sourceWindowIdentifier = nil
        configuredSize = .zero
        state = .idle
        onReset?()
        // Serialize teardown after any in-flight start/update. Closing a panel
        // while startCapture is suspended must not leave an invisible stream.
        if let previousStream {
            enqueue { try? await previousStream.stopCapture() }
        }
    }

    func shutdown() async {
        isShuttingDown = true
        stop()
        await operation?.value
    }

    @discardableResult
    func activateSourceApplication() -> Bool {
        guard state == .live || state == .paused,
              let application = sourceApplication, !application.isTerminated else { return false }
        if application.isHidden { application.unhide() }
        return application.activate(options: [.activateAllWindows])
    }

    func resize(to size: CGSize, scale: CGFloat) {
        viewport = size
        backingScale = scale
        resizeTask?.cancel()
        let expectedGeneration = generation
        resizeTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(150)) }
            catch { return }
            guard let self, !Task.isCancelled else { return }
            enqueue { [weak self] in
                guard let self, generation == expectedGeneration, let stream else { return }
                let size = PreviewSizing.pixelSize(for: viewport, scale: backingScale)
                guard size != configuredSize else { return }
                do {
                    try await stream.updateConfiguration(makeConfiguration())
                    if self.stream === stream, generation == expectedGeneration {
                        configuredSize = size
                    }
                } catch {
                    // Resizing is optional: the existing stream can continue
                    // at its previous resolution if reconfiguration fails.
                    logger.error("Could not resize capture: \(error.localizedDescription)")
                }
            }
        }
    }

    private func enqueue(_ action: @escaping @MainActor () async -> Void) {
        let previous = operation
        operation = Task { @MainActor in
            await previous?.value
            await action()
        }
    }

    func select(_ filter: SCContentFilter) {
        guard !isShuttingDown, filter.style == .window else { return }

        generation += 1
        let selection = generation
        frameGeneration = nil
        resizeTask?.cancel()
        onReset?()
        state = .waiting
        var title: String?
        sourceApplication = nil
        sourceWindowIdentifier = nil
        if #available(macOS 15.2, *) {
            let window = filter.includedWindows.first
            sourceWindowIdentifier = window?.windowID
            title = window?.title ?? window?.owningApplication?.applicationName
            if let processID = window?.owningApplication?.processID {
                sourceApplication = NSRunningApplication(processIdentifier: processID)
            }
        }
        sourceTitle = title
        onSelection?(filter.contentRect.size, title, sourceApplication != nil)

        enqueue { [weak self] in
            guard let self, generation == selection else { return }
            do {
                if let existingStream = stream {
                    // An otherwise static window may send its only complete
                    // frame before the async update call returns.
                    frameGeneration = selection
                    try await existingStream.updateContentFilter(filter)
                    guard generation == selection, stream === existingStream else { return }
                    let size = PreviewSizing.pixelSize(for: viewport, scale: backingScale)
                    try await existingStream.updateConfiguration(makeConfiguration())
                    guard generation == selection, stream === existingStream else { return }
                    configuredSize = size
                    frameGeneration = selection
                } else {
                    let newStream = SCStream(filter: filter, configuration: makeConfiguration(), delegate: self)
                    try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
                    stream = newStream
                    configuredSize = PreviewSizing.pixelSize(for: viewport, scale: backingScale)
                    frameGeneration = selection
                    try await newStream.startCapture()
                }
            } catch {
                guard generation == selection else { return }
                fail(error)
            }
        }
    }

    private func makeConfiguration() -> SCStreamConfiguration {
        let size = PreviewSizing.pixelSize(for: viewport, scale: backingScale)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(size.width)
        configuration.height = Int(size.height)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 15)
        configuration.queueDepth = 3
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.preservesAspectRatio = true
        configuration.scalesToFit = true
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.ignoreGlobalClipSingleWindow = true
        configuration.backgroundColor = backgroundColor
        configuration.streamName = sourceTitle ?? "OnTop"
        return configuration
    }

    private func fail(_ error: Error) {
        logger.error("Capture ended: \(error.localizedDescription)")
        generation += 1
        frameGeneration = nil
        resizeTask?.cancel()
        let previousStream = stream
        stream = nil
        sourceApplication = nil
        let nsError = error as NSError
        let message: String
        if nsError.domain == SCStreamErrorDomain, nsError.code == SCStreamError.Code.userDeclined.rawValue {
            message = NSLocalizedString("Access wasn't granted. Choose a window and allow sharing to try again.", comment: "Permission error")
        } else {
            message = NSLocalizedString("The window was closed or sharing ended. Choose a window to continue.", comment: "Capture ended")
        }
        state = .unavailable(message)
        if let previousStream { enqueue { try? await previousStream.stopCapture() } }
    }

    private func receive(_ sampleBuffer: CMSampleBuffer, from stream: SCStream) {
        guard self.stream === stream, frameGeneration == generation,
              sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: rawStatus) else { return }

        switch status {
        case .complete, .started:
            guard CMSampleBufferDataIsReady(sampleBuffer), CMSampleBufferGetImageBuffer(sampleBuffer) != nil else { return }
            onFrame?(sampleBuffer)
            state = .live
        case .idle:
            // A static document is still live, not an interrupted capture.
            if state == .paused { state = .live }
        case .blank, .suspended:
            state = .paused
        case .stopped:
            fail(NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userStopped.rawValue))
        @unknown default:
            break
        }
    }
}

extension CaptureController: SCStreamDelegate, @preconcurrency SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        let streamID = ObjectIdentifier(stream)
        Task { @MainActor [weak self] in
            guard let self, self.stream.map(ObjectIdentifier.init) == streamID else { return }
            fail(error)
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        // This output was registered on .main; no buffer or UI crosses queues.
        receive(sampleBuffer, from: stream)
    }
}
