import Foundation
import Network

final class ProbeResult: @unchecked Sendable {
    var connected = false
}

final class TunnelSession: @unchecked Sendable {
    private static let startupTimeout: TimeInterval = 10

    private let logger = AppLogger.shared
    private let tunnel: Tunnel
    private let keychainService: KeychainService
    private let proxyService: SystemProxyService
    private let stateHandler: @MainActor (TunnelRuntimeState) -> Void
    private let queue = DispatchQueue(label: "WormholeLink.TunnelSession")
    private let probeQueue = DispatchQueue(label: "WormholeLink.TunnelSession.Probe")

    private var process: Process?
    private var reconnectWorkItem: DispatchWorkItem?
    private var startupTimeoutWorkItem: DispatchWorkItem?
    private var retryDelay: TimeInterval = 1
    private var userInitiatedStop = false
    private var temporaryFiles: [URL] = []
    private var lastErrorOutput = ""
    private var launchArguments: [String] = []

    init(
        tunnel: Tunnel,
        keychainService: KeychainService,
        proxyService: SystemProxyService,
        stateHandler: @escaping @MainActor (TunnelRuntimeState) -> Void
    ) {
        self.tunnel = tunnel
        self.keychainService = keychainService
        self.proxyService = proxyService
        self.stateHandler = stateHandler
    }

    func start() {
        queue.async {
            self.userInitiatedStop = false
            self.reconnectWorkItem?.cancel()
            self.launchProcess()
        }
    }

    func stop() {
        queue.async {
            self.userInitiatedStop = true
            self.reconnectWorkItem?.cancel()
            self.startupTimeoutWorkItem?.cancel()
            self.cleanupProxyIfNeeded()
            self.process?.terminate()
            self.process = nil
            self.retryDelay = 1
            self.clearAskpassFiles()
            self.publish(.init(phase: .idle))
        }
    }

    func stopAndWait(timeout: TimeInterval = 2) {
        let semaphore = DispatchSemaphore(value: 0)

        queue.async {
            self.userInitiatedStop = true
            self.reconnectWorkItem?.cancel()
            self.startupTimeoutWorkItem?.cancel()
            self.cleanupProxyIfNeeded()

            if let process = self.process, process.isRunning {
                self.logger.info("Synchronously terminating ssh for tunnel '\(self.tunnel.name)'", category: .tunnelSession)
                process.terminate()

                let deadline = Date().addingTimeInterval(timeout)
                while process.isRunning && Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }

                if process.isRunning {
                    self.logger.warning("SSH process for '\(self.tunnel.name)' did not exit after SIGTERM before app shutdown", category: .tunnelSession)
                }
            }

            self.process = nil
            self.retryDelay = 1
            self.clearAskpassFiles()
            self.publish(.init(phase: .idle))
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + timeout + 0.5)
    }

    private func launchProcess() {
        clearAskpassFiles()
        lastErrorOutput = ""

        do {
            try validateIdentityPermissionsIfNeeded()

            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            let arguments = try buildArguments()
            let launcherURL = try writeLauncherScript()

            process.executableURL = launcherURL
            process.arguments = [String(ProcessInfo.processInfo.processIdentifier)] + arguments
            process.standardOutput = stdout
            process.standardError = stderr
            process.standardInput = FileHandle.nullDevice
            process.environment = try buildEnvironment()
            launchArguments = arguments
            scheduleStartupTimeout()
            logger.info("Launching ssh for tunnel '\(tunnel.name)': ssh \(arguments.joined(separator: " "))", category: .tunnelSession)

            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    self.logger.debug("SSH stdout for '\(self.tunnel.name)': \(text)", category: .tunnelSession)
                }
            }

            stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    self?.appendErrorOutput(text)
                    self?.logger.warning("SSH stderr for '\(self?.tunnel.name ?? "unknown")': \(text)", category: .tunnelSession)
                    if text.localizedCaseInsensitiveContains("Permission denied") {
                        self?.publish(.init(phase: .failed(text)))
                    }
                }
            }

            process.terminationHandler = { [weak self] terminatedProcess in
                self?.queue.async {
                    self?.handleTermination(status: terminatedProcess.terminationStatus)
                }
            }

            publish(.init(phase: .connecting))
            try process.run()
            self.process = process

            queue.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.verifyStartup()
            }
        } catch {
            scheduleFailure(error.localizedDescription)
        }
    }

    private func handleTermination(status: Int32) {
        startupTimeoutWorkItem?.cancel()
        clearAskpassFiles()
        cleanupProxyIfNeeded()
        process = nil
        logger.info("SSH process terminated for '\(tunnel.name)' with status \(status)", category: .tunnelSession)

        if userInitiatedStop {
            publish(.init(phase: .idle))
            return
        }

        if tunnel.autoReconnect {
            let delay = retryDelay
            publish(.init(phase: .reconnecting(delay)))

            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.retryDelay = min(self.retryDelay * 2, 60)
                self.launchProcess()
            }

            reconnectWorkItem = workItem
            queue.asyncAfter(deadline: .now() + delay, execute: workItem)
        } else {
            publish(.init(phase: .failed(failureMessage(for: status))))
        }
    }

    private func verifyStartup() {
        guard let process, process.isRunning else {
            logger.warning("Startup verification skipped for '\(tunnel.name)' because ssh is no longer running", category: .tunnelSession)
            return
        }

        let didProbeSucceed: Bool
        switch tunnel.type {
        case .remoteForward:
            didProbeSucceed = true
        case .localForward, .socksProxy:
            didProbeSucceed = probeLocalPort(host: tunnel.localBindAddress, port: tunnel.localPort)
        }

        if !didProbeSucceed {
            logger.warning("Tunnel '\(tunnel.name)' port probe did not succeed; treating the still-running ssh process as authoritative", category: .tunnelSession)
        }

        startupTimeoutWorkItem?.cancel()
        retryDelay = 1
        logger.info("Tunnel '\(tunnel.name)' verified as live", category: .tunnelSession)
        if tunnel.type == .socksProxy, tunnel.autoConfigureSystemProxy {
            do {
                try proxyService.enableProxy(for: tunnel)
            } catch {
                logger.error("Failed to enable SOCKS proxy for '\(tunnel.name)': \(error.localizedDescription)", category: .tunnelSession)
            }
        }
        publish(.init(phase: .connected))
    }

    private func buildArguments() throws -> [String] {
        var arguments = [
            "-N",
            "-p", String(tunnel.sshPort),
            "-S", "none",
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ForkAfterAuthentication=no",
            "-o", "ControlMaster=no",
            "-o", "StrictHostKeyChecking=\(tunnel.strictHostKeyChecking ? "yes" : "no")",
            "-o", "BatchMode=no"
        ]

        if tunnel.compress {
            arguments.append("-C")
        }

        switch tunnel.authMethod {
        case .password:
            arguments += ["-o", "PreferredAuthentications=password,keyboard-interactive"]
        case .identityFile:
            if let identityFilePath = tunnel.identityFilePath, !identityFilePath.isEmpty {
                arguments += ["-i", identityFilePath]
            }
        }

        switch tunnel.type {
        case .localForward:
            let bind = normalizedBindAddress()
            let remoteHost = tunnel.remoteHost?.isEmpty == false ? tunnel.remoteHost! : "127.0.0.1"
            let remotePort = max(tunnel.remotePort ?? 0, 1)
            arguments += ["-L", "\(bind):\(tunnel.localPort):\(remoteHost):\(remotePort)"]
        case .remoteForward:
            let bind = normalizedBindAddress()
            let remoteHost = tunnel.remoteHost?.isEmpty == false ? tunnel.remoteHost! : "127.0.0.1"
            let remotePort = max(tunnel.remotePort ?? 0, 1)
            arguments += ["-R", "\(bind):\(remotePort):\(remoteHost):\(tunnel.localPort)"]
        case .socksProxy:
            let bind = normalizedBindAddress()
            arguments += ["-D", "\(bind):\(tunnel.localPort)"]
        }

        arguments.append("\(tunnel.sshUser)@\(tunnel.sshHost)")
        return arguments
    }

    private func buildEnvironment() throws -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        if let secret = try currentSecret(), !secret.isEmpty {
            let fileURL = try writeAskpassSecret(secret)
            let scriptURL = try writeAskpassScript()
            temporaryFiles.append(contentsOf: [fileURL, scriptURL])
            environment["SSH_ASKPASS"] = scriptURL.path
            environment["SSH_ASKPASS_REQUIRE"] = "force"
            environment["DISPLAY"] = "WormholeLink"
            environment["WORMHOLELINK_SECRET_FILE"] = fileURL.path
        }
        return environment
    }

    private func currentSecret() throws -> String? {
        switch tunnel.authMethod {
        case .password:
            return try keychainService.readSecret(kind: .tunnelPassword, account: tunnel.id.uuidString)
        case .identityFile:
            return try keychainService.readSecret(kind: .tunnelPassphrase, account: tunnel.id.uuidString)
        }
    }

    private func writeAskpassSecret(_ secret: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wormholelink-\(UUID().uuidString).secret")
        try secret.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    private func writeAskpassScript() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wormholelink-\(UUID().uuidString).sh")
        let script = "#!/bin/sh\n/bin/cat \"$WORMHOLELINK_SECRET_FILE\"\n"
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    private func writeLauncherScript() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wormholelink-launcher-\(UUID().uuidString).sh")
        let script = "#!/bin/sh\nparent_pid=\"$1\"\nshift\n/usr/bin/ssh \"$@\" &\nssh_pid=$!\ncleanup() {\n  if kill -0 \"$ssh_pid\" 2>/dev/null; then\n    kill \"$ssh_pid\" 2>/dev/null || true\n    wait \"$ssh_pid\" 2>/dev/null || true\n  fi\n}\ntrap cleanup EXIT INT TERM HUP\nwhile kill -0 \"$ssh_pid\" 2>/dev/null; do\n  if ! kill -0 \"$parent_pid\" 2>/dev/null; then\n    cleanup\n    exit 0\n  fi\n  sleep 1\ndone\nwait \"$ssh_pid\"\n"
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        temporaryFiles.append(url)
        return url
    }

    private func clearAskpassFiles() {
        temporaryFiles.forEach { try? FileManager.default.removeItem(at: $0) }
        temporaryFiles.removeAll()
    }

    private func normalizedBindAddress() -> String {
        tunnel.localBindAddress == "*" ? "0.0.0.0" : tunnel.localBindAddress
    }

    private func validateIdentityPermissionsIfNeeded() throws {
        guard tunnel.authMethod == .identityFile,
              let identityFilePath = tunnel.identityFilePath,
              !identityFilePath.isEmpty else {
            return
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: identityFilePath)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        if permissions & 0o077 != 0 {
            throw NSError(domain: "WormholeLink", code: 1, userInfo: [NSLocalizedDescriptionKey: "Identity file must have 0600 permissions."])
        }
    }

    private func probeLocalPort(host: String, port: Int) -> Bool {
        let targetHost = host == "*" || host == "0.0.0.0" ? "127.0.0.1" : host
        let semaphore = DispatchSemaphore(value: 0)
        let probeResult = ProbeResult()

        let connection = NWConnection(host: NWEndpoint.Host(targetHost), port: NWEndpoint.Port(integerLiteral: NWEndpoint.Port.IntegerLiteralType(port)), using: .tcp)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                probeResult.connected = true
                connection.cancel()
                semaphore.signal()
            case .failed, .cancelled:
                semaphore.signal()
            default:
                break
            }
        }
        connection.start(queue: probeQueue)
        _ = semaphore.wait(timeout: .now() + 2)
        return probeResult.connected
    }

    private func cleanupProxyIfNeeded() {
        if tunnel.type == .socksProxy, tunnel.autoConfigureSystemProxy {
            proxyService.disableProxy(for: tunnel.id)
        }
    }

    private func scheduleFailure(_ message: String) {
        startupTimeoutWorkItem?.cancel()
        retryDelay = min(retryDelay * 2, 60)
        logger.error("Tunnel '\(tunnel.name)' scheduling failure: \(message)", category: .tunnelSession)
        publish(.init(phase: .failed(message)))
    }

    private func scheduleStartupTimeout() {
        startupTimeoutWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  !self.userInitiatedStop,
                  let process = self.process,
                  process.isRunning else {
                return
            }

            let message = self.lastErrorOutput.isEmpty
                ? "SSH connection timed out while establishing the tunnel"
                : self.lastErrorOutput
            self.logger.error("Tunnel '\(self.tunnel.name)' startup timed out: \(message)", category: .tunnelSession)
            self.publish(.init(phase: .failed(message)))
            process.terminate()
        }

        startupTimeoutWorkItem = workItem
        queue.asyncAfter(deadline: .now() + Self.startupTimeout, execute: workItem)
    }

    private func appendErrorOutput(_ text: String) {
        if lastErrorOutput.isEmpty {
            lastErrorOutput = text
        } else {
            lastErrorOutput += "\n\(text)"
        }

        if lastErrorOutput.count > 1000 {
            lastErrorOutput = String(lastErrorOutput.suffix(1000))
        }
    }

    private func failureMessage(for status: Int32) -> String {
        if !lastErrorOutput.isEmpty {
            return lastErrorOutput
        }

        if launchArguments.isEmpty {
            return "SSH exited with status \(status)"
        }

        return "SSH exited with status \(status) while running: ssh \(launchArguments.joined(separator: " "))"
    }

    private func publish(_ state: TunnelRuntimeState) {
        Task { @MainActor in
            stateHandler(state)
        }
    }
}