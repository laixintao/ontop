import AppKit
import AVFoundation
import ScreenCaptureKit

@main
@MainActor
enum SmokeTests {
    private static var assertions = 0
    private static let qa = URL(fileURLWithPath: "build/qa", isDirectory: true)

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            try await Task.sleep(for: .seconds(60))
            fputs("FAIL: tests timed out after 60 seconds\n", stderr)
            exit(1)
        }
        Task { @MainActor in
            do {
                try FileManager.default.createDirectory(at: qa, withIntermediateDirectories: true)
                try resourcesAndSizing()
                try cropping()
                try await interactionAndRendering()
                try await pointerLifecycle()
                print("PASS [\(Bundle.main.preferredLocalizations.first ?? "en")]: \(assertions) assertions — pixel cropping, click-through, controls, opacity, geometry, app switching, lifecycle")
                exit(0)
            } catch {
                fputs("FAIL: \(error)\n", stderr)
                exit(1)
            }
        }
        app.run()
    }

    private struct Failure: Error, CustomStringConvertible { let description: String }
    private static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        assertions += 1
        guard try value() else { throw Failure(description: message) }
    }
    private static func near(_ a: CGFloat, _ b: CGFloat, tolerance: CGFloat = 0.01) -> Bool { abs(a - b) <= tolerance }
    private static func waitFor(_ message: String, until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw Failure(description: message) }
            try await Task.sleep(for: .milliseconds(25))
        }
        assertions += 1
    }
    private static func isolatedDefaults() -> (UserDefaults, String) {
        let name = "app.ontop.tests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    private static func resourcesAndSizing() throws {
        let resources = URL(fileURLWithPath: "build/Debug/OnTop.app/Contents/Resources", isDirectory: true)
        func strings(_ locale: String) throws -> [String: String] {
            let data = try Data(contentsOf: resources.appendingPathComponent("\(locale).lproj/Localizable.strings"))
            return try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: String]
        }
        let en = try strings("en"), zh = try strings("zh-Hans")
        try check(Set(en.keys) == Set(zh.keys), "Translation keys must match")
        for key in ["Return to App", "Stop", "Opacity", "Drag to resize", "Drag to move", "Reset Preview Size"] {
            try check(en[key]?.isEmpty == false && zh[key]?.isEmpty == false, "Missing translation: \(key)")
        }
        let screen = CGSize(width: 1440, height: 900)
        try check(PreviewSizing.initialSize(source: CGSize(width: 1600, height: 1000), available: screen) == CGSize(width: 480, height: 300), "Initial size")
        for source in [CGSize(width: 300, height: 3000), CGSize(width: 8000, height: 200), CGSize(width: 1000, height: 800), .zero] {
            let size = PreviewSizing.initialSize(source: source, available: screen)
            try check(size.width > 0 && size.height > 0 && size.width <= screen.width * 0.8 && size.height <= screen.height * 0.8, "Fit extreme aspect ratios on screen")
            try check(near(size.width / size.height, PreviewSizing.aspectRatio(source)), "Never distort a tall or wide source")
        }
        for available in [CGRect(x: 0, y: 0, width: 1200, height: 800), CGRect(x: -1500, y: -500, width: 1000, height: 700)] {
            let frame = PreviewSizing.constrained(CGRect(x: 10000, y: -10000, width: 2000, height: 1000), to: available)
            try check(available.contains(frame), "Recover offscreen windows on either side of the main display")
            try check(near(frame.width / frame.height, 2), "Clamping must preserve the ratio")
        }
        try check(PreviewSizing.pixelSize(for: CGSize(width: 480, height: 300), scale: 2) == CGSize(width: 960, height: 600), "Retina scaling")
        try check(PreviewSizing.pixelSize(for: CGSize(width: 481, height: 301), scale: 1) == CGSize(width: 482, height: 302), "Even capture dimensions")
        try check(PreviewSizing.pixelSize(for: .zero, scale: .nan) == CGSize(width: 2, height: 2), "Safe invalid geometry")
        try check(PreviewSizing.pixelSize(for: CGSize(width: 20000, height: 20000), scale: 2) == CGSize(width: 8192, height: 8192), "Bounded capture dimensions")
    }

    private static func cropping() throws {
        let cropper = FrameCropper()
        let rect = CGRect(x: 80, y: 60, width: 320, height: 200)
        for scale in [1.0, 2.0, 3.0] {
            let sample = try makeFrame(content: rect, scale: scale)
            try check(FrameContent.pixelRect(in: sample) == rect, "Content points must convert to pixels exactly once at \(scale)x")
            guard let cropped = cropper.prepare(sample), let pixels = CMSampleBufferGetImageBuffer(cropped) else { throw Failure(description: "Crop failed") }
            try check(CVPixelBufferGetWidth(pixels) == 320 && CVPixelBufferGetHeight(pixels) == 200, "Crop must exclude all surrounding padding")
            try checkQuadrants(pixels)
            try savePixels(pixels, name: "cropped-\(Int(scale))x.png")
        }
        let full = try makeFrame()
        try check(cropper.prepare(full) === full, "Unpadded frames must not be copied")
        let black = try makeFrame(content: rect, black: true)
        guard let blackResult = cropper.prepare(black), let blackPixels = CMSampleBufferGetImageBuffer(blackResult) else { throw Failure(description: "Black document was rejected") }
        try check(CVPixelBufferGetWidth(blackPixels) == 320, "Legitimately black documents must not be trimmed by color")
        let empty = try makeFrame(content: .zero)
        try check(cropper.prepare(empty) == nil, "Empty content during transitions must not replace the last frame")
        let offscreen = try makeFrame(content: CGRect(x: 800, y: 0, width: 100, height: 100))
        try check(cropper.prepare(offscreen) == nil, "Invalid out-of-surface metadata must be rejected")
        let fractional = try makeFrame(content: CGRect(x: 10.25, y: 20.25, width: 100.5, height: 80.5))
        try check(FrameContent.pixelRect(in: fractional) == CGRect(x: 11, y: 21, width: 99, height: 79), "Fractional edges must not leak black padding")
        let bounded = FrameCropper()
        var held: [CMSampleBuffer] = []
        for _ in 0..<6 {
            if let sample = bounded.prepare(try makeFrame(content: rect)) { held.append(sample) }
        }
        try check(held.count == 6, "Crop buffer pool should serve the renderer queue")
        try check(bounded.prepare(try makeFrame(content: rect)) == nil, "Back-pressure must cap crop allocations")
        held.removeAll()
        bounded.reset()
        try check(bounded.prepare(try makeFrame(content: rect)) != nil, "Reset must release the crop pool")
    }

    private static func interactionAndRendering() async throws {
        let (defaults, domain) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        let preview = PreviewPanelController(defaults: defaults, tracksPointer: false)
        let capture = CaptureController()
        var closed = 0, returned = 0, chosen = 0
        var viewport = CGSize.zero
        preview.onClose = { closed += 1; capture.stop() }
        preview.onActivateSource = { returned += 1 }
        preview.onChooseWindow = { chosen += 1 }
        preview.onResize = { size, scale in viewport = size; capture.resize(to: size, scale: scale) }
        defer { preview.close() }
        preview.setSourceApplicationActive(true)
        preview.show(sourceSize: CGSize(width: 800, height: 500), title: "Reference document", canActivateSource: true)
        preview.setState(.waiting)
        try check(preview.returnButton.title == NSLocalizedString("Return to App", comment: "Test"), "Return button uses the selected language")
        try check(!preview.panel.isVisible && !preview.controlsPanel.isVisible, "Selecting an active source must not cover it")
        preview.setSourceApplicationActive(false)
        try check(preview.panel.isVisible, "Switching away must restore the picture")
        try check(!preview.controlsPanel.isVisible && !preview.resizePanel.isVisible, "Child controls must not reappear merely because the parent was ordered front")
        try check(preview.panel.ignoresMouseEvents && preview.videoView.hitTest(.zero) == nil, "Picture must always be click-through")
        try check(preview.panel.level == .floating && !preview.panel.hidesOnDeactivate, "Pin across app switches")
        try check(!preview.panel.canBecomeKey && !preview.panel.canBecomeMain, "Never steal focus")
        try check(!preview.panel.styleMask.contains(.titled) && !preview.panel.hasShadow, "No native title frame, including while hovering")
        for behavior: NSWindow.CollectionBehavior in [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary] {
            try check(preview.panel.collectionBehavior.contains(behavior), "Desktop/fullscreen behavior")
        }
        try check(viewport == CGSize(width: 480, height: 300), "Capture viewport must match the picture")
        let original = preview.panel.frame
        let center = CGPoint(x: original.midX, y: original.midY)
        preview.updateHover(at: center, pressedButtons: 1, now: 1)
        try check(!preview.isChromeVisible, "Never introduce controls under an ongoing drag in another app")
        preview.updateHover(at: center, now: 2)
        try check(preview.isChromeVisible && preview.controlsPanel.isVisible && preview.resizePanel.isVisible, "Hover must reveal controls")
        try check(preview.panel.ignoresMouseEvents && !preview.controlsPanel.ignoresMouseEvents, "Only the controls may intercept clicks")
        try check(preview.panel.frame == original && viewport == original.size, "Hover must not resize content")
        preview.updateHover(at: CGPoint(x: -10000, y: -10000), now: 2.1)
        try check(preview.isChromeVisible, "Brief pointer departures must not flicker the controls")
        preview.updateHover(at: CGPoint(x: -10000, y: -10000), now: 2.4)
        try check(!preview.isChromeVisible && !preview.controlsPanel.isVisible, "Controls must hide after leaving")
        preview.setChromeVisible(true)
        try check(!preview.returnButton.isEnabled, "Cannot return before the source is live")
        preview.returnButton.performClick(nil)
        try check(returned == 0, "Disabled return cannot activate an app")
        preview.setState(.live)
        preview.returnButton.performClick(nil)
        try check(returned == 1, "Only the explicit return button activates the source")
        preview.chooseButton.performClick(nil)
        try check(chosen == 1 && returned == 1, "Choose must not activate the source")
        preview.setChoosing(true)
        try check(!preview.chooseButton.isEnabled, "Prevent multiple simultaneous pickers")
        preview.setChoosing(false)
        preview.setState(.paused)
        preview.returnButton.performClick(nil)
        try check(returned == 2, "Paused source can still be opened")
        preview.setState(.unavailable("Closed"))
        try check(!preview.returnButton.isEnabled, "A closed source must not be activated")
        preview.setState(.live)
        preview.show(sourceSize: CGSize(width: 800, height: 500), title: nil)
        try check(!preview.returnButton.isEnabled, "Unknown source app must not get a return action")
        preview.show(sourceSize: CGSize(width: 800, height: 500), title: "Reference document", canActivateSource: true)

        // Native hit testing exercises the same WindowServer routing used by mouse-down.
        let underneath = NSWindow(contentRect: original, styleMask: .borderless, backing: .buffered, defer: false)
        underneath.isReleasedWhenClosed = false
        underneath.level = .floating
        underneath.orderFrontRegardless()
        preview.panel.orderFrontRegardless()
        preview.setChromeVisible(false)
        defer { underneath.close() }
        try await Task.sleep(for: .milliseconds(100))
        try check(NSWindow.windowNumber(at: center, belowWindowWithWindowNumber: 0) == underneath.windowNumber,
                  "WindowServer must route picture clicks to the window underneath")
        preview.setChromeVisible(true)
        preview.controlsPanel.contentView?.layoutSubtreeIfNeeded()
        preview.controlsPanel.displayIfNeeded()
        CATransaction.flush()
        try await Task.sleep(for: .milliseconds(100))
        let buttonPoint = preview.controlsPanel.convertPoint(toScreen: preview.returnButton.convert(CGPoint(x: preview.returnButton.bounds.midX, y: preview.returnButton.bounds.midY), to: nil))
        try check(NSWindow.windowNumber(at: buttonPoint, belowWindowWithWindowNumber: 0) == preview.controlsPanel.windowNumber,
                  "WindowServer button routing: hit=\(NSWindow.windowNumber(at: buttonPoint, belowWindowWithWindowNumber: 0)), expected=\(preview.controlsPanel.windowNumber), point=\(buttonPoint), controls=\(preview.controlsPanel.frame), button=\(preview.returnButton.frame), visible=\(preview.controlsPanel.isVisible)")
        try check(NSWindow.windowNumber(at: center, belowWindowWithWindowNumber: 0) == underneath.windowNumber,
                  "Hovering must not turn the picture into an input blocker")

        // Deliver a real down/up pair through AppKit, not just performClick.
        let location = preview.controlsPanel.convertPoint(fromScreen: buttonPoint)
        func clickEvent(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                              windowNumber: preview.controlsPanel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
        }
        NSApp.postEvent(clickEvent(.leftMouseUp), atStart: true)
        preview.controlsPanel.sendEvent(clickEvent(.leftMouseDown))
        try check(returned == 3, "A native mouse click must trigger Return while the panel cannot become key")

        preview.opacitySlider.doubleValue = 0.55
        preview.opacitySlider.sendAction(preview.opacitySlider.action, to: preview.opacitySlider.target)
        try check(near(preview.panel.alphaValue, 0.55) && near(preview.opacity, 0.55), "Opacity slider must change the actual window")
        try check(preview.controlsPanel.alphaValue == 1 && preview.resizePanel.alphaValue == 1, "Controls must remain readable at low opacity")
        preview.setOpacity(-10)
        try check(preview.opacity == 0.3, "Opacity minimum prevents losing the preview")
        preview.setOpacity(10)
        try check(preview.opacity == 1, "Clamp opacity maximum")
        preview.setOpacity(.nan)
        try check(preview.opacity == 1, "Recover invalid saved opacity")
        preview.setOpacity(0.7)
        let reloaded = PreviewPanelController(defaults: defaults, tracksPointer: false)
        try check(near(reloaded.opacity, 0.7), "Remember opacity in a new session")

        // Dragging a handle moves the entire group without activating the source.
        func event(_ type: NSEvent.EventType, on handle: PreviewHandle, at screenPoint: CGPoint) -> NSEvent {
            let window = handle.window!
            return NSEvent.mouseEvent(with: type, location: window.convertPoint(fromScreen: screenPoint), modifierFlags: [],
                                      timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
        }
        let dragStart = CGPoint(x: preview.controlsPanel.frame.minX + 20, y: preview.controlsPanel.frame.midY)
        let beforeMove = preview.panel.frame
        preview.moveHandle.mouseDown(with: event(.leftMouseDown, on: preview.moveHandle, at: dragStart))
        preview.moveHandle.mouseDragged(with: event(.leftMouseDragged, on: preview.moveHandle, at: CGPoint(x: dragStart.x - 70, y: dragStart.y - 40)))
        preview.updateHover(at: CGPoint(x: -10000, y: -10000), now: 10)
        try check(preview.isChromeVisible, "Keep handles alive during manipulation outside the panel")
        preview.moveHandle.mouseUp(with: event(.leftMouseUp, on: preview.moveHandle, at: dragStart))
        try check(near(preview.panel.frame.minX, beforeMove.minX - 70) && near(preview.panel.frame.minY, beforeMove.minY - 40), "Handle drag must move by screen delta")
        try check(returned == 3, "Dragging must never return to the app")
        let beforeResize = preview.panel.frame
        let resizeStart = CGPoint(x: preview.resizePanel.frame.midX, y: preview.resizePanel.frame.midY)
        preview.resizeHandle.mouseDown(with: event(.leftMouseDown, on: preview.resizeHandle, at: resizeStart))
        preview.resizeHandle.mouseDragged(with: event(.leftMouseDragged, on: preview.resizeHandle, at: CGPoint(x: resizeStart.x - 80, y: resizeStart.y)))
        preview.resizeHandle.mouseUp(with: event(.leftMouseUp, on: preview.resizeHandle, at: resizeStart))
        try check(near(preview.panel.frame.width, beforeResize.width - 80), "Resize handle must change width")
        try check(near(preview.panel.frame.width / preview.panel.frame.height, 1.6), "Resize must preserve the source aspect")
        try check(near(preview.panel.frame.maxY, beforeResize.maxY), "Resize must anchor the top-left corner")
        try check(viewport == preview.videoView.bounds.size, "Resize must update capture resolution")
        try check(preview.videoView.displayLayer.frame == preview.videoView.bounds,
                  "Resizing must resize the actual video layer, not only the NSWindow")

        let source = try makeFrame(content: CGRect(x: 80, y: 60, width: 320, height: 200), scale: 2)
        preview.display(source)
        let renderer = preview.videoView.displayLayer.sampleBufferRenderer
        CMTimebaseSetRate(renderer.timebase, rate: 0)
        if #available(macOS 14.4, *) {
            try await waitFor("Cropped frame never reached native renderer") { renderer.displayedPixelBuffer().map { CVPixelBufferGetWidth($0) == 320 } ?? false }
            try checkQuadrants(renderer.displayedPixelBuffer()!)
        }
        let frame = preview.panel.frame
        let windowID = preview.panel.windowNumber
        for index in 0..<30 {
            preview.setSourceApplicationActive(true)
            try check(!preview.panel.isVisible && !preview.controlsPanel.isVisible && !preview.resizePanel.isVisible, "Hide every window on source activation \(index)")
            preview.display(source)
            preview.setSourceApplicationActive(false)
            try check(preview.panel.frame == frame && preview.panel.windowNumber == windowID && closed == 0, "App switching must not accumulate scale, reset geometry, or stop capture \(index)")
            try check(preview.panel.ignoresMouseEvents && !preview.panel.isKeyWindow, "Restore must preserve pass-through and focus \(index)")
            try check(preview.videoView.displayLayer.frame == preview.videoView.bounds,
                      "Video layer must still fill the restored picture \(index)")
        }
        if #available(macOS 14.4, *) {
            try check(renderer.displayedPixelBuffer() != nil, "Keep the last frame while hidden")
        }
        // Reproduce the screenshot: changing padded output sizes must not change content size.
        for dimensions in [(640, 400), (1200, 900), (800, 600), (640, 400)] {
            let padded = try makeFrame(width: dimensions.0, height: dimensions.1, content: CGRect(x: 80, y: 60, width: 320, height: 200), scale: 2)
            preview.display(padded)
            try check(preview.panel.frame == frame, "Changing IOSurface size/padding must not resize the preview")
            try await Task.sleep(for: .milliseconds(30))
        }
        // A real source aspect change should fit the window, while preserving its chosen width.
        preview.display(try makeFrame(content: CGRect(x: 30, y: 40, width: 320, height: 300)))
        try check(near(preview.panel.frame.width, frame.width) && near(preview.panel.frame.width / preview.panel.frame.height, 320.0 / 300), "Follow real source resizes without letterboxing or stretching")
        try check(preview.videoView.displayLayer.frame == preview.videoView.bounds,
                  "Source aspect changes must also resize the actual video layer")
        preview.display(source)
        preview.setOpacity(1)
        preview.setChromeVisible(true)
        try snapshot(preview.controlsPanel.contentView!, name: "controls-light.png")
        preview.controlsPanel.appearance = NSAppearance(named: .darkAqua)
        preview.controlsPanel.contentView?.needsDisplay = true
        try await Task.sleep(for: .milliseconds(100))
        try snapshot(preview.controlsPanel.contentView!, name: "controls-dark.png")
        preview.controlsPanel.appearance = NSAppearance(named: .aqua)
        preview.setState(.unavailable("Closed"))
        try snapshot(preview.videoView, name: "preview-ended.png")
        preview.setState(.live)
        preview.clear()
        if #available(macOS 14.4, *) {
            try await waitFor("Clear must discard the displayed frame") { renderer.displayedPixelBuffer() == nil }
        }
        preview.display(source)
        if #available(macOS 14.4, *) {
            try await waitFor("Renderer must recover after clear") { renderer.displayedPixelBuffer() != nil }
        }
        preview.setSourceApplicationActive(true)
        preview.close()
        preview.close()
        preview.setSourceApplicationActive(false)
        try check(closed == 1 && !preview.panel.isVisible && !preview.controlsPanel.isVisible, "Stop while hidden must clean up exactly once and prevent resurrection")
        preview.show(sourceSize: CGSize(width: 800, height: 500), title: "New session", canActivateSource: true)
        try check(near(preview.panel.frame.width, beforeResize.width - 80), "Restore chosen width in a fresh session")
        preview.setState(.live)
        preview.setChromeVisible(true)
        preview.stopButton.performClick(nil)
        try check(closed == 2 && !preview.panel.isVisible && !preview.controlsPanel.isVisible, "Explicit Stop button must remove all windows")
        await capture.shutdown()
        try check(capture.state == .idle && !SCContentSharingPicker.shared.isActive, "Stop deactivates picker and capture")
        try check(!capture.activateSourceApplication(), "Idle capture cannot activate an unrelated app")
    }

    private static func pointerLifecycle() async throws {
        let (defaults, domain) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        let preview = PreviewPanelController(defaults: defaults)
        preview.show(sourceSize: CGSize(width: 800, height: 500), title: "Pointer lifecycle")
        try check(preview.isTrackingPointer, "Start passive hover observation only while visible")
        preview.setSourceApplicationActive(true)
        try check(!preview.isTrackingPointer, "No hover polling while hidden")
        preview.setSourceApplicationActive(false)
        try check(preview.isTrackingPointer, "Restore hover observation with the preview")
        preview.resetSize()
        try check(near(preview.panel.frame.width, 480), "Menu reset recovers the default usable size")
        preview.close()
        try check(!preview.isTrackingPointer && !preview.controlsPanel.isVisible, "Stop releases hover timer and controls")
    }

    private static func makeFrame(width: Int = 640, height: Int = 400, content: CGRect? = nil,
                                  scale: Double = 1, black: Bool = false) throws -> CMSampleBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes, &pixelBuffer) == kCVReturnSuccess,
              let buffer = pixelBuffer else { throw Failure(description: "Allocate synthetic frame") }
        let rect = content ?? CGRect(x: 0, y: 0, width: width, height: height)
        CVPixelBufferLockBaseAddress(buffer, [])
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let bytes = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let point = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                let inside = rect.contains(point)
                let colors: (UInt8, UInt8, UInt8)
                if !inside || black { colors = (0, 0, 0) }
                else if CGFloat(y) < rect.midY { colors = CGFloat(x) < rect.midX ? (240, 40, 30) : (40, 210, 60) }
                else { colors = CGFloat(x) < rect.midX ? (35, 90, 235) : (230, 210, 40) }
                let i = y * stride + x * 4
                bytes[i] = colors.2; bytes[i + 1] = colors.1; bytes[i + 2] = colors.0; bytes[i + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format) == noErr,
              let format else { throw Failure(description: "Describe frame") }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
        var result: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: buffer, formatDescription: format,
                                                       sampleTiming: &timing, sampleBufferOut: &result) == noErr,
              let result else { throw Failure(description: "Create sample") }
        if let content, let attachments = CMSampleBufferGetSampleAttachmentsArray(result, createIfNecessary: true) as? [NSMutableDictionary] {
            let points = CGRect(x: content.minX / scale, y: content.minY / scale, width: content.width / scale, height: content.height / scale)
            attachments[0][SCStreamFrameInfo.contentRect.rawValue] = points.dictionaryRepresentation
            attachments[0][SCStreamFrameInfo.scaleFactor.rawValue] = scale
            attachments[0][SCStreamFrameInfo.contentScale.rawValue] = 0.5
        }
        return result
    }

    private static func checkQuadrants(_ buffer: CVPixelBuffer) throws {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let bytes = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        for (x, y, rgb) in [(2, 2, [240, 40, 30]), (width - 3, 2, [40, 210, 60]),
                             (2, height - 3, [35, 90, 235]), (width - 3, height - 3, [230, 210, 40])] {
            let i = y * stride + x * 4
            let actual = [Int(bytes[i + 2]), Int(bytes[i + 1]), Int(bytes[i])]
            try check(zip(actual, rgb).allSatisfy { abs($0 - $1) <= 8 }, "Wrong crop orientation/padding/color at \(x),\(y): \(actual), expected \(rgb)")
        }
    }
    private static func savePixels(_ buffer: CVPixelBuffer, name: String) throws {
        let image = CIImage(cvPixelBuffer: buffer)
        let context = CIContext()
        guard let cg = context.createCGImage(image, from: image.extent),
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { throw Failure(description: "Encode crop QA") }
        try png.write(to: qa.appendingPathComponent(name))
    }
    private static func snapshot(_ view: NSView, name: String) throws {
        view.layoutSubtreeIfNeeded()
        guard let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw Failure(description: "Prepare UI screenshot") }
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: view.bounds, to: image)
        }
        guard let png = image.representation(using: .png, properties: [:]) else { throw Failure(description: "Encode UI screenshot") }
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        try png.write(to: qa.appendingPathComponent(name.replacingOccurrences(of: ".png", with: "-\(language).png")))
    }
}
