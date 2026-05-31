import AppKit
import SwiftUI

@MainActor
final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    var visibilityDidChange: ((Bool) -> Void)?

    init(manager: TunnelManager) {
        let view = PreferencesRootView(manager: manager)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "WormholeLink"
        window.setContentSize(NSSize(width: 980, height: 640))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        visibilityDidChange?(true)
    }

    func windowWillClose(_ notification: Notification) {
        visibilityDidChange?(false)
    }
}