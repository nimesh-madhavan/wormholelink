import Foundation

enum SystemProxyError: LocalizedError {
    case missingNetworkService
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingNetworkService:
            return "No supported network service was found for SOCKS proxy configuration."
        case .commandFailed(let message):
            return message
        }
    }
}

final class SystemProxyService {
    private let logger = AppLogger.shared

    private struct ProxySnapshot {
        let service: String
        let isEnabled: Bool
        let host: String?
        let port: Int?
    }

    private var snapshots: [UUID: ProxySnapshot] = [:]

    func enableProxy(for tunnel: Tunnel) throws {
        guard tunnel.type == .socksProxy else {
            return
        }

        let service = try activeNetworkService()
        if snapshots[tunnel.id] == nil {
            snapshots[tunnel.id] = try readSnapshot(for: service)
        }

        let host = tunnel.localBindAddress == "*" ? "127.0.0.1" : tunnel.localBindAddress
        try runNetworkSetup(["-setsocksfirewallproxy", service, host, String(tunnel.localPort)])
        try runNetworkSetup(["-setsocksfirewallproxystate", service, "on"])
    }

    func disableProxy(for tunnelID: UUID) {
        guard let snapshot = snapshots.removeValue(forKey: tunnelID) else {
            return
        }

        do {
            if snapshot.isEnabled, let host = snapshot.host, let port = snapshot.port {
                try runNetworkSetup(["-setsocksfirewallproxy", snapshot.service, host, String(port)])
                try runNetworkSetup(["-setsocksfirewallproxystate", snapshot.service, "on"])
            } else {
                try runNetworkSetup(["-setsocksfirewallproxystate", snapshot.service, "off"])
            }
        } catch {
            logger.error("Failed to restore SOCKS proxy: \(error.localizedDescription)", category: .proxy)
        }
    }

    private func activeNetworkService() throws -> String {
        let output = try runNetworkSetup(["-listallnetworkservices"])
        let candidates = output
            .split(separator: "\n")
            .dropFirst()
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("*") }

        guard let service = candidates.first else {
            throw SystemProxyError.missingNetworkService
        }

        return service
    }

    private func readSnapshot(for service: String) throws -> ProxySnapshot {
        let output = try runNetworkSetup(["-getsocksfirewallproxy", service])
        var isEnabled = false
        var host: String?
        var port: Int?

        for line in output.split(separator: "\n") {
            let components = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard components.count == 2 else {
                continue
            }

            let key = components[0].trimmingCharacters(in: .whitespaces)
            let value = components[1].trimmingCharacters(in: .whitespaces)

            switch key {
            case "Enabled":
                isEnabled = value == "Yes"
            case "Server":
                host = value.isEmpty ? nil : value
            case "Port":
                port = Int(value)
            default:
                continue
            }
        }

        return ProxySnapshot(service: service, isEnabled: isEnabled, host: host, port: port)
    }

    @discardableResult
    private func runNetworkSetup(_ arguments: [String]) throws -> String {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let errorOutput = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

        guard process.terminationStatus == 0 else {
            throw SystemProxyError.commandFailed(errorOutput.isEmpty ? output : errorOutput)
        }

        return output
    }
}