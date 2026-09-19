import AppKit
import AVFoundation
import CoreImage
import ScreenCaptureKit

enum FrameContent {
    static func pixelRect(in sample: CMSampleBuffer) -> CGRect? {
        guard let buffer = CMSampleBufferGetImageBuffer(sample) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        let info = (CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
            as? [[SCStreamFrameInfo: Any]])?.first
        guard let value = info?[.contentRect] else { return bounds }
        guard let dictionary = value as? [String: Any],
              let rect = CGRect(dictionaryRepresentation: dictionary as CFDictionary) else { return nil }
        let scale = (info?[.scaleFactor] as? NSNumber)?.doubleValue ?? 1
        guard scale.isFinite, scale > 0,
              [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite),
              rect.width > 0, rect.height > 0 else { return nil }
        // contentRect is in surface points. contentScale has ALREADY been applied
        // by SCK; using it again would shrink the image twice.
        let pixels = CGRect(x: rect.minX * scale, y: rect.minY * scale,
                            width: rect.width * scale, height: rect.height * scale).intersection(bounds)
        guard !pixels.isNull, pixels.width >= 1, pixels.height >= 1 else { return nil }
        return CGRect(x: ceil(pixels.minX), y: ceil(pixels.minY),
                      width: floor(pixels.maxX) - ceil(pixels.minX),
                      height: floor(pixels.maxY) - ceil(pixels.minY))
    }
}

/// Only padded frames take the GPU crop path. Ordinary frames stay zero-copy.
/// The bounded pool avoids allocating an unbounded queue while rendering stalls.
@MainActor
final class FrameCropper {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var pool: CVPixelBufferPool?
    private var poolSize = CGSize.zero

    func prepare(_ sample: CMSampleBuffer) -> CMSampleBuffer? {
        guard let buffer = CMSampleBufferGetImageBuffer(sample),
              let rect = FrameContent.pixelRect(in: sample), rect.width >= 1, rect.height >= 1 else { return nil }
        let full = CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        if rect == full { return sample }
        if pool == nil || poolSize != rect.size {
            let attributes: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: Int(rect.width), kCVPixelBufferHeightKey: Int(rect.height),
                kCVPixelBufferIOSurfacePropertiesKey: [:], kCVPixelBufferMetalCompatibilityKey: true
            ]
            pool = nil
            guard CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool) == kCVReturnSuccess else { return nil }
            poolSize = rect.size
        }
        guard let pool else { return nil }
        var output: CVPixelBuffer?
        let limits = [kCVPixelBufferPoolAllocationThresholdKey: 6] as CFDictionary
        guard CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil, pool, limits, &output) == kCVReturnSuccess,
              let output else { return nil }
        let image = CIImage(cvPixelBuffer: buffer)
        // IOSurface uses top-left coordinates, Core Image uses bottom-left.
        let crop = CGRect(x: rect.minX, y: full.height - rect.maxY, width: rect.width, height: rect.height)
        let cropped = image.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        context.render(cropped, to: output, bounds: CGRect(origin: .zero, size: rect.size),
                       colorSpace: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!)
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: output,
                                                           formatDescriptionOut: &format) == noErr,
              let format else { return nil }
        var timing = CMSampleTimingInfo()
        guard CMSampleBufferGetSampleTimingInfo(sample, at: 0, timingInfoOut: &timing) == noErr else { return nil }
        var result: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: output,
                                                       formatDescription: format, sampleTiming: &timing,
                                                       sampleBufferOut: &result) == noErr else { return nil }
        return result
    }

    func reset() { pool = nil; poolSize = .zero }
}

@MainActor
final class VideoView: NSView {
    let displayLayer = AVSampleBufferDisplayLayer()
    var onContentSizeChange: ((CGSize) -> Void)?
    private let cropper = FrameCropper()
    private var pendingFrame: CMSampleBuffer?
    private var isWaitingForRenderer = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = CGColor(gray: 0, alpha: 0)
        layer?.masksToBounds = true
        layer?.cornerRadius = 8
        displayLayer.videoGravity = .resizeAspect
        layer?.addSublayer(displayLayer)
        setAccessibilityLabel(NSLocalizedString("Live preview. Clicks and scrolling pass through to the window underneath.", comment: "Preview accessibility"))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var mouseDownCanMoveWindow: Bool { false }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        CATransaction.commit()
    }

    func display(_ sampleBuffer: CMSampleBuffer) {
        guard let frame = cropper.prepare(sampleBuffer), let buffer = CMSampleBufferGetImageBuffer(frame),
              let attachments = CMSampleBufferGetSampleAttachmentsArray(frame, createIfNecessary: true)
                as? [NSMutableDictionary], let sample = attachments.first else { return }
        sample[kCMSampleAttachmentKey_DisplayImmediately] = true
        onContentSizeChange?(CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer)))
        pendingFrame = frame
        if !isWaitingForRenderer { renderPendingFrame() }
    }

    private func renderPendingFrame() {
        let renderer = displayLayer.sampleBufferRenderer
        if renderer.status == .failed || renderer.requiresFlushToResumeDecoding { renderer.flush() }
        guard let frame = pendingFrame else { return }
        if renderer.isReadyForMoreMediaData {
            pendingFrame = nil
            renderer.enqueue(frame)
        } else {
            isWaitingForRenderer = true
            renderer.requestMediaDataWhenReady(on: .main) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.displayLayer.sampleBufferRenderer.stopRequestingMediaData()
                    self.isWaitingForRenderer = false
                    self.renderPendingFrame()
                }
            }
        }
    }

    func clear() {
        let renderer = displayLayer.sampleBufferRenderer
        renderer.stopRequestingMediaData()
        isWaitingForRenderer = false
        pendingFrame = nil
        renderer.flush(removingDisplayedImage: true, completionHandler: nil)
        cropper.reset()
    }
}
