import AppKit
import Foundation

enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

enum LogCategory: String {
    case app = "App"
    case tunnelManager = "TunnelManager"
    case tunnelSession = "TunnelSession"
    case persistence = "Persistence"
    case proxy = "SystemProxy"
    case keychain = "Keychain"
}

final class AppLogger: @unchecked Sendable {
    static let shared = AppLogger()

    let logFileURL: URL

    private let queue = DispatchQueue(label: "WormholeLink.AppLogger")
    private let dateFormatter: ISO8601DateFormatter

    private init() {
        dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let baseDirectory: URL
        if let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            baseDirectory = applicationSupport.appendingPathComponent("WormholeLink/Logs", isDirectory: true)
        } else {
            baseDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("WormholeLinkLogs", isDirectory: true)
        }

        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        logFileURL = baseDirectory.appendingPathComponent("debug.log")
        rotateIfNeeded()
        log(level: .info, category: .app, message: "Logger initialized at \(logFileURL.path)")
    }

    func debug(_ message: String, category: LogCategory) {
        log(level: .debug, category: category, message: message)
    }

    func info(_ message: String, category: LogCategory) {
        log(level: .info, category: category, message: message)
    }

    func warning(_ message: String, category: LogCategory) {
        log(level: .warning, category: category, message: message)
    }

    func error(_ message: String, category: LogCategory) {
        log(level: .error, category: category, message: message)
    }

    func openLogFile() {
        NSWorkspace.shared.open(logFileURL)
    }

    private func log(level: LogLevel, category: LogCategory, message: String) {
        let sanitizedMessage = message.replacingOccurrences(of: "\n", with: "\\n")
        let line = "[\(dateFormatter.string(from: .now))] [\(level.rawValue)] [\(category.rawValue)] \(sanitizedMessage)\n"

        queue.async {
            guard let data = line.data(using: .utf8) else {
                return
            }

            if !FileManager.default.fileExists(atPath: self.logFileURL.path) {
                FileManager.default.createFile(atPath: self.logFileURL.path, contents: nil)
            }

            do {
                let handle = try FileHandle(forWritingTo: self.logFileURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } catch {
                NSLog("WormholeLink logger failed: \(error.localizedDescription)")
            }
        }
    }

    private func rotateIfNeeded() {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
              let fileSize = attributes[.size] as? NSNumber,
              fileSize.intValue > 1_000_000 else {
            return
        }

        let archivedURL = logFileURL.deletingLastPathComponent().appendingPathComponent("debug.previous.log")
        try? FileManager.default.removeItem(at: archivedURL)
        try? FileManager.default.moveItem(at: logFileURL, to: archivedURL)
    }
}