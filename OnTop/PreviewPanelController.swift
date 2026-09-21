import AppKit
import AVFoundation

enum PreviewSizing {
    static func aspectRatio(_ source: CGSize) -> CGFloat {
        guard source.width.isFinite, source.height.isFinite, source.width > 0, source.height > 0 else { return 1.6 }
        return min(100, max(0.01, source.width / source.height))
    }

    static func size(source: CGSize, preferredWidth: CGFloat, available: CGSize) -> CGSize {
        let ratio = aspectRatio(source)
        let maxWidth = max(1, min(available.width, available.height * ratio))
        let width = min(maxWidth, max(min(240, maxWidth), preferredWidth.isFinite ? preferredWidth : 480))
        return CGSize(width: width, height: width / ratio)
    }

    static func initialSize(source: CGSize, available: CGSize) -> CGSize {
        size(source: source, preferredWidth: 480, available: CGSize(width: available.width * 0.8, height: available.height * 0.8))
    }

    static func constrained(_ frame: CGRect, to available: CGRect) -> CGRect {
        let size = size(source: frame.size, preferredWidth: frame.width, available: available.size)
        return CGRect(x: min(max(frame.minX, available.minX), available.maxX - size.width),
                      y: min(max(frame.minY, available.minY), available.maxY - size.height),
                      width: size.width, height: size.height)
    }

    static func pixelSize(for viewport: CGSize, scale: CGFloat) -> CGSize {
        let scale = scale.isFinite ? max(1, scale) : 1
        func pixels(_ points: CGFloat) -> CGFloat {
            guard points.isFinite else { return 2 }
            return min(8192, max(2, (points * scale / 2).rounded(.up) * 2))
        }
        return CGSize(width: pixels(viewport.width), height: pixels(viewport.height))
    }
}

/// Keep interactive chrome outside the picture, with room reserved even while
/// it is hidden so hovering never moves or resizes the reference.
enum PreviewChromeLayout {
    static let toolbarGap: CGFloat = 6
    static let resizeGap: CGFloat = 4

    static func contentArea(in screen: CGRect, toolbarHeight: CGFloat, resizeWidth: CGFloat) -> CGRect {
        CGRect(x: screen.minX, y: screen.minY,
               width: max(1, screen.width - resizeWidth - resizeGap),
               height: max(1, screen.height - toolbarHeight - toolbarGap))
    }

    static func frames(picture: CGRect, controls: CGSize, resize: CGSize, screen: CGRect) -> (toolbar: CGRect, handle: CGRect) {
        let x = min(max(picture.midX - controls.width / 2, screen.minX), max(screen.minX, screen.maxX - controls.width))
        return (CGRect(x: x, y: picture.maxY + toolbarGap, width: controls.width, height: controls.height),
                CGRect(x: picture.maxX + resizeGap, y: picture.minY, width: resize.width, height: resize.height))
    }
}

private final class PreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PreviewButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Explicit handles keep both dragging and resizing out of the click-through picture.
@MainActor
final class PreviewHandle: NSView {
    var onBegin: (() -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    var onEnd: (() -> Void)?
    private var anchor: CGPoint?
    private let resize: Bool

    init(resize: Bool) {
        self.resize = resize
        super.init(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        let label = NSLocalizedString(resize ? "Drag to resize" : "Drag to move", comment: "Preview handle")
        toolTip = label
        setAccessibilityLabel(label)
        let image = NSImageView(image: NSImage(systemSymbolName: resize ? "arrow.up.left.and.arrow.down.right" : "line.3.horizontal", accessibilityDescription: label)!)
        image.contentTintColor = resize ? .secondaryLabelColor : .labelColor
        image.imageScaling = .scaleProportionallyUpOrDown
        image.translatesAutoresizingMaskIntoConstraints = false
        addSubview(image)
        NSLayoutConstraint.activate([
            image.centerXAnchor.constraint(equalTo: centerXAnchor),
            image.centerYAnchor.constraint(equalTo: centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: resize ? 16 : 20),
            image.heightAnchor.constraint(equalToConstant: resize ? 16 : 20)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(convert(point, from: superview)) ? self : nil }
    override var mouseDownCanMoveWindow: Bool { false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: resize ? .crosshair : .openHand) }
    override func draw(_ dirtyRect: NSRect) {
        guard !resize else { return }
        NSColor.labelColor.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 4), xRadius: 6, yRadius: 6).fill()
    }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        anchor = window.convertPoint(toScreen: event.locationInWindow)
        onBegin?()
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window, let anchor else { return }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        onDrag?(CGPoint(x: point.x - anchor.x, y: point.y - anchor.y))
    }
    override func mouseUp(with event: NSEvent) {
        guard anchor != nil else { return }
        anchor = nil
        onEnd?()
    }
}

@MainActor
final class PreviewPanelController: NSObject, NSWindowDelegate {
    var onChooseWindow: (() -> Void)?
    var onActivateSource: (() -> Void)?
    var onClose: (() -> Void)?
    var onResize: ((CGSize, CGFloat) -> Void)?
    var shouldRevealControls: ((CGPoint) -> Bool)?
    var onVisibilityChange: (() -> Void)?

    let panel: NSPanel
    let controlsPanel: NSPanel
    let resizePanel: NSPanel
    let videoView = VideoView()
    let returnButton = PreviewButton()
    let stopButton = PreviewButton()
    let hideButton = PreviewButton()
    let chooseButton = PreviewButton()
    let opacitySlider = NSSlider(value: 1, minValue: 0.3, maxValue: 1, target: nil, action: nil)
    let moveHandle = PreviewHandle(resize: false)
    let resizeHandle = PreviewHandle(resize: true)
    private let opacityLabel = NSTextField(labelWithString: "100%")
    private let message = NSTextField(wrappingLabelWithString: "")
    private let statusBackground = NSVisualEffectView()
    private let defaults: UserDefaults
    private let tracksPointer: Bool
    private let slot: Int
    private var pointerTimer: Timer?
    private var state: CaptureState = .idle
    private var sourceSize = CGSize(width: 800, height: 500)
    private var canActivateSource = false
    private var isPresented = false
    private var sourceIsActive = false
    private var isManipulating = false
    private var manipulationFrame = CGRect.zero
    private var lastHoverTime: TimeInterval = 0
    private(set) var isChromeVisible = false
    private(set) var opacity: Double = 1
    private(set) var isTrackingPointer = false
    private(set) var isTemporarilyHidden = false

    init(defaults: UserDefaults = .standard, tracksPointer: Bool = true, slot: Int = 0) {
        self.defaults = defaults
        self.tracksPointer = tracksPointer
        self.slot = slot
        func makePanel(_ size: CGSize) -> NSPanel {
            let panel = PreviewPanel(contentRect: CGRect(origin: .zero, size: size),
                                     styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .floating
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .ignoresCycle]
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            return panel
        }
        panel = makePanel(CGSize(width: 480, height: 300))
        controlsPanel = makePanel(CGSize(width: 440, height: 44))
        resizePanel = makePanel(CGSize(width: 24, height: 24))
        super.init()
        // Child windows inherit the parent's click-through behavior at the
        // WindowServer level. Keep the hit-testable controls independent.
        controlsPanel.level = NSWindow.Level(rawValue: panel.level.rawValue + 1)
        resizePanel.level = controlsPanel.level
        panel.ignoresMouseEvents = true
        panel.delegate = self
        panel.contentView = videoView
        configureControls()
        configureStatus()
        videoView.onContentSizeChange = { [weak self] size in self?.updateSourceSize(size) }
        configureHandle(moveHandle, resizing: false)
        configureHandle(resizeHandle, resizing: true)
        setOpacity(defaults.object(forKey: preferenceKey("previewOpacity")) as? Double ?? 1)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }
    @objc private func screenChanged() { keepOnScreen() }

    private func materialView() -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 10
        view.layer?.masksToBounds = true
        return view
    }

    private func configureControls() {
        func button(_ button: NSButton, title: String, symbol: String, action: Selector) {
            button.title = NSLocalizedString(title, comment: "Preview control")
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
            button.bezelStyle = .inline
            button.isBordered = false
            button.font = .systemFont(ofSize: 12, weight: .medium)
            button.contentTintColor = .labelColor
            button.refusesFirstResponder = true
            button.target = self
            button.action = action
            button.setAccessibilityLabel(button.title)
        }
        button(returnButton, title: "Return to App", symbol: "arrow.up.forward.app", action: #selector(returnToSource))
        button(hideButton, title: "Hide", symbol: "eye.slash", action: #selector(hidePreview))
        hideButton.toolTip = NSLocalizedString("Temporarily hide this preview. Restore it from the OnTop menu.", comment: "Hide preview help")
        hideButton.setAccessibilityLabel(NSLocalizedString("Hide Preview", comment: "Menu item"))
        button(stopButton, title: "Stop", symbol: "stop.circle", action: #selector(stopPinning))
        button(chooseButton, title: "", symbol: "rectangle.on.rectangle", action: #selector(chooseWindow))
        chooseButton.toolTip = NSLocalizedString("Choose another window", comment: "Preview control")
        chooseButton.setAccessibilityLabel(chooseButton.toolTip)
        stopButton.toolTip = NSLocalizedString("Stop Pinning", comment: "Preview control")
        opacitySlider.isContinuous = true
        opacitySlider.controlSize = .small
        opacitySlider.target = self
        opacitySlider.action = #selector(opacityChanged)
        opacitySlider.toolTip = NSLocalizedString("Opacity", comment: "Preview opacity")
        opacitySlider.setAccessibilityLabel(opacitySlider.toolTip)
        opacityLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        opacityLabel.alignment = .right
        opacityLabel.textColor = .secondaryLabelColor
        let opacityIcon = NSImageView(image: NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: opacitySlider.toolTip)!)
        opacityIcon.contentTintColor = .secondaryLabelColor
        let stack = NSStackView(views: [moveHandle, returnButton, hideButton, stopButton, chooseButton, opacityIcon, opacitySlider, opacityLabel])
        stack.spacing = 10
        stack.alignment = .centerY
        for (view, width) in [(moveHandle as NSView, 44.0), (chooseButton, 26.0), (opacityIcon, 14.0), (opacitySlider, 72.0), (opacityLabel, 36.0)] {
            view.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        moveHandle.heightAnchor.constraint(equalToConstant: 44).isActive = true
        let background = materialView()
        controlsPanel.contentView = background
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: background.centerYAnchor)
        ])
        controlsPanel.setContentSize(CGSize(width: stack.fittingSize.width + 20, height: 44))
        let resizeBackground = materialView()
        resizePanel.contentView = resizeBackground
        resizeHandle.frame = resizeBackground.bounds
        resizeHandle.autoresizingMask = [.width, .height]
        resizeBackground.addSubview(resizeHandle)
        controlsPanel.orderOut(nil)
        resizePanel.orderOut(nil)
        updateSourceAction()
    }

    private func configureStatus() {
        statusBackground.material = .hudWindow
        statusBackground.blendingMode = .withinWindow
        statusBackground.state = .active
        statusBackground.wantsLayer = true
        statusBackground.layer?.cornerRadius = 8
        statusBackground.translatesAutoresizingMaskIntoConstraints = false
        message.font = .systemFont(ofSize: 12, weight: .medium)
        message.alignment = .center
        message.translatesAutoresizingMaskIntoConstraints = false
        statusBackground.addSubview(message)
        videoView.addSubview(statusBackground)
        NSLayoutConstraint.activate([
            statusBackground.centerXAnchor.constraint(equalTo: videoView.centerXAnchor),
            statusBackground.bottomAnchor.constraint(equalTo: videoView.bottomAnchor, constant: -12),
            statusBackground.widthAnchor.constraint(lessThanOrEqualTo: videoView.widthAnchor, constant: -24),
            message.leadingAnchor.constraint(equalTo: statusBackground.leadingAnchor, constant: 12),
            message.trailingAnchor.constraint(equalTo: statusBackground.trailingAnchor, constant: -12),
            message.topAnchor.constraint(equalTo: statusBackground.topAnchor, constant: 8),
            message.bottomAnchor.constraint(equalTo: statusBackground.bottomAnchor, constant: -8)
        ])
        statusBackground.isHidden = true
    }

    private var screenFrame: CGRect {
        (panel.screen ?? NSScreen.main)?.visibleFrame.insetBy(dx: 16, dy: 16)
            ?? CGRect(x: 16, y: 16, width: 1248, height: 768)
    }

    private func contentArea(in screen: CGRect) -> CGRect {
        PreviewChromeLayout.contentArea(in: screen, toolbarHeight: controlsPanel.frame.height, resizeWidth: resizePanel.frame.width)
    }

    private var availableFrame: CGRect { contentArea(in: screenFrame) }

    func show(sourceSize: CGSize, title: String?, canActivateSource: Bool = false) {
        self.sourceSize = sourceSize
        self.canActivateSource = canActivateSource
        panel.title = title.map { "\($0) — OnTop" } ?? "OnTop"
        returnButton.toolTip = title.map { "\(NSLocalizedString("Return to App", comment: "Preview control")): \($0)" }
        updateSourceAction()
        if !isPresented {
            let saved = defaults.string(forKey: preferenceKey("previewFrame")).map(NSRectFromString)
            let savedScreen = saved.flatMap { frame in NSScreen.screens.first { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) } }
            let screen = savedScreen ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            let available = contentArea(in: screen?.visibleFrame.insetBy(dx: 16, dy: 16) ?? screenFrame)
            let size = PreviewSizing.initialSize(source: sourceSize, available: available.size)
            let initial = initialFrame(size: size, available: available)
            let restored = saved.flatMap { frame -> CGRect? in
                guard frame.width > 0, frame.height > 0,
                      [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite) else { return nil }
                let size = PreviewSizing.size(source: sourceSize, preferredWidth: frame.width, available: available.size)
                return CGRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height)
            }
            panel.setFrame(PreviewSizing.constrained(restored ?? initial, to: available), display: false)
        } else {
            fitSourceKeepingTopLeft()
        }
        isPresented = true
        let wasHidden = isTemporarilyHidden
        isTemporarilyHidden = false
        layoutControls()
        updateVisibility()
        notifyResize()
        if wasHidden { onVisibilityChange?() }
    }

    private func updateSourceSize(_ size: CGSize) {
        // Ignore rounding noise from even output dimensions, not source resizes.
        guard abs(PreviewSizing.aspectRatio(size) / PreviewSizing.aspectRatio(sourceSize) - 1) > 0.005 else { return }
        sourceSize = size
        fitSourceKeepingTopLeft()
    }

    private func fitSourceKeepingTopLeft() {
        let size = PreviewSizing.size(source: sourceSize, preferredWidth: panel.frame.width, available: availableFrame.size)
        let frame = CGRect(x: panel.frame.minX, y: panel.frame.maxY - size.height, width: size.width, height: size.height)
        panel.setFrame(PreviewSizing.constrained(frame, to: availableFrame), display: true)
        layoutControls()
    }

    func resetSize() {
        guard isPresented else { return }
        let size = PreviewSizing.initialSize(source: sourceSize, available: availableFrame.size)
        let frame = initialFrame(size: size, available: availableFrame)
        panel.setFrame(frame, display: true)
        layoutControls()
        saveFrame()
    }

    private func preferenceKey(_ key: String) -> String { slot == 0 ? key : "preview.\(slot).\(key)" }

    private func initialFrame(size: CGSize, available: CGRect) -> CGRect {
        let verticalGap = controlsPanel.frame.height + PreviewChromeLayout.toolbarGap + 16
        let horizontalGap = resizePanel.frame.width + PreviewChromeLayout.resizeGap + 16
        let rows = max(1, Int((available.height + verticalGap) / (size.height + verticalGap)))
        let columns = max(1, Int((available.width + horizontalGap) / (size.width + horizontalGap)))
        let page = slot / (rows * columns)
        let column = (slot / rows) % columns
        let row = slot % rows
        let frame = CGRect(x: available.maxX - size.width - CGFloat(column) * (size.width + horizontalGap) - CGFloat(page * 32),
                           y: available.maxY - size.height - CGFloat(row) * (size.height + verticalGap) - CGFloat(page * 32),
                           width: size.width, height: size.height)
        return PreviewSizing.constrained(frame, to: available)
    }

    func setSourceApplicationActive(_ active: Bool) {
        sourceIsActive = active
        updateVisibility()
    }

    func setTemporarilyHidden(_ hidden: Bool) {
        guard isPresented, hidden != isTemporarilyHidden else { return }
        isTemporarilyHidden = hidden
        updateVisibility()
        onVisibilityChange?()
    }

    private func updateVisibility() {
        guard isPresented else { return }
        if sourceIsActive || isTemporarilyHidden {
            setChromeVisible(false)
            panel.orderOut(nil)
            stopPointerTracking()
        } else if !panel.isVisible {
            panel.orderFrontRegardless()
            layoutControls()
            startPointerTracking()
        }
    }

    private func startPointerTracking() {
        guard tracksPointer, pointerTimer == nil else { return }
        // Reading mouseLocation requires no Accessibility/Input Monitoring access.
        // Tracking areas don't fire on a click-through window.
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            MainActor.assumeIsolated {
                self.updateHover(at: NSEvent.mouseLocation, pressedButtons: NSEvent.pressedMouseButtons)
            }
        }
        timer.tolerance = 0.015
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
        isTrackingPointer = true
        updateHover(at: NSEvent.mouseLocation, pressedButtons: NSEvent.pressedMouseButtons)
    }

    private func stopPointerTracking() {
        pointerTimer?.invalidate()
        pointerTimer = nil
        isTrackingPointer = false
    }

    func updateHover(at point: CGPoint, pressedButtons: Int = 0, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard isPresented, panel.isVisible, !sourceIsActive, !isTemporarilyHidden else { setChromeVisible(false); return }
        let inside = containsHoverPoint(point)
        if isManipulating || (isChromeVisible && pressedButtons != 0) { return }
        if inside, shouldRevealControls?(point) == false { setChromeVisible(false); return }
        if inside {
            lastHoverTime = now
            if pressedButtons == 0 { setChromeVisible(true) }
        } else if now - lastHoverTime >= 0.18 {
            setChromeVisible(false)
        }
    }

    func containsHoverPoint(_ point: CGPoint) -> Bool {
        guard panel.isVisible else { return false }
        if panel.frame.contains(point) { return true }
        guard isChromeVisible else { return false }
        // These are logical hover corridors only; they never intercept clicks.
        let toolbarBridge = CGRect(x: max(panel.frame.minX, controlsPanel.frame.minX), y: panel.frame.maxY,
                                   width: max(0, min(panel.frame.maxX, controlsPanel.frame.maxX) - max(panel.frame.minX, controlsPanel.frame.minX)),
                                   height: PreviewChromeLayout.toolbarGap)
        let resizeBridge = CGRect(x: panel.frame.maxX, y: panel.frame.minY,
                                  width: PreviewChromeLayout.resizeGap, height: min(panel.frame.height, resizePanel.frame.height))
        return controlsPanel.frame.contains(point) || resizePanel.frame.contains(point) || toolbarBridge.contains(point) || resizeBridge.contains(point)
    }

    func setChromeVisible(_ visible: Bool) {
        let show = visible && isPresented && panel.isVisible && !sourceIsActive && !isTemporarilyHidden
        guard show != isChromeVisible else { return }
        isChromeVisible = show
        if show {
            layoutControls()
            controlsPanel.orderFrontRegardless()
            resizePanel.orderFrontRegardless()
        } else {
            controlsPanel.orderOut(nil)
            resizePanel.orderOut(nil)
        }
    }

    private func layoutControls() {
        let frames = PreviewChromeLayout.frames(picture: panel.frame, controls: controlsPanel.frame.size, resize: resizePanel.frame.size, screen: screenFrame)
        controlsPanel.setFrameOrigin(frames.toolbar.origin)
        resizePanel.setFrameOrigin(frames.handle.origin)
    }

    private func configureHandle(_ handle: PreviewHandle, resizing: Bool) {
        handle.onBegin = { [weak self] in
            guard let self else { return }
            self.isManipulating = true
            self.manipulationFrame = self.panel.frame
        }
        handle.onDrag = { [weak self] delta in
            guard let self else { return }
            let initial = self.manipulationFrame
            if resizing {
                let ratio = PreviewSizing.aspectRatio(self.sourceSize)
                let horizontal = delta.x
                let vertical = -delta.y * ratio
                let change = abs(horizontal) >= abs(vertical) ? horizontal : vertical
                let size = PreviewSizing.size(source: self.sourceSize, preferredWidth: initial.width + change, available: self.availableFrame.size)
                let frame = CGRect(x: initial.minX, y: initial.maxY - size.height, width: size.width, height: size.height)
                self.panel.setFrame(PreviewSizing.constrained(frame, to: self.availableFrame), display: true)
            } else {
                let frame = initial.offsetBy(dx: delta.x, dy: delta.y)
                let targetScreen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) }
                let available = targetScreen.map { self.contentArea(in: $0.visibleFrame.insetBy(dx: 16, dy: 16)) } ?? self.availableFrame
                self.panel.setFrame(PreviewSizing.constrained(frame, to: available), display: true)
            }
            self.layoutControls()
        }
        handle.onEnd = { [weak self] in
            guard let self else { return }
            self.isManipulating = false
            self.keepOnScreen()
            self.saveFrame()
        }
    }

    private func keepOnScreen() {
        guard isPresented else { return }
        panel.setFrame(PreviewSizing.constrained(panel.frame, to: availableFrame), display: true)
        layoutControls()
    }

    private func saveFrame() { defaults.set(NSStringFromRect(panel.frame), forKey: preferenceKey("previewFrame")) }

    func setOpacity(_ value: Double) {
        opacity = value.isFinite ? min(1, max(0.3, value)) : 1
        panel.alphaValue = opacity
        opacitySlider.doubleValue = opacity
        opacityLabel.stringValue = "\(Int((opacity * 100).rounded()))%"
        defaults.set(opacity, forKey: preferenceKey("previewOpacity"))
    }

    @objc private func opacityChanged() { setOpacity(opacitySlider.doubleValue) }
    @objc private func returnToSource() {
        guard canActivateSource, state == .live || state == .paused else { return }
        onActivateSource?()
    }
    @objc private func stopPinning() { close() }
    @objc private func hidePreview() { setTemporarilyHidden(true) }
    @objc private func chooseWindow() { onChooseWindow?() }

    func setState(_ state: CaptureState) {
        self.state = state
        updateSourceAction()
        switch state {
        case .idle, .live: statusBackground.isHidden = true
        case .waiting: message.stringValue = NSLocalizedString("Opening preview…", comment: "Waiting state"); statusBackground.isHidden = false
        case .paused: message.stringValue = NSLocalizedString("Preview paused", comment: "Paused state"); statusBackground.isHidden = false
        case .unavailable:
            message.stringValue = NSLocalizedString("Preview ended. Hover to choose another window.", comment: "Ended state")
            statusBackground.isHidden = false
        }
    }

    func setChoosing(_ choosing: Bool) { chooseButton.isEnabled = !choosing }
    private func updateSourceAction() { returnButton.isEnabled = canActivateSource && (state == .live || state == .paused) }
    func display(_ sample: CMSampleBuffer) { videoView.display(sample) }
    func clear() { videoView.clear() }

    func close() {
        guard isPresented else { return }
        isPresented = false
        sourceIsActive = false
        isTemporarilyHidden = false
        isManipulating = false
        setChromeVisible(false)
        stopPointerTracking()
        panel.orderOut(nil)
        clear()
        onClose?()
    }
    func windowWillClose(_ notification: Notification) { close() }
    func windowDidMove(_ notification: Notification) { layoutControls() }
    func windowDidResize(_ notification: Notification) { layoutControls(); notifyResize() }
    func windowDidChangeBackingProperties(_ notification: Notification) { notifyResize() }
    private func notifyResize() { onResize?(videoView.bounds.size, panel.backingScaleFactor) }
}
