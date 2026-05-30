import Foundation

final class PersistenceStore {
    private let logger = AppLogger.shared

    private enum Keys {
        static let tunnels = "tunnels"
        static let settings = "settings"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadTunnels() -> [Tunnel] {
        guard let data = defaults.data(forKey: Keys.tunnels) else {
            return []
        }

        do {
            return try decoder.decode([Tunnel].self, from: data)
        } catch {
            return []
        }
    }

    func saveTunnels(_ tunnels: [Tunnel]) {
        do {
            let data = try encoder.encode(tunnels)
            defaults.set(data, forKey: Keys.tunnels)
        } catch {
            logger.error("Failed to encode tunnels: \(error.localizedDescription)", category: .persistence)
        }
    }

    func loadSettings() -> AppSettings {
        guard let data = defaults.data(forKey: Keys.settings) else {
            return AppSettings()
        }

        do {
            return try decoder.decode(AppSettings.self, from: data)
        } catch {
            return AppSettings()
        }
    }

    func saveSettings(_ settings: AppSettings) {
        do {
            let data = try encoder.encode(settings)
            defaults.set(data, forKey: Keys.settings)
        } catch {
            logger.error("Failed to encode settings: \(error.localizedDescription)", category: .persistence)
        }
    }
}