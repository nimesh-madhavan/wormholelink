import AppKit
import Combine

@MainActor
final class StatusBarController: NSObject {
    private let manager: TunnelManager
    private let preferencesAction: () -> Void
    private let openDebugLogAction: () -> Void
    private let quitAction: () -> Void
    private let statusItem: NSStatusItem
    private var cancellables: Set<AnyCancellable> = []
    private var pulseTimer: Timer?
    private var animationFrame = 0

    init(manager: TunnelManager, preferencesAction: @escaping () -> Void, openDebugLogAction: @escaping () -> Void, quitAction: @escaping () -> Void) {
        self.manager = manager
        self.preferencesAction = preferencesAction
        self.openDebugLogAction = openDebugLogAction
        self.quitAction = quitAction
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        manager.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.rebuildMenu()
                self?.refreshIcon()
            }
            .store(in: &cancellables)

        rebuildMenu()
        refreshIcon()
    }

    @objc private func connectTunnel(_ sender: NSMenuItem) {
        guard let rawID = sender.representedObject as? String,
              let tunnelID = UUID(uuidString: rawID) else {
            return
        }

        manager.connectTunnel(tunnelID)
    }

    @objc private func disconnectTunnel(_ sender: NSMenuItem) {
        guard let rawID = sender.representedObject as? String,
              let tunnelID = UUID(uuidString: rawID) else {
            return
        }

        manager.disconnectTunnel(tunnelID)
    }

    @objc private func connectAll(_ sender: Any?) {
        manager.connectAll()
    }

    @objc private func disconnectAll(_ sender: Any?) {
        manager.disconnectAll()
    }

    @objc private func openPreferences(_ sender: Any?) {
        preferencesAction()
    }

    @objc private func openDebugLog(_ sender: Any?) {
        openDebugLogAction()
    }

    @objc private func quit(_ sender: Any?) {
        quitAction()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        for tunnel in manager.menuBarTunnels {
            let state = manager.runtimeState(for: tunnel.id)
            let item = NSMenuItem(
                title: "\(state.menuSymbol) \(tunnel.name)    [\(state.label)]",
                action: state.phase == .connected ? #selector(disconnectTunnel(_:)) : #selector(connectTunnel(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = tunnel.id.uuidString
            menu.addItem(item)
        }

        if !manager.menuBarTunnels.isEmpty {
            menu.addItem(.separator())
        }

        let connectAllItem = NSMenuItem(title: "Connect All", action: #selector(connectAll(_:)), keyEquivalent: "")
        connectAllItem.target = self
        menu.addItem(connectAllItem)

        let disconnectAllItem = NSMenuItem(title: "Disconnect All", action: #selector(disconnectAll(_:)), keyEquivalent: "")
        disconnectAllItem.target = self
        menu.addItem(disconnectAllItem)

        menu.addItem(.separator())

        let preferencesItem = NSMenuItem(title: "Preferences...", action: #selector(openPreferences(_:)), keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        let openDebugLogItem = NSMenuItem(title: "Open Debug Log", action: #selector(openDebugLog(_:)), keyEquivalent: "")
        openDebugLogItem.target = self
        menu.addItem(openDebugLogItem)

        let quitItem = NSMenuItem(title: "Quit WormholeLink", action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func refreshIcon() {
        let states = manager.menuBarTunnels.map { manager.runtimeState(for: $0.id) }
        let activeCount = states.filter {
            if case .connected = $0.phase {
                return true
            }
            return false
        }.count
        let isConnecting = states.contains {
            if case .connecting = $0.phase {
                return true
            }
            if case .reconnecting = $0.phase {
                return true
            }
            return false
        }

        if isConnecting {
            if pulseTimer == nil {
                pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.16, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        self?.animationFrame = ((self?.animationFrame ?? 0) + 1) % 12
                        self?.applyStatusImage(activeCount: activeCount, isConnecting: true)
                    }
                }
            }
        } else {
            pulseTimer?.invalidate()
            pulseTimer = nil
            animationFrame = 0
        }

        applyStatusImage(activeCount: activeCount, isConnecting: isConnecting)
    }

    private func applyStatusImage(activeCount: Int, isConnecting: Bool) {
        statusItem.button?.image = WormholeIcon.statusBarImage(
            activeCount: activeCount,
            isConnecting: isConnecting,
            animationFrame: animationFrame
        )
    }
}