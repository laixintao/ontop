import AppKit
@preconcurrency import CoreMedia
@preconcurrency import ScreenCaptureKit

@MainActor
protocol WindowCapture: AnyObject {
    var state: CaptureState { get }
    var sourceApplicationProcessIdentifier: pid_t? { get }
    var sourceWindowIdentifier: CGWindowID? { get }
    var streamForPicker: SCStream? { get }
    var streamIdentifier: ObjectIdentifier? { get }
    var onFrame: ((CMSampleBuffer) -> Void)? { get set }
    var onReset: (() -> Void)? { get set }
    var onSelection: ((CGSize, String?, Bool) -> Void)? { get set }
    var onStateChange: ((CaptureState) -> Void)? { get set }
    func select(_ filter: SCContentFilter)
    func resize(to size: CGSize, scale: CGFloat)
    @discardableResult func activateSourceApplication() -> Bool
    func stop()
    func shutdown() async
}

@MainActor
final class PinnedWindow {
    let id = UUID()
    let slot: Int
    let capture: any WindowCapture
    let preview: PreviewPanelController
    var title = NSLocalizedString("Window", comment: "Unnamed preview")

    init(slot: Int, capture: any WindowCapture, preview: PreviewPanelController) {
        self.slot = slot
        self.capture = capture
        self.preview = preview
    }
}

/// The sole picker observer routes each stream to its own capture and preview.
/// Stopping one stream must not disable selection for the others.
@MainActor
final class PinManager: NSObject {
    var onChange: (() -> Void)?
    var onPickerFailure: ((Error) -> Void)?
    private(set) var windows: [PinnedWindow] = []
    private(set) var isChoosing = false
    private let picker = SCContentSharingPicker.shared
    private let defaults: UserDefaults
    private let tracksPointer: Bool
    private let captureFactory: () -> any WindowCapture
    private var replacementID: UUID?
    private var replacementStreamID: ObjectIdentifier?
    private var isShuttingDown = false
    private var frontmostPID: pid_t?
    private var teardowns: [UUID: Task<Void, Never>] = [:]

    init(defaults: UserDefaults = .standard, tracksPointer: Bool = true,
         captureFactory: @escaping () -> any WindowCapture = { CaptureController() }) {
        self.defaults = defaults
        self.tracksPointer = tracksPointer
        self.captureFactory = captureFactory
        super.init()
        var configuration = SCContentSharingPickerConfiguration()
        // Repeat Add Window to authorize independent streams, including via
        // macOS's sharing menu. Never combine sources into one display canvas.
        configuration.allowedPickerModes = [.singleWindow]
        configuration.excludedBundleIDs = [Bundle.main.bundleIdentifier ?? "app.ontop.OnTop"]
        configuration.allowsChangingSelectedContent = true
        picker.defaultConfiguration = configuration
        picker.maximumStreamCount = nil
        picker.add(self)
    }

    func window(id: UUID) -> PinnedWindow? { windows.first { $0.id == id } }

    func chooseWindow(replacing id: UUID? = nil) {
        guard beginSelection(replacing: id) else { return }
        if let id, let stream = window(id: id)?.capture.streamForPicker {
            picker.present(for: stream, using: .window)
        } else {
            picker.present(using: .window)
        }
    }

    @discardableResult
    func beginSelection(replacing id: UUID? = nil) -> Bool {
        guard !isChoosing, !isShuttingDown else { return false }
        if let id, window(id: id) == nil { return false }
        replacementID = id
        replacementStreamID = id.flatMap { window(id: $0)?.capture.streamIdentifier }
        isChoosing = true
        picker.isActive = true
        updateChoosing()
        return true
    }

    private func updateChoosing() {
        for window in windows { window.preview.setChoosing(isChoosing) }
        onChange?()
    }

    /// Nil means a new share, except when replacing an ended preview. Non-nil
    /// callbacks only update the exact stream that the picker is referring to.
    func destination(for streamID: ObjectIdentifier?, sourceWindowID: CGWindowID? = nil) -> PinnedWindow? {
        guard !isShuttingDown, picker.isActive else { return nil }
        let target: PinnedWindow?
        if let streamID {
            guard let existing = windows.first(where: { $0.capture.streamIdentifier == streamID }) else {
                if streamID == replacementStreamID { cancelSelection() }
                return nil
            }
            target = existing
        } else if let replacementID {
            guard let existing = window(id: replacementID) else {
                cancelSelection()
                return nil
            }
            target = existing
        } else {
            target = nil
        }
        replacementID = nil
        replacementStreamID = nil
        isChoosing = false
        let destination: PinnedWindow
        if let sourceWindowID, let duplicate = windows.first(where: { $0.capture.sourceWindowIdentifier == sourceWindowID }) {
            if let target, target !== duplicate { stop(id: target.id) }
            destination = duplicate
        } else {
            destination = target ?? makeWindow()
        }
        updateChoosing()
        return destination
    }

    func cancelSelection(for streamID: ObjectIdentifier? = nil) {
        if let streamID, streamID != replacementStreamID, !windows.contains(where: { $0.capture.streamIdentifier == streamID }) { return }
        replacementID = nil
        replacementStreamID = nil
        isChoosing = false
        if windows.isEmpty { picker.isActive = false }
        updateChoosing()
    }

    private func makeWindow() -> PinnedWindow {
        let occupied = Set(windows.map(\.slot))
        var slot = 0
        while occupied.contains(slot) { slot += 1 }
        let preview = PreviewPanelController(defaults: defaults, tracksPointer: tracksPointer, slot: slot)
        let capture = captureFactory()
        let window = PinnedWindow(slot: slot, capture: capture, preview: preview)
        windows.append(window)
        preview.onChooseWindow = { [weak self, weak window] in
            guard let window else { return }
            self?.chooseWindow(replacing: window.id)
        }
        preview.onActivateSource = { [weak capture] in capture?.activateSourceApplication() }
        preview.onClose = { [weak self, weak window] in
            guard let window else { return }
            self?.stop(id: window.id)
        }
        preview.onResize = { [weak capture] size, scale in capture?.resize(to: size, scale: scale) }
        preview.shouldRevealControls = { [weak self, weak window] point in
            guard let self, let window else { return false }
            return hoverOwner(at: point) === window
        }
        capture.onFrame = { [weak preview] in preview?.display($0) }
        capture.onReset = { [weak preview] in preview?.clear() }
        capture.onSelection = { [weak self, weak window] size, title, canActivate in
            guard let self, let window else { return }
            window.title = title ?? NSLocalizedString("Window", comment: "Unnamed preview")
            refreshVisibility()
            window.preview.show(sourceSize: size, title: title, canActivateSource: canActivate)
            onChange?()
        }
        capture.onStateChange = { [weak self, weak preview] state in
            preview?.setState(state)
            self?.refreshVisibility()
            self?.onChange?()
        }
        return window
    }

    func hoverOwner(at point: CGPoint) -> PinnedWindow? {
        // NSApp.orderedWindows omits panels that opt out of window cycling.
        // AppKit's window-number list includes those panels in actual z-order.
        let candidates = windows.flatMap { window in
            [window.preview.panel, window.preview.controlsPanel, window.preview.resizePanel]
                .filter { $0.isVisible && $0.frame.contains(point) }
                .map { (panel: $0, owner: window) }
        }
        guard let first = candidates.first else { return nil }
        if candidates.allSatisfy({ $0.owner === first.owner }) { return first.owner }
        // Only query stacking when previews overlap; only our own window IDs
        // are needed, never other apps' metadata, pixels, or event monitoring.
        for number in NSWindow.windowNumbers(options: []) ?? [] {
            if let candidate = candidates.first(where: { $0.panel.windowNumber == number.intValue }) {
                return candidate.owner
            }
        }
        return nil
    }

    func setFrontmostApplication(_ processID: pid_t?) {
        frontmostPID = processID
        refreshVisibility()
        onChange?()
    }

    private func refreshVisibility() {
        guard !isShuttingDown else { return }
        for window in windows {
            let pid = window.capture.sourceApplicationProcessIdentifier
            window.preview.setSourceApplicationActive(pid != nil && pid == frontmostPID)
        }
    }

    func stop(id: UUID) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        let window = windows.remove(at: index)
        window.preview.onClose = nil
        window.preview.close()
        let capture = window.capture
        capture.onFrame = nil
        capture.onReset = nil
        capture.onSelection = nil
        capture.onStateChange = nil
        capture.stop()
        teardowns[id] = Task { @MainActor [weak self] in
            await capture.shutdown()
            self?.teardowns[id] = nil
        }
        if windows.isEmpty && !isChoosing { picker.isActive = false }
        onChange?()
    }

    func stopAll() {
        picker.isActive = false
        replacementID = nil
        replacementStreamID = nil
        isChoosing = false
        for window in windows { stop(id: window.id) }
        updateChoosing()
    }

    func shutdown() async {
        isShuttingDown = true
        stopAll()
        picker.remove(self)
        for task in Array(teardowns.values) { await task.value }
    }
}

extension PinManager: SCContentSharingPickerObserver {
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        let streamID = stream.map(ObjectIdentifier.init)
        Task { @MainActor [weak self] in
            guard let self, filter.style == .window else { return }
            var windowID: CGWindowID?
            if #available(macOS 15.2, *) { windowID = filter.includedWindows.first?.windowID }
            destination(for: streamID, sourceWindowID: windowID)?.capture.select(filter)
        }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        let streamID = stream.map(ObjectIdentifier.init)
        Task { @MainActor [weak self] in self?.cancelSelection(for: streamID) }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor [weak self] in
            guard let self, !isShuttingDown else { return }
            cancelSelection()
            onPickerFailure?(error)
        }
    }
}
