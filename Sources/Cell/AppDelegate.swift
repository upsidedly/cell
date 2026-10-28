import AppKit
import CellCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private let model = CellModel()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var popoverAnchor: NSPanel?
    private var settingsWindow: NSWindow?
    private var openingRefresh: Task<Void, Never>?
    private var outsideClickMonitor: Any?
    private var localEventMonitor: Any?
    private var menuTrackingObservers: [NSObjectProtocol] = []
    private var menuTrackingCount = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "dev.matthew.cell")
            .filter({ $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }).isEmpty else {
            NSApp.terminate(nil); return
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "Cell"
        item.isVisible = true
        item.behavior = []
        item.button?.target = self
        item.button?.action = #selector(pressed)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.setAccessibilityIdentifier("cell-menu-bar")
        statusItem = item
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.delegate = self
        let host = NSHostingController(rootView: PopoverView(model: model))
        popover.contentViewController = host
        popover.contentSize = host.view.fittingSize
        model.onUpdate = { [weak self] in self?.updateStatus() }
        model.onSettings = { [weak self] in self?.showSettings() }
        installMenus()
        updateStatus()
        model.start()
        if CommandLine.arguments.contains("--settings") {
            showSettings()
        } else if CommandLine.arguments.contains("--popup") || !UserDefaults.standard.bool(forKey: "hasLaunched") {
            openPopover()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        removePopoverMonitors()
        openingRefresh?.cancel(); model.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openPopover(); return false
    }

    private func updateStatus() {
        guard let button = statusItem?.button else { return }
        let percentage = model.sample?.percent.map { "\($0)%" } ?? "—"
        button.effectiveAppearance.performAsCurrentDrawingAppearance {
            button.image = BatteryMenuImage.make(for: model.sample)
        }
        button.imagePosition = model.percentagePosition == .left ? .imageTrailing : .imageLeading
        button.font = .menuBarFont(ofSize: 0)
        button.title = model.showsPercentage
            ? (model.percentagePosition == .left ? percentage + " " : " " + percentage) : ""
        button.toolTip = "Cell · " + percentage + " · Mac " + CellModel.watts(model.sample?.macWatts)
        button.setAccessibilityLabel("Cell, " + percentage + ", " + model.batteryStatus)
        if popover.isShown, let view = popover.contentViewController?.view {
            popover.contentSize = view.fittingSize
        }
    }

    @objc private func pressed() {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu(); return }
        if popover.isShown { popover.performClose(nil) } else { openPopover() }
    }

    private func openPopover() {
        guard let button = statusItem?.button else { return }
        openingRefresh?.cancel()
        model.popupOpen = true
        popover.contentSize = popover.contentViewController?.view.fittingSize ?? NSSize(width: 310, height: 250)
        let anchor = presentationAnchor(for: button)
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        popover.contentViewController?.view.window?.title = "Cell"
        popover.contentViewController?.view.window?.makeKey()
        installPopoverMonitors()
        UserDefaults.standard.set(true, forKey: "hasLaunched")
        openingRefresh = Task { [weak self] in
            guard let self else { return }
            await self.model.refresh()
        }
    }

    private func presentationAnchor(for button: NSStatusBarButton) -> NSView {
        if let window = button.window, window.frame.height > 0 { return button }
        // macOS 27's MenuBarAgent can host a status button in a zero-height
        // proxy window. A transparent, non-interactive anchor keeps the native
        // popover usable without reading other apps' Accessibility trees.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let menuHeight = max(NSStatusBar.system.thickness, frame.maxY - (screen?.visibleFrame.maxY ?? frame.maxY))
        let isMenuClick = mouse.y >= frame.maxY - menuHeight
        let x = isMenuClick ? mouse.x : frame.maxX - 150
        let rect = NSRect(x: min(max(x - 8, frame.minX + 8), frame.maxX - 24), y: frame.maxY - menuHeight, width: 16, height: menuHeight)
        let panel = popoverAnchor ?? NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Cell Anchor"
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = false; panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSView(frame: NSRect(origin: .zero, size: rect.size))
        panel.setFrame(rect, display: false)
        panel.orderFrontRegardless()
        popoverAnchor = panel
        return panel.contentView ?? button
    }

    func popoverDidClose(_ notification: Notification) {
        removePopoverMonitors()
        openingRefresh?.cancel(); openingRefresh = nil
        model.popupOpen = false
        popoverAnchor?.orderOut(nil)
    }

    private func installPopoverMonitors() {
        removePopoverMonitors()
        // MenuBarAgent's proxy anchor does not reliably participate in native
        // transient dismissal. Observe clicks without consuming their delivery.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissPopoverForOutsideClick() }
        }
        let center = NotificationCenter.default
        menuTrackingObservers = [
            center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.menuTrackingCount += 1 }
            },
            center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.menuTrackingCount = max(0, self.menuTrackingCount - 1)
                }
            }
        ]
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                guard let self, self.popover.isShown, self.menuTrackingCount == 0 else { return false }
                if event.type == .keyDown {
                    if event.keyCode == 53 {
                        self.popover.performClose(nil)
                        return true
                    }
                    return false
                }
                if event.window != self.popover.contentViewController?.view.window,
                   event.window != self.statusItem?.button?.window {
                    self.dismissPopoverForOutsideClick()
                }
                return false
            }
            return handled ? nil : event
        }
    }

    private func dismissPopoverForOutsideClick() {
        guard popover.isShown else { return }
        let point = NSEvent.mouseLocation
        if popover.contentViewController?.view.window?.frame.contains(point) == true { return }
        if let button = statusItem?.button, let window = button.window, window.frame.height > 0,
           window.convertToScreen(button.convert(button.bounds, to: nil)).contains(point) { return }
        // The opening click identifies the proxy-hosted status item's anchor.
        if popoverAnchor?.frame.contains(point) == true { return }
        popover.performClose(nil)
    }

    private func removePopoverMonitors() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let localEventMonitor { NSEvent.removeMonitor(localEventMonitor) }
        outsideClickMonitor = nil; localEventMonitor = nil
        for observer in menuTrackingObservers { NotificationCenter.default.removeObserver(observer) }
        menuTrackingObservers.removeAll()
        menuTrackingCount = 0
    }

    @objc private func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Cell Settings"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView(model: model))
            window.setContentSize(window.contentViewController?.view.fittingSize ?? NSSize(width: 340, height: 170))
            settingsWindow = window
        }
        settingsWindow?.center()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func showPowerFlow() { openPopover() }

    private func showMenu() {
        guard let item = statusItem else { return }
        let menu = NSMenu()
        let settings = menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit Cell", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    private func installMenus() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let submenu = NSMenu()
        let power = submenu.addItem(withTitle: "Show Power Flow", action: #selector(showPowerFlow), keyEquivalent: "1")
        power.target = self
        let settings = submenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        submenu.addItem(.separator())
        let quit = submenu.addItem(withTitle: "Quit Cell", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        appItem.submenu = submenu
        menu.addItem(appItem)
        NSApp.mainMenu = menu
    }
}

@main
enum CellApplication {
    @MainActor static func main() {
        if CommandLine.arguments.contains(where: { ["--telemetry", "--charge-status", "--verify-charge-controls"].contains($0) }) {
            let command = Task { await runCommands() }
            withExtendedLifetime(command) { dispatchMain() }
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    @MainActor private static func runCommands() async {
        let args = CommandLine.arguments
        if args.contains("--telemetry") {
            do {
                let sample = try await PowerReader().sample()
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                print(String(decoding: try encoder.encode(sample), as: UTF8.self)); exit(0)
            } catch { print(error.localizedDescription); exit(1) }
        }
        if args.contains("--charge-status") || args.contains("--verify-charge-controls") {
            let service = ChargeService()
            do {
                let original = try await service.read()
                if args.contains("--verify-charge-controls") {
                    let temporary = original.availableLimits.first(where: { $0 != original.limit }) ?? original.limit
                    do {
                        let changed = try await service.set(temporary)
                        guard changed.limit == temporary else { throw CocoaError(.validationMissingMandatoryProperty) }
                        let restored = try await service.set(original.limit)
                        guard restored == original else { throw CocoaError(.validationMissingMandatoryProperty) }
                        print("Native limit changed to \(temporary)% and restored to \(original.limit)%.")
                    } catch {
                        do { _ = try await service.set(original.limit) }
                        catch { print("Restoration failed: \(error.localizedDescription)"); exit(2) }
                        throw error
                    }
                }
                print(String(decoding: try JSONEncoder().encode(original), as: UTF8.self)); exit(0)
            } catch { print(error.localizedDescription); exit(1) }
        }
        exit(1)
    }
}
