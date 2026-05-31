@preconcurrency import AppKit

@MainActor
final class SleepWakeObserver {
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    init(manager: TunnelManager) {
        let center = NSWorkspace.shared.notificationCenter
        sleepObserver = center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                manager.handleSleep()
            }
        }
        wakeObserver = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                manager.handleWake()
            }
        }
    }
}