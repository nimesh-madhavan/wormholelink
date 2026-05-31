import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let manager = TunnelManager()
    private let logger = AppLogger.shared

    private var statusBarController: StatusBarController?
    private var preferencesWindowController: PreferencesWindowController?
    private var sleepWakeObserver: SleepWakeObserver?
    private var isPreferencesWindowVisible = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Application finished launching", category: .app)
        NSApp.applicationIconImage = WormholeIcon.applicationIcon()
        installMainMenu()
        NSApp.setActivationPolicy(.accessory)

        preferencesWindowController = PreferencesWindowController(manager: manager)
        preferencesWindowController?.visibilityDidChange = { [weak self] isVisible in
            self?.handlePreferencesVisibilityChange(isVisible)
        }
        statusBarController = StatusBarController(
            manager: manager,
            preferencesAction: { [weak self] in
                self?.showPreferencesWindow()
            },
            openDebugLogAction: { [weak self] in
                self?.openDebugLog()
            },
            quitAction: {
                NSApp.terminate(nil)
            }
        )
        sleepWakeObserver = SleepWakeObserver(manager: manager)
        manager.startAutoLaunchTunnelsIfNeeded()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        logger.info("Application termination requested", category: .app)
        manager.shutdownForApplicationExit()
        logger.info("Application termination cleanup complete", category: .app)
        return .terminateNow
    }

    func showPreferencesWindow() {
        logger.debug("Opening preferences window", category: .app)
        updateActivationPolicy(forPreferencesWindowVisible: true)
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindowController?.showWindow(nil)
        preferencesWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    private func handlePreferencesVisibilityChange(_ isVisible: Bool) {
        isPreferencesWindowVisible = isVisible
        updateActivationPolicy(forPreferencesWindowVisible: isVisible)
    }

    private func updateActivationPolicy(forPreferencesWindowVisible isVisible: Bool) {
        let desiredPolicy: NSApplication.ActivationPolicy = isVisible ? .regular : .accessory
        guard NSApp.activationPolicy() != desiredPolicy else {
            return
        }

        NSApp.setActivationPolicy(desiredPolicy)
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About WormholeLink", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let preferencesItem = NSMenuItem(title: "Preferences...", action: #selector(showPreferencesFromMenu(_:)), keyEquivalent: ",")
        preferencesItem.target = self
        appMenu.addItem(preferencesItem)
        let openLogItem = NSMenuItem(title: "Open Debug Log", action: #selector(openDebugLogFromMenu(_:)), keyEquivalent: "")
        openLogItem.target = self
        appMenu.addItem(openLogItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide WormholeLink", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h").keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit WormholeLink", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    @objc private func showPreferencesFromMenu(_ sender: Any?) {
        showPreferencesWindow()
    }

    @objc private func openDebugLogFromMenu(_ sender: Any?) {
        openDebugLog()
    }

    private func openDebugLog() {
        logger.info("Opening debug log at \(logger.logFileURL.path)", category: .app)
        logger.openLogFile()
    }
}

@main
struct WormholeLinkMain {
    static func main() {
        let application = NSApplication.shared
        let appDelegate = AppDelegate()
        application.delegate = appDelegate
        application.run()
    }
}