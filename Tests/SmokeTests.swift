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
                try chromeGeometry()
                try cropping()
                try await interactionAndRendering()
                try await pointerLifecycle()
                try await multipleWindows()
                print("PASS [\(Bundle.main.preferredLocalizations.first ?? "en")]: \(assertions) assertions — pixel cropping, click-through, controls, opacity, geometry, app switching, multiple windows, lifecycle")
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
        for key in ["Return to App", "Stop", "Hide", "Hide Preview", "Show Preview", "Show All Previews", "Opacity", "Drag to resize", "Drag to move", "Reset Preview Size"] {
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

    private static func chromeGeometry() throws {
        let controls = CGSize(width: 480, height: 44), handle = CGSize(width: 24, height: 24)
        for screen in [CGRect(x: 16, y: 16, width: 1408, height: 840), CGRect(x: -1550, y: -400, width: 1000, height: 700), CGRect(x: 16, y: 16, width: 768, height: 550)] {
            let content = PreviewChromeLayout.contentArea(in: screen, toolbarHeight: controls.height, resizeWidth: handle.width)
            for source in [CGSize(width: 480, height: 300), CGSize(width: 100, height: 1200), CGSize(width: 5000, height: 80)] {
                for origin in [CGPoint(x: screen.minX - 1000, y: screen.minY - 1000), CGPoint(x: screen.maxX + 1000, y: screen.maxY + 1000)] {
                    let picture = PreviewSizing.constrained(CGRect(origin: origin, size: source), to: content)
                    let chrome = PreviewChromeLayout.frames(picture: picture, controls: controls, resize: handle, screen: screen)
                    try check(chrome.toolbar.minY > picture.maxY, "Toolbar must stay strictly above the entire picture")
                    try check(!chrome.handle.intersects(picture), "Resize handle must stay outside the picture")
                    try check(screen.contains(chrome.toolbar) && screen.contains(chrome.handle), "Chrome must remain on-screen at every edge, aspect ratio, and display origin")
                }
            }
        }
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
        // A user's notification banners occupy the default top-right position.
        // Keep our hit-testing fixture in the screen center without dismissing
        // their notifications or changing the app's actual window levels.
        if let screen = preview.panel.screen?.visibleFrame {
            preview.panel.setFrameOrigin(CGPoint(x: screen.midX - preview.panel.frame.width / 2,
                                                 y: screen.midY - preview.panel.frame.height / 2))
        }
        let original = preview.panel.frame
        let center = CGPoint(x: original.midX, y: original.midY)
        preview.updateHover(at: center, pressedButtons: 1, now: 1)
        try check(!preview.isChromeVisible, "Never introduce controls under an ongoing drag in another app")
        preview.updateHover(at: center, now: 2)
        try check(preview.isChromeVisible && preview.controlsPanel.isVisible && preview.resizePanel.isVisible, "Hover must reveal controls")
        try check(preview.panel.ignoresMouseEvents && !preview.controlsPanel.ignoresMouseEvents, "Only the controls may intercept clicks")
        try check(preview.panel.frame == original && viewport == original.size, "Hover must not resize content")
        try check(preview.controlsPanel.frame.minY > original.maxY && !preview.resizePanel.frame.intersects(original), "All hover buttons and handles must stay outside the reference picture")
        let hoverBridge = CGPoint(x: original.midX, y: original.maxY + 3)
        preview.updateHover(at: hoverBridge, now: 3)
        preview.updateHover(at: hoverBridge, now: 4)
        try check(preview.isChromeVisible, "Slowly crossing the gap to the toolbar must not hide it")
        preview.updateHover(at: CGPoint(x: preview.controlsPanel.frame.midX, y: preview.controlsPanel.frame.midY), now: 5)
        try check(preview.isChromeVisible, "The detached toolbar must remain hoverable")
        preview.updateHover(at: CGPoint(x: -10000, y: -10000), now: 5.1)
        try check(preview.isChromeVisible, "Brief pointer departures must not flicker the controls")
        preview.updateHover(at: CGPoint(x: -10000, y: -10000), now: 5.4)
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
        // The developer may run tests while another app is in a fullscreen Space.
        // Put the receiver in the same Spaces as the preview being tested.
        underneath.collectionBehavior = preview.panel.collectionBehavior
        underneath.orderFrontRegardless()
        preview.panel.orderFrontRegardless()
        preview.setChromeVisible(false)
        defer { underneath.close() }
        underneath.displayIfNeeded()
        CATransaction.flush()
        try await waitFor("WindowServer must route picture clicks to the window underneath (receiver=\(underneath.windowNumber), point=\(center), visible=\(underneath.isVisible))") {
            NSWindow.windowNumber(at: center, belowWindowWithWindowNumber: 0) == underneath.windowNumber
        }
        preview.setChromeVisible(true)
        preview.controlsPanel.contentView?.layoutSubtreeIfNeeded()
        preview.controlsPanel.displayIfNeeded()
        CATransaction.flush()
        let buttonPoint = preview.controlsPanel.convertPoint(toScreen: preview.returnButton.convert(CGPoint(x: preview.returnButton.bounds.midX, y: preview.returnButton.bounds.midY), to: nil))
        try await waitFor("WindowServer button routing: expected=\(preview.controlsPanel.windowNumber), point=\(buttonPoint), controls=\(preview.controlsPanel.frame), button=\(preview.returnButton.frame), visible=\(preview.controlsPanel.isVisible)") {
            NSWindow.windowNumber(at: buttonPoint, belowWindowWithWindowNumber: 0) == preview.controlsPanel.windowNumber
        }
        try check(NSWindow.windowNumber(at: center, belowWindowWithWindowNumber: 0) == underneath.windowNumber,
                  "Hovering must not turn the picture into an input blocker")
        for picturePoint in [CGPoint(x: original.midX, y: original.maxY - 12), CGPoint(x: original.maxX - 12, y: original.minY + 12)] {
            try await waitFor("The former toolbar and resize-handle areas must pass clicks through (point=\(picturePoint), receiver=\(underneath.windowNumber), actual=\(NSWindow.windowNumber(at: picturePoint, belowWindowWithWindowNumber: 0)), picture=\(preview.panel.frame), controls=\(preview.controlsPanel.frame), resize=\(preview.resizePanel.frame))") {
                NSWindow.windowNumber(at: picturePoint, belowWindowWithWindowNumber: 0) == underneath.windowNumber
            }
        }

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
        // Start near the enlarged grip's edge, outside its former hit area.
        let gripPoint = CGPoint(x: 40, y: 2)
        let content = preview.controlsPanel.contentView!
        let receiver = content.hitTest(preview.moveHandle.convert(gripPoint, to: content.superview))
        try check(receiver === preview.moveHandle, "The enlarged grip's padding must accept dragging, not just its icon")
        let dragStart = preview.controlsPanel.convertPoint(toScreen: preview.moveHandle.convert(gripPoint, to: nil))
        let beforeMove = preview.panel.frame
        receiver?.mouseDown(with: event(.leftMouseDown, on: preview.moveHandle, at: dragStart))
        receiver?.mouseDragged(with: event(.leftMouseDragged, on: preview.moveHandle, at: CGPoint(x: dragStart.x - 70, y: dragStart.y - 40)))
        preview.updateHover(at: CGPoint(x: -10000, y: -10000), now: 10)
        try check(preview.isChromeVisible, "Keep handles alive during manipulation outside the panel")
        receiver?.mouseUp(with: event(.leftMouseUp, on: preview.moveHandle, at: dragStart))
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
        try check(capture.state == .idle, "Stop leaves the capture idle")
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
        let savedFrame = preview.panel.frame
        preview.setChromeVisible(true)
        preview.hideButton.performClick(nil)
        try check(preview.isTemporarilyHidden && !preview.isTrackingPointer && !preview.panel.isVisible && !preview.controlsPanel.isVisible && !preview.resizePanel.isVisible, "Hide must remove all display surfaces and stop pointer polling")
        for _ in 0..<3 {
            preview.setSourceApplicationActive(true)
            preview.setSourceApplicationActive(false)
            try check(!preview.panel.isVisible && preview.isTemporarilyHidden, "App switches must not undo a manual hide")
        }
        preview.setSourceApplicationActive(true)
        preview.setTemporarilyHidden(false)
        try check(!preview.panel.isVisible && !preview.isTemporarilyHidden, "Showing a manually hidden preview still respects active source visibility")
        preview.setSourceApplicationActive(false)
        try check(preview.panel.isVisible && preview.isTrackingPointer && preview.panel.frame == savedFrame, "Restore must resume tracking at the same size and position")
        preview.setTemporarilyHidden(true)
        preview.show(sourceSize: CGSize(width: 800, height: 500), title: "Explicit new source")
        try check(!preview.isTemporarilyHidden && preview.panel.isVisible, "Explicitly replacing a hidden source makes the new preview available")
        preview.setTemporarilyHidden(true)
        preview.close()
        preview.setTemporarilyHidden(false)
        try check(!preview.isTrackingPointer && !preview.controlsPanel.isVisible, "Stop releases hover timer and controls")
        try check(!preview.panel.isVisible, "A stopped hidden preview must not be resurrected by Show")
    }

    @MainActor
    private final class TestCapture: WindowCapture {
        let token = NSObject()
        var state: CaptureState = .idle { didSet { onStateChange?(state) } }
        var sourceApplicationProcessIdentifier: pid_t?
        var sourceWindowIdentifier: CGWindowID?
        var streamForPicker: SCStream? { nil }
        var streamIdentifier: ObjectIdentifier? { ObjectIdentifier(token) }
        var onFrame: ((CMSampleBuffer) -> Void)?
        var onReset: (() -> Void)?
        var onSelection: ((CGSize, String?, Bool) -> Void)?
        var onStateChange: ((CaptureState) -> Void)?
        var stops = 0, shutdowns = 0, activations = 0
        var viewport = CGSize.zero
        func select(_ filter: SCContentFilter) {}
        func show(id: CGWindowID, pid: pid_t, size: CGSize = CGSize(width: 800, height: 500)) {
            sourceWindowIdentifier = id
            sourceApplicationProcessIdentifier = pid
            state = .waiting
            onSelection?(size, "Reference \(id)", true)
            state = .live
        }
        func resize(to size: CGSize, scale: CGFloat) { viewport = size }
        @discardableResult func activateSourceApplication() -> Bool { activations += 1; return true }
        func stop() { stops += 1; state = .idle }
        func shutdown() async { shutdowns += 1 }
    }

    private static func multipleWindows() async throws {
        let (defaults, domain) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        var captures: [TestCapture] = []
        let pins = PinManager(defaults: defaults, tracksPointer: false) {
            let capture = TestCapture()
            captures.append(capture)
            return capture
        }
        try check(pins.beginSelection(), "Begin an initial share")
        try check(!pins.beginSelection(), "Only one system picker may be presented at a time")
        let first = pins.destination(for: nil, sourceWindowID: 101)!
        captures[0].show(id: 101, pid: 1001)
        // A nil-stream callback from the system sharing menu must add a new
        // preview even when OnTop did not explicitly present that picker.
        let second = pins.destination(for: nil, sourceWindowID: 102)!
        captures[1].show(id: 102, pid: 1002)
        try check(pins.windows.count == 2 && first !== second, "Two shared windows must create two independent previews")
        try check(first.preview.panel !== second.preview.panel && first.preview.panel.isVisible && second.preview.panel.isVisible, "Both native preview windows must be visible")
        try check(first.preview.panel.frame != second.preview.panel.frame, "New preview slots must not stack in exactly the same position")
        try check(first.preview.panel.ignoresMouseEvents && second.preview.panel.ignoresMouseEvents, "Every picture remains click-through")
        // Small displays may need cascading pictures. Where tiling fits, leave
        // room for the external controls between the two reference windows.
        if !first.preview.panel.frame.intersects(second.preview.panel.frame) {
            try check(!first.preview.controlsPanel.frame.intersects(second.preview.panel.frame) && !second.preview.controlsPanel.frame.intersects(first.preview.panel.frame), "Initial tiling must leave room for each preview's external toolbar")
        }
        let firstFrame = first.preview.panel.frame
        let secondFrame = second.preview.panel.frame
        first.preview.setOpacity(0.4)
        second.preview.setOpacity(0.85)
        try check(near(first.preview.panel.alphaValue, 0.4) && near(second.preview.panel.alphaValue, 0.85), "Each window has independent opacity")
        try check(near(defaults.double(forKey: "previewOpacity"), 0.4) && near(defaults.double(forKey: "preview.1.previewOpacity"), 0.85), "Settings must persist separately per preview slot")
        first.preview.returnButton.performClick(nil)
        try check(captures[0].activations == 1 && captures[1].activations == 0, "Return must activate only the selected source")
        first.preview.setChromeVisible(true)
        first.preview.hideButton.performClick(nil)
        try check(!first.preview.panel.isVisible && second.preview.panel.isVisible && pins.windows.count == 2, "Hide must affect only one preview and keep its session")
        try check(captures[0].stops == 0 && captures[0].state == .live && SCContentSharingPicker.shared.isActive, "Hiding must preserve the stream and system sharing authorization")
        captures[0].onFrame?(try makeFrame())
        captures[0].state = .paused
        captures[0].state = .live
        pins.setFrontmostApplication(1003)
        try check(first.preview.isTemporarilyHidden && !first.preview.panel.isVisible, "Incoming frames and stream state changes must not restore a manually hidden preview")
        second.preview.setTemporarilyHidden(true)
        pins.showAllPreviews()
        try check(first.preview.panel.isVisible && second.preview.panel.isVisible && first.preview.panel.frame == firstFrame && second.preview.panel.frame == secondFrame, "Show All restores independent frames without choosing sources again")
        try check(near(first.preview.opacity, 0.4) && near(second.preview.opacity, 0.85), "Hide and Show All must preserve each opacity")
        for _ in 0..<10 {
            pins.setFrontmostApplication(1001)
            try check(!first.preview.panel.isVisible && second.preview.panel.isVisible, "Using source A must leave source B visible")
            pins.setFrontmostApplication(1002)
            try check(first.preview.panel.isVisible && !second.preview.panel.isVisible, "Using source B must leave source A visible")
            pins.setFrontmostApplication(1003)
            try check(first.preview.panel.frame == firstFrame && second.preview.panel.frame == secondFrame, "Switching apps preserves each preview's geometry")
        }

        let firstPixels = try makeFrame(content: CGRect(x: 80, y: 60, width: 320, height: 200))
        let secondPixels = try makeFrame(content: CGRect(x: 40, y: 20, width: 240, height: 240))
        captures[0].onFrame?(firstPixels)
        captures[1].onFrame?(secondPixels)
        let firstRenderer = first.preview.videoView.displayLayer.sampleBufferRenderer
        let secondRenderer = second.preview.videoView.displayLayer.sampleBufferRenderer
        CMTimebaseSetRate(firstRenderer.timebase, rate: 0)
        CMTimebaseSetRate(secondRenderer.timebase, rate: 0)
        if #available(macOS 14.4, *) {
            try await waitFor("Both independent renderers must receive their own frames") {
                firstRenderer.displayedPixelBuffer().map { CVPixelBufferGetWidth($0) == 320 } == true &&
                secondRenderer.displayedPixelBuffer().map { CVPixelBufferGetWidth($0) == 240 } == true
            }
            try checkQuadrants(firstRenderer.displayedPixelBuffer()!)
            try checkQuadrants(secondRenderer.displayedPixelBuffer()!)
        }
        try check(near(first.preview.panel.frame.width / first.preview.panel.frame.height, 1.6) && near(second.preview.panel.frame.width / second.preview.panel.frame.height, 1), "One source's aspect changes must not resize another preview")

        // Overlap the two pictures: only the top one may show a toolbar.
        second.preview.panel.setFrame(first.preview.panel.frame, display: true)
        second.preview.panel.orderFrontRegardless()
        let point = CGPoint(x: first.preview.panel.frame.midX, y: first.preview.panel.frame.midY)
        first.preview.setChromeVisible(false)
        second.preview.setChromeVisible(false)
        try await waitFor("Hover routing must follow the topmost picture") { pins.hoverOwner(at: point) === second }
        first.preview.updateHover(at: point)
        second.preview.updateHover(at: point)
        try check(!first.preview.isChromeVisible && second.preview.isChromeVisible, "Overlapping previews must not expose competing hover controls")
        let bridge = CGPoint(x: second.preview.panel.frame.midX, y: second.preview.panel.frame.maxY + 3)
        try check(pins.hoverOwner(at: bridge) === second, "Multi-window hover routing must include the toolbar gap")
        second.preview.updateHover(at: bridge, now: 100)
        second.preview.updateHover(at: bridge, now: 101)
        try check(second.preview.isChromeVisible, "Crossing to detached controls must remain stable with overlapping previews")
        try snapshot(second.preview.controlsPanel.contentView!, name: "multiwindow-controls.png")
        second.preview.resetSize()

        try check(pins.beginSelection(replacing: first.id), "Replace only the requested preview")
        try check(!first.preview.chooseButton.isEnabled && !second.preview.chooseButton.isEnabled, "Disable new picker actions in all previews during a selection")
        try check(pins.destination(for: captures[0].streamIdentifier, sourceWindowID: 103) === first, "An existing stream's update must route to its own preview")
        captures[0].show(id: 103, pid: 1004)
        try check(pins.windows.count == 2 && captures[1].stops == 0, "Replacing one source must not replace or stop the second")
        try check(pins.beginSelection(), "Begin adding another source")
        pins.cancelSelection()
        try check(pins.windows.count == 2 && !pins.isChoosing && SCContentSharingPicker.shared.isActive, "Cancel keeps existing previews and sharing active")
        try check(pins.destination(for: nil, sourceWindowID: 102) === second && pins.windows.count == 2, "Re-sharing the same window must not make duplicates")

        captures[1].sourceApplicationProcessIdentifier = 1004
        pins.setFrontmostApplication(1004)
        try check(!first.preview.panel.isVisible && !second.preview.panel.isVisible, "Two references from one source app must both hide when that app is active")
        pins.setFrontmostApplication(1006)
        try check(first.preview.panel.isVisible && second.preview.panel.isVisible, "Both references from the same app must return after switching away")

        captures[0].state = .unavailable("Closed")
        try check(second.preview.panel.isVisible && SCContentSharingPicker.shared.isActive, "An ended stream must not disable other streams or the shared picker")
        let firstStream = captures[0].streamIdentifier
        try check(pins.beginSelection(replacing: first.id), "Can choose a replacement for an ended source")
        pins.stop(id: first.id)
        try check(pins.destination(for: firstStream, sourceWindowID: 104) == nil && !pins.isChoosing, "Late selection for a stopped window cannot resurrect it or leave the picker busy")
        try check(pins.windows.count == 1 && pins.windows.first === second && captures[1].stops == 0, "Stopping A keeps B capturing")
        let third = pins.destination(for: nil, sourceWindowID: 105)!
        captures[2].show(id: 105, pid: 1005)
        try check(third.slot == 0 && near(third.preview.opacity, 0.4), "Reuse a freed preference slot without overwriting another window's settings")
        second.preview.stopButton.performClick(nil)
        try check(pins.windows.count == 1 && pins.windows.first === third && captures[2].stops == 0, "A preview's Stop button closes only that preview")
        third.preview.setTemporarilyHidden(true)
        pins.stopAll()
        try check(pins.windows.isEmpty && !SCContentSharingPicker.shared.isActive, "Stop All ends all previews and deactivates the picker")
        try check(pins.destination(for: nil, sourceWindowID: 106) == nil, "Late new-share callbacks after Stop All cannot recreate previews")
        try check(!first.preview.panel.isVisible && !second.preview.panel.isVisible && !third.preview.panel.isVisible, "Stop All hides every native window")
        await pins.shutdown()
        try check(captures.allSatisfy { $0.stops == 1 && $0.shutdowns == 1 }, "Every capture must be stopped and awaited exactly once")
        try check(!pins.beginSelection(), "Shutdown must reject any new picker")
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
