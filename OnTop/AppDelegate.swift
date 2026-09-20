import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let pins = PinManager()
    private var isQuitting = false
    private var activationObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "OnTop")
        image?.isTemplate = true
        statusItem.button?.image = image
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        pins.onChange = { [weak self] in self?.updateStatus() }
        pins.onPickerFailure = { error in
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Couldn't open the window picker", comment: "Picker error")
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: NSLocalizedString("OK", comment: "Dismiss alert"))
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        let workspace = NSWorkspace.shared
        pins.setFrontmostApplication(workspace.frontmostApplication?.processIdentifier)
        activationObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let processID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                self?.pins.setFrontmostApplication(processID ?? NSWorkspace.shared.frontmostApplication?.processIdentifier)
            }
        }
        updateStatus()
        menuWillOpen(menu)
        DispatchQueue.main.async { [weak self] in self?.pins.chooseWindow() }
    }

    private func updateStatus() {
        guard !isQuitting else { return }
        if pins.windows.isEmpty {
            statusItem.button?.toolTip = NSLocalizedString("OnTop — pin a window preview", comment: "Menu bar tooltip")
        } else if pins.windows.contains(where: { $0.preview.isTemporarilyHidden }) {
            let hidden = pins.windows.filter { $0.preview.isTemporarilyHidden }.count
            statusItem.button?.toolTip = String(format: NSLocalizedString("OnTop — %d pinned windows, %d hidden", comment: "Menu bar tooltip"), pins.windows.count, hidden)
        } else {
            statusItem.button?.toolTip = String(format: NSLocalizedString("OnTop — %d pinned windows", comment: "Menu bar tooltip"), pins.windows.count)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        func item(_ title: String, action: Selector, key: String = "", window: PinnedWindow? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            item.representedObject = window?.id
            return item
        }
        let add = item(NSLocalizedString("Add Window…", comment: "Menu item"), action: #selector(addWindow), key: "o")
        add.isEnabled = !pins.isChoosing
        menu.addItem(add)
        if !pins.windows.isEmpty { menu.addItem(.separator()) }
        for window in pins.windows {
            let title = window.title.count > 52 ? String(window.title.prefix(49)) + "…" : window.title
            let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            parent.toolTip = window.title
            if window.preview.isTemporarilyHidden {
                parent.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: NSLocalizedString("Hidden", comment: "Preview status"))
            }
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            let visibilityTitle = window.preview.isTemporarilyHidden
                ? NSLocalizedString("Show Preview", comment: "Menu item")
                : NSLocalizedString("Hide Preview", comment: "Menu item")
            submenu.addItem(item(visibilityTitle, action: #selector(togglePreviewVisibility(_:)), window: window))
            let back = item(NSLocalizedString("Return to App", comment: "Preview control"), action: #selector(returnToApp(_:)), window: window)
            back.isEnabled = window.capture.sourceApplicationProcessIdentifier != nil && (window.capture.state == .live || window.capture.state == .paused)
            submenu.addItem(back)
            let choose = item(NSLocalizedString("Choose another window", comment: "Preview control"), action: #selector(replaceWindow(_:)), window: window)
            choose.isEnabled = !pins.isChoosing
            submenu.addItem(choose)
            let opacity = NSMenuItem(title: NSLocalizedString("Opacity", comment: "Menu item"), action: nil, keyEquivalent: "")
            let opacityMenu = NSMenu()
            for percent in [100, 85, 70, 50, 30] {
                let option = item("\(percent)%", action: #selector(changeOpacity(_:)), window: window)
                option.tag = percent
                option.state = abs(Double(percent) / 100 - window.preview.opacity) < 0.005 ? .on : .off
                opacityMenu.addItem(option)
            }
            opacity.submenu = opacityMenu
            submenu.addItem(opacity)
            submenu.addItem(item(NSLocalizedString("Reset Preview Size", comment: "Menu item"), action: #selector(resetWindow(_:)), window: window))
            submenu.addItem(.separator())
            submenu.addItem(item(NSLocalizedString("Stop Pinning", comment: "Menu item"), action: #selector(stopWindow(_:)), window: window))
            parent.submenu = submenu
            menu.addItem(parent)
        }
        menu.addItem(.separator())
        let showAll = item(NSLocalizedString("Show All Previews", comment: "Menu item"), action: #selector(showAllPreviews))
        showAll.isEnabled = pins.windows.contains { $0.preview.isTemporarilyHidden }
        menu.addItem(showAll)
        let stop = item(NSLocalizedString("Stop All", comment: "Menu item"), action: #selector(stopAll), key: "w")
        stop.keyEquivalentModifierMask = [.command, .shift]
        stop.isEnabled = !pins.windows.isEmpty || pins.isChoosing
        menu.addItem(stop)
        menu.addItem(item(NSLocalizedString("Quit OnTop", comment: "Menu item"), action: #selector(quit), key: "q"))
    }

    private func window(for sender: NSMenuItem) -> PinnedWindow? {
        (sender.representedObject as? UUID).flatMap { pins.window(id: $0) }
    }
    @objc private func addWindow() { pins.chooseWindow() }
    @objc private func replaceWindow(_ sender: NSMenuItem) {
        if let window = window(for: sender) { pins.chooseWindow(replacing: window.id) }
    }
    @objc private func returnToApp(_ sender: NSMenuItem) { window(for: sender)?.capture.activateSourceApplication() }
    @objc private func resetWindow(_ sender: NSMenuItem) { window(for: sender)?.preview.resetSize() }
    @objc private func changeOpacity(_ sender: NSMenuItem) { window(for: sender)?.preview.setOpacity(Double(sender.tag) / 100) }
    @objc private func stopWindow(_ sender: NSMenuItem) {
        if let window = window(for: sender) { pins.stop(id: window.id) }
    }
    @objc private func stopAll() { pins.stopAll() }
    @objc private func togglePreviewVisibility(_ sender: NSMenuItem) {
        if let window = window(for: sender) { window.preview.setTemporarilyHidden(!window.preview.isTemporarilyHidden) }
    }
    @objc private func showAllPreviews() { pins.showAllPreviews() }
    @objc private func quit() { NSApp.terminate(nil) }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !isQuitting { pins.chooseWindow() }
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isQuitting else { return .terminateLater }
        isQuitting = true
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        Task { @MainActor in
            await pins.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
