import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var selectItem: NSMenuItem!
    private var stopItem: NSMenuItem!
    private var resetItem: NSMenuItem!
    private var opacityItems: [NSMenuItem] = []
    private let preview = PreviewPanelController()
    private let capture = CaptureController()
    private var isQuitting = false
    private var activationObserver: NSObjectProtocol?
    private var frontmostApplicationPID: pid_t?

    func applicationDidFinishLaunching(_ notification: Notification) {
        createMenu()
        observeApplicationActivation()

        preview.onChooseWindow = { [weak self] in self?.capture.chooseWindow() }
        preview.onActivateSource = { [weak self] in self?.capture.activateSourceApplication() }
        preview.onClose = { [weak self] in self?.capture.stop() }
        preview.onResize = { [weak self] size, scale in
            self?.capture.resize(to: size, scale: scale)
        }
        capture.onFrame = { [weak self] frame in self?.preview.display(frame) }
        capture.onReset = { [weak self] in self?.preview.clear() }
        capture.onSelection = { [weak self] size, title, canActivateSource in
            guard let self else { return }
            refreshPreviewVisibility()
            preview.show(sourceSize: size, title: title, canActivateSource: canActivateSource)
        }
        capture.onStateChange = { [weak self] state in
            guard let self else { return }
            preview.setState(state)
            stopItem.isEnabled = state != .idle
            resetItem.isEnabled = state != .idle
            refreshPreviewVisibility()
        }
        capture.onPickerVisibilityChange = { [weak self] isChoosing in
            self?.selectItem.isEnabled = !isChoosing
            self?.preview.setChoosing(isChoosing)
        }
        capture.onPickerFailure = { error in
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Couldn't open the window picker", comment: "Picker error")
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: NSLocalizedString("OK", comment: "Dismiss alert"))
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }

        // Wait until the menu bar item is installed before presenting system UI.
        DispatchQueue.main.async { [weak self] in self?.capture.chooseWindow() }
    }

    private func observeApplicationActivation() {
        let workspace = NSWorkspace.shared
        frontmostApplicationPID = workspace.frontmostApplication?.processIdentifier
        activationObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let processID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                guard let self else { return }
                // Use the notification's app: frontmostApplication may still
                // describe the previous app during an activation transition.
                self.frontmostApplicationPID = processID ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
                self.refreshPreviewVisibility()
            }
        }
    }

    private func refreshPreviewVisibility() {
        guard !isQuitting else { return }
        let sourcePID = capture.sourceApplicationProcessIdentifier
        let sourceIsActive = sourcePID != nil && sourcePID == frontmostApplicationPID
        preview.setSourceApplicationActive(sourceIsActive)
        if capture.state == .idle {
            statusItem.button?.toolTip = NSLocalizedString("OnTop — pin a window preview", comment: "Menu bar tooltip")
        } else if sourceIsActive {
            statusItem.button?.toolTip = NSLocalizedString("OnTop — preview returns when you switch apps", comment: "Menu bar tooltip")
        } else {
            statusItem.button?.toolTip = NSLocalizedString("OnTop — preview is open", comment: "Menu bar tooltip")
        }
    }

    private func createMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "OnTop")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = NSLocalizedString("OnTop — pin a window preview", comment: "Menu bar tooltip")

        let menu = NSMenu()
        menu.autoenablesItems = false
        selectItem = NSMenuItem(title: NSLocalizedString("Choose Window…", comment: "Menu item"),
                                action: #selector(chooseWindow), keyEquivalent: "o")
        stopItem = NSMenuItem(title: NSLocalizedString("Stop Pinning", comment: "Menu item"),
                              action: #selector(stopPinning), keyEquivalent: "w")
        stopItem.isEnabled = false
        let quitItem = NSMenuItem(title: NSLocalizedString("Quit OnTop", comment: "Menu item"),
                                  action: #selector(quit), keyEquivalent: "q")
        for item in [selectItem!, stopItem!, quitItem] { item.target = self }
        menu.addItem(selectItem)
        menu.addItem(stopItem)
        resetItem = NSMenuItem(title: NSLocalizedString("Reset Preview Size", comment: "Menu item"),
                               action: #selector(resetPreviewSize), keyEquivalent: "0")
        resetItem.target = self
        resetItem.isEnabled = false
        menu.addItem(resetItem)
        let opacityItem = NSMenuItem(title: NSLocalizedString("Opacity", comment: "Menu item"), action: nil, keyEquivalent: "")
        let opacityMenu = NSMenu()
        opacityMenu.delegate = self
        for percent in [100, 85, 70, 50, 30] {
            let item = NSMenuItem(title: "\(percent)%", action: #selector(changeOpacity(_:)), keyEquivalent: "")
            item.tag = percent
            item.target = self
            opacityMenu.addItem(item)
            opacityItems.append(item)
        }
        opacityItem.submenu = opacityMenu
        menu.addItem(opacityItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    @objc private func chooseWindow() { capture.chooseWindow() }
    @objc private func resetPreviewSize() { preview.resetSize() }
    @objc private func changeOpacity(_ sender: NSMenuItem) { preview.setOpacity(Double(sender.tag) / 100) }
    func menuWillOpen(_ menu: NSMenu) {
        for item in opacityItems { item.state = abs(Double(item.tag) / 100 - preview.opacity) < 0.005 ? .on : .off }
    }

    @objc private func stopPinning() {
        preview.close()
        capture.stop()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !isQuitting { capture.chooseWindow() }
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isQuitting else { return .terminateLater }
        isQuitting = true
        preview.close()
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        Task { @MainActor in
            await capture.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
