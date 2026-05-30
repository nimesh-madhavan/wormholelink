import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

@MainActor
final class TunnelManager: ObservableObject {
    @Published private(set) var tunnels: [Tunnel]
    @Published var appSettings: AppSettings
    @Published private(set) var selection: PreferencesSelection
    @Published private(set) var runtimeStates: [UUID: TunnelRuntimeState]

    let keychainService: KeychainService

    private let persistenceStore: PersistenceStore
    private let proxyService: SystemProxyService
    private var sessions: [UUID: TunnelSession] = [:]
    private let supportsUserNotifications: Bool
    private let logger = AppLogger.shared

    init(
        persistenceStore: PersistenceStore = PersistenceStore(),
        keychainService: KeychainService = KeychainService(),
        proxyService: SystemProxyService = SystemProxyService()
    ) {
        let loadedTunnels = persistenceStore.loadTunnels()
        let loadedSettings = persistenceStore.loadSettings()
        var loadedRuntimeStates: [UUID: TunnelRuntimeState] = [:]
        loadedTunnels.forEach { loadedRuntimeStates[$0.id] = TunnelRuntimeState() }

        self.persistenceStore = persistenceStore
        self.keychainService = keychainService
        self.proxyService = proxyService
        supportsUserNotifications = Self.canUseUserNotifications()
        tunnels = loadedTunnels
        appSettings = loadedSettings
        selection = loadedTunnels.first.map { .tunnel($0.id) } ?? .general
        runtimeStates = loadedRuntimeStates

        logger.info("Loaded \(loadedTunnels.count) tunnels", category: .tunnelManager)

        if appSettings.useNotificationCenter {
            requestNotificationsAuthorization()
        }
    }

    var menuBarTunnels: [Tunnel] {
        tunnels.filter(\.showInMenuBar)
    }

    func tunnel(with id: UUID) -> Tunnel? {
        tunnels.first(where: { $0.id == id })
    }

    func makeTunnelBinding(for tunnelID: UUID) -> Binding<Tunnel> {
        Binding(
            get: {
                self.tunnels.first(where: { $0.id == tunnelID }) ?? Tunnel.makeNew(type: .localForward)
            },
            set: { updated in
                self.updateTunnel(updated)
            }
        )
    }

    func runtimeState(for tunnelID: UUID) -> TunnelRuntimeState {
        runtimeStates[tunnelID] ?? TunnelRuntimeState()
    }

    func setSelection(_ selection: PreferencesSelection) {
        self.selection = selection
    }

    func addTunnel(type: TunnelType) {
        var tunnel = Tunnel.makeNew(type: type)
        tunnel.name = uniqueName(basedOn: tunnel.name)
        tunnels.append(tunnel)
        runtimeStates[tunnel.id] = TunnelRuntimeState()
        selection = .tunnel(tunnel.id)
        logger.info("Added tunnel '\(tunnel.name)' of type \(tunnel.type.displayName)", category: .tunnelManager)
        persistTunnels()
    }

    func duplicateSelectedTunnel() {
        guard case .tunnel(let tunnelID) = selection,
                            let tunnel = tunnel(with: tunnelID) else {
            return
        }

        duplicateTunnel(tunnel)
    }

    func duplicateTunnel(with tunnelID: UUID) {
        guard let tunnel = tunnel(with: tunnelID) else {
            return
        }

        duplicateTunnel(tunnel)
    }

    private func duplicateTunnel(_ sourceTunnel: Tunnel) {
        var tunnel = sourceTunnel

        tunnel.id = UUID()
        tunnel.name = uniqueName(basedOn: "\(tunnel.name) Copy")
        tunnels.append(tunnel)
        runtimeStates[tunnel.id] = TunnelRuntimeState()
        selection = .tunnel(tunnel.id)
        logger.info("Duplicated tunnel as '\(tunnel.name)'", category: .tunnelManager)
        persistTunnels()
    }

    func removeSelectedTunnel() {
        guard case .tunnel(let tunnelID) = selection else {
            return
        }

        removeTunnel(with: tunnelID)
    }

    func removeTunnel(with tunnelID: UUID) {
        guard tunnel(with: tunnelID) != nil else {
            return
        }

        disconnectTunnel(tunnelID)
        tunnels.removeAll { $0.id == tunnelID }
        runtimeStates.removeValue(forKey: tunnelID)
        keychainService.deleteSecret(kind: .tunnelPassword, account: tunnelID.uuidString)
        keychainService.deleteSecret(kind: .tunnelPassphrase, account: tunnelID.uuidString)
        logger.info("Removed tunnel \(tunnelID.uuidString)", category: .tunnelManager)
        selection = tunnels.first.map { .tunnel($0.id) } ?? .general
        persistTunnels()
    }

    func exportSelectedTunnel() {
        guard case .tunnel(let tunnelID) = selection,
              let tunnel = tunnel(with: tunnelID) else {
            return
        }

        exportTunnel(tunnel)
    }

    func exportTunnel(with tunnelID: UUID) {
        guard let tunnel = tunnel(with: tunnelID) else {
            return
        }

        exportTunnel(tunnel)
    }

    private func exportTunnel(_ tunnel: Tunnel) {
        selection = .tunnel(tunnel.id)

        do {
            try export(tunnels: [tunnel], suggestedFileName: "\(tunnel.name).json")
            logger.info("Exported tunnel '\(tunnel.name)'", category: .tunnelManager)
        } catch {
            logger.error("Failed to export tunnel '\(tunnel.name)': \(error.localizedDescription)", category: .tunnelManager)
            presentError(title: "Export Failed", message: error.localizedDescription)
            runtimeStates[tunnel.id] = .init(phase: .failed(error.localizedDescription))
        }
    }

    func exportAllTunnels() {
        guard !tunnels.isEmpty else {
            presentError(title: "Nothing to Export", message: "There are no tunnel configurations to export.")
            return
        }

        do {
            try export(tunnels: tunnels, suggestedFileName: "WormholeLink Connections.json")
            logger.info("Exported all tunnels (\(tunnels.count) total)", category: .tunnelManager)
        } catch {
            logger.error("Failed to export all tunnels: \(error.localizedDescription)", category: .tunnelManager)
            presentError(title: "Export Failed", message: error.localizedDescription)
        }
    }

    func importTunnels() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowsMultipleSelection = true
        openPanel.message = "Import WormholeLink tunnel configuration files. Imported tunnels are merged with your existing connections."

        guard openPanel.runModal() == .OK else {
            return
        }

        do {
            var importedTunnels: [Tunnel] = []
            for url in openPanel.urls {
                let data = try Data(contentsOf: url)
                importedTunnels.append(contentsOf: try decodeImportedTunnels(from: data))
            }

            guard !importedTunnels.isEmpty else {
                return
            }

            let preparedTunnels = importedTunnels.map { imported in
                var tunnel = imported
                tunnel.id = UUID()
                tunnel.name = uniqueName(basedOn: imported.name)
                return tunnel
            }

            tunnels.append(contentsOf: preparedTunnels)
            preparedTunnels.forEach { runtimeStates[$0.id] = TunnelRuntimeState() }
            if let firstImportedTunnel = preparedTunnels.first {
                selection = .tunnel(firstImportedTunnel.id)
            }
            persistTunnels()
            logger.info("Imported \(preparedTunnels.count) tunnel configuration(s); merged with existing tunnels", category: .tunnelManager)
        } catch {
            logger.error("Failed to import tunnel configurations: \(error.localizedDescription)", category: .tunnelManager)
            presentError(title: "Import Failed", message: error.localizedDescription)
        }
    }

    func updateTunnel(_ tunnel: Tunnel) {
        guard let index = tunnels.firstIndex(where: { $0.id == tunnel.id }) else {
            return
        }

        var updated = tunnel
        updated.name = uniqueName(basedOn: tunnel.name, excluding: tunnel.id)
        tunnels[index] = updated
        persistTunnels()
    }

    func updateSettings(_ settings: AppSettings) {
        appSettings = settings
        persistenceStore.saveSettings(settings)
        if settings.useNotificationCenter {
            requestNotificationsAuthorization()
        }
    }

    func saveSecret(_ secret: String, kind: KeychainSecretKind, for tunnelID: UUID) {
        do {
            if secret.isEmpty {
                keychainService.deleteSecret(kind: kind, account: tunnelID.uuidString)
            } else {
                try keychainService.save(secret: secret, kind: kind, account: tunnelID.uuidString)
            }
        } catch {
            runtimeStates[tunnelID] = .init(phase: .failed(error.localizedDescription))
        }
    }

    func secret(kind: KeychainSecretKind, for tunnelID: UUID) -> String {
        do {
            return try keychainService.readSecret(kind: kind, account: tunnelID.uuidString) ?? ""
        } catch {
            return ""
        }
    }

    func connectTunnel(_ tunnelID: UUID) {
        guard let tunnel = tunnel(with: tunnelID) else {
            return
        }

        logger.info("Connecting tunnel '\(tunnel.name)'", category: .tunnelManager)

        disconnectTunnel(tunnelID)

        let session = TunnelSession(
            tunnel: tunnel,
            keychainService: keychainService,
            proxyService: proxyService
        ) { [weak self] state in
            self?.handleStateChange(state, for: tunnelID, tunnelName: tunnel.name)
        }

        sessions[tunnelID] = session
        runtimeStates[tunnelID] = .init(phase: .connecting)
        session.start()
    }

    func disconnectTunnel(_ tunnelID: UUID) {
        logger.info("Disconnecting tunnel \(tunnelID.uuidString)", category: .tunnelManager)
        sessions[tunnelID]?.stop()
        sessions.removeValue(forKey: tunnelID)
        runtimeStates[tunnelID] = .init(phase: .idle)
    }

    func connectAll() {
        tunnels.forEach { connectTunnel($0.id) }
    }

    func disconnectAll() {
        tunnels.forEach { disconnectTunnel($0.id) }
    }

    func shutdownForApplicationExit() {
        logger.info("Shutting down \(sessions.count) active tunnel session(s) for application exit", category: .tunnelManager)

        let activeSessions = sessions
        for (tunnelID, session) in activeSessions {
            session.stopAndWait()
            runtimeStates[tunnelID] = .init(phase: .idle)
        }

        sessions.removeAll()
    }

    func startAutoLaunchTunnelsIfNeeded() {
        tunnels.filter(\.autoStartOnLaunch).forEach { connectTunnel($0.id) }
    }

    func handleSleep() {
        guard appSettings.reconnectOnSleepWake else {
            return
        }

        let activeTunnelIDs = sessions.keys
        activeTunnelIDs.forEach { disconnectTunnel($0) }
    }

    func handleWake() {
        guard appSettings.reconnectOnSleepWake else {
            return
        }

        tunnels.filter { runtimeState(for: $0.id).phase == .idle && $0.autoReconnect }.forEach { connectTunnel($0.id) }
    }

    private func handleStateChange(_ state: TunnelRuntimeState, for tunnelID: UUID, tunnelName: String) {
        runtimeStates[tunnelID] = state
        logger.info("Tunnel '\(tunnelName)' state changed to \(state.label)", category: .tunnelManager)
        if case .connected = state.phase {
            notify(title: tunnelName, body: "Tunnel connected")
        }
        if case .failed(let message) = state.phase {
            logger.error("Tunnel '\(tunnelName)' failed: \(message)", category: .tunnelManager)
            notify(title: tunnelName, body: message)
        }
    }

    private func notify(title: String, body: String) {
        guard appSettings.useNotificationCenter, supportsUserNotifications else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func requestNotificationsAuthorization() {
        guard supportsUserNotifications else {
            return
        }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private static func canUseUserNotifications() -> Bool {
        let bundleURL = Bundle.main.bundleURL
        return bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    private func decodeImportedTunnels(from data: Data) throws -> [Tunnel] {
        let decoder = JSONDecoder()
        if let tunnels = try? decoder.decode([Tunnel].self, from: data) {
            return tunnels
        }

        if let tunnel = try? decoder.decode(Tunnel.self, from: data) {
            return [tunnel]
        }

        throw TunnelImportError.invalidFormat
    }

    private func export(tunnels: [Tunnel], suggestedFileName: String) throws {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = suggestedFileName

        guard savePanel.runModal() == .OK, let url = savePanel.url else {
            return
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let payload: Encodable
        if tunnels.count == 1, let tunnel = tunnels.first {
            payload = tunnel
        } else {
            payload = tunnels
        }

        let data = try AnyEncodable(payload).encoded(using: encoder)
        try data.write(to: url)
        logger.info("Exported configuration file to \(url.path)", category: .tunnelManager)
    }

    private func presentError(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    private func uniqueName(basedOn proposed: String, excluding excludedID: UUID? = nil) -> String {
        let trimmed = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Tunnel" : trimmed

        let existingNames = Set(
            tunnels
                .filter { $0.id != excludedID }
                .map { $0.name.lowercased() }
        )

        guard existingNames.contains(base.lowercased()) else {
            return base
        }

        var counter = 2
        while existingNames.contains("\(base) \(counter)".lowercased()) {
            counter += 1
        }
        return "\(base) \(counter)"
    }

    private func persistTunnels() {
        persistenceStore.saveTunnels(tunnels)
    }
}

private struct AnyEncodable: Encodable {
    private let encodeHandler: (Encoder) throws -> Void

    init(_ wrapped: Encodable) {
        encodeHandler = wrapped.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeHandler(encoder)
    }

    func encoded(using encoder: JSONEncoder) throws -> Data {
        try encoder.encode(self)
    }
}

private enum TunnelImportError: LocalizedError {
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "The selected file does not contain a valid WormholeLink tunnel configuration."
        }
    }
}