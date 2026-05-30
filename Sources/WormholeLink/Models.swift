import Foundation

enum TunnelType: String, Codable, CaseIterable, Identifiable {
    case localForward
    case remoteForward
    case socksProxy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .localForward:
            return "Local Forward"
        case .remoteForward:
            return "Remote Forward"
        case .socksProxy:
            return "SOCKS Proxy"
        }
    }
}

enum AuthMethod: String, Codable, CaseIterable, Identifiable {
    case password
    case identityFile

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .password:
            return "Password"
        case .identityFile:
            return "Identity File"
        }
    }
}

struct Tunnel: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var type: TunnelType
    var sshHost: String
    var sshPort: Int
    var sshUser: String
    var authMethod: AuthMethod
    var identityFilePath: String?
    var localBindAddress: String
    var localPort: Int
    var remoteHost: String?
    var remotePort: Int?
    var compress: Bool
    var strictHostKeyChecking: Bool
    var autoStartOnLaunch: Bool
    var autoReconnect: Bool
    var showInMenuBar: Bool
    var autoConfigureSystemProxy: Bool

    static func makeNew(type: TunnelType) -> Tunnel {
        Tunnel(
            id: UUID(),
            name: Self.defaultName(for: type),
            type: type,
            sshHost: "",
            sshPort: 22,
            sshUser: NSUserName(),
            authMethod: .password,
            identityFilePath: nil,
            localBindAddress: "127.0.0.1",
            localPort: Self.defaultPort(for: type),
            remoteHost: type == .socksProxy ? nil : "127.0.0.1",
            remotePort: type == .socksProxy ? nil : 0,
            compress: false,
            strictHostKeyChecking: true,
            autoStartOnLaunch: false,
            autoReconnect: false,
            showInMenuBar: true,
            autoConfigureSystemProxy: false
        )
    }

    private static func defaultName(for type: TunnelType) -> String {
        switch type {
        case .localForward:
            return "New Local Forward"
        case .remoteForward:
            return "New Remote Forward"
        case .socksProxy:
            return "New SOCKS Proxy"
        }
    }

    private static func defaultPort(for type: TunnelType) -> Int {
        switch type {
        case .localForward:
            return 5432
        case .remoteForward:
            return 8080
        case .socksProxy:
            return 1080
        }
    }
}

struct AppSettings: Codable, Equatable {
    var launchAtLogin: Bool = false
    var useNotificationCenter: Bool = true
    var allowSaveAdminPasswordInKeychain: Bool = false
    var reconnectOnSleepWake: Bool = true
}

enum TunnelPhase: Equatable {
    case idle
    case connecting
    case connected
    case reconnecting(TimeInterval)
    case failed(String)
}

struct TunnelRuntimeState: Equatable {
    var phase: TunnelPhase = .idle
    var lastEvent: Date = .now

    var isActive: Bool {
        switch phase {
        case .connecting, .connected, .reconnecting:
            return true
        case .idle, .failed:
            return false
        }
    }

    var menuSymbol: String {
        switch phase {
        case .connected:
            return "●"
        case .connecting, .reconnecting:
            return "◐"
        case .idle:
            return "○"
        case .failed:
            return "△"
        }
    }

    var label: String {
        switch phase {
        case .idle:
            return "Idle"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .reconnecting(let delay):
            return "Retrying in \(Int(delay.rounded()))s"
        case .failed(let message):
            return message.isEmpty ? "Failed" : message
        }
    }
}

enum PreferencesSelection: Hashable {
    case general
    case tunnel(UUID)
}