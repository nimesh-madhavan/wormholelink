import AppKit
import SwiftUI

private let portNumberFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .none
    formatter.allowsFloats = false
    formatter.minimum = 0
    formatter.maximum = 65535
    formatter.usesGroupingSeparator = false
    return formatter
}()

struct PreferencesRootView: View {
    @ObservedObject var manager: TunnelManager

    var body: some View {
        NavigationSplitView {
            List(selection: selectionBinding) {
                Label("General", systemImage: "gearshape")
                    .tag(PreferencesSelection.general)

                Section("Tunnels") {
                    ForEach(manager.tunnels) { tunnel in
                        Label(tunnel.name, systemImage: iconName(for: tunnel.type))
                            .tag(PreferencesSelection.tunnel(tunnel.id))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .toolbar {
                ToolbarItemGroup {
                    Menu {
                        ForEach(TunnelType.allCases) { type in
                            Button(type.displayName) {
                                manager.addTunnel(type: type)
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }

                    Button {
                        manager.removeSelectedTunnel()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(!isTunnelSelection)

                    Menu {
                        Button("Import...") {
                            manager.importTunnels()
                        }

                        Button("Export All...") {
                            manager.exportAllTunnels()
                        }

                        Button("Duplicate") {
                            manager.duplicateSelectedTunnel()
                        }
                        .disabled(!isTunnelSelection)

                        Button("Export") {
                            manager.exportSelectedTunnel()
                        }
                        .disabled(!isTunnelSelection)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        } detail: {
            switch manager.selection {
            case .general:
                GeneralSettingsView(manager: manager)
            case .tunnel(let tunnelID):
                if manager.tunnel(with: tunnelID) != nil {
                    TunnelDetailContainerView(manager: manager, tunnelID: tunnelID)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("Select a tunnel")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var selectionBinding: Binding<PreferencesSelection?> {
        Binding(
            get: { manager.selection },
            set: { selection in
                if let selection {
                    manager.setSelection(selection)
                }
            }
        )
    }

    private var isTunnelSelection: Bool {
        if case .tunnel = manager.selection {
            return true
        }
        return false
    }

    private func iconName(for type: TunnelType) -> String {
        switch type {
        case .localForward:
            return "arrow.down.to.line"
        case .remoteForward:
            return "arrow.up.to.line"
        case .socksProxy:
            return "network"
        }
    }
}

struct TunnelDetailContainerView: View {
    @ObservedObject var manager: TunnelManager
    let tunnelID: UUID

    var body: some View {
        let binding = manager.makeTunnelBinding(for: tunnelID)
        TunnelDetailView(manager: manager, tunnel: binding)
            .id(tunnelID)
    }
}

struct TunnelDetailView: View {
    @ObservedObject var manager: TunnelManager
    @Binding var tunnel: Tunnel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text(tunnel.name.isEmpty ? "Untitled Tunnel" : tunnel.name)
                        .font(.title2.weight(.semibold))
                    Text(manager.runtimeState(for: tunnel.id).label)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Connect") {
                    manager.connectTunnel(tunnel.id)
                }
                Button("Disconnect") {
                    manager.disconnectTunnel(tunnel.id)
                }
            }

            TabView {
                TunnelConnectionTab(manager: manager, tunnel: $tunnel)
                    .tabItem { Text("Connection") }
                TunnelOptionsTab(tunnel: $tunnel)
                    .tabItem { Text("Options") }
            }
        }
        .padding(24)
    }
}

struct TunnelConnectionTab: View {
    @ObservedObject var manager: TunnelManager
    @Binding var tunnel: Tunnel

    var body: some View {
        Form {
            TextField("Connection Name", text: $tunnel.name)
            TextField("SSH Server Address", text: $tunnel.sshHost)
            TextField("SSH Port", value: $tunnel.sshPort, formatter: portNumberFormatter)
            TextField("SSH Username", text: $tunnel.sshUser)

            Picker("Authentication", selection: $tunnel.authMethod) {
                ForEach(AuthMethod.allCases) { method in
                    Text(method.displayName).tag(method)
                }
            }
            .pickerStyle(.segmented)

            if tunnel.authMethod == .password {
                TunnelSecretField(
                    title: "Password",
                    secretKind: .tunnelPassword,
                    manager: manager,
                    tunnelID: tunnel.id
                )
            } else {
                HStack {
                    TextField("Identity File", text: Binding(
                        get: { tunnel.identityFilePath ?? "" },
                        set: { tunnel.identityFilePath = $0.isEmpty ? nil : $0 }
                    ))
                    Button("Browse...") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = false
                        panel.canChooseFiles = true
                        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
                        if panel.runModal() == .OK {
                            tunnel.identityFilePath = panel.url?.path
                        }
                    }
                }

                TunnelSecretField(
                    title: "Passphrase",
                    secretKind: .tunnelPassphrase,
                    manager: manager,
                    tunnelID: tunnel.id
                )
            }

            TextField("Local Bind Address", text: $tunnel.localBindAddress)
            TextField("Local Port", value: $tunnel.localPort, formatter: portNumberFormatter)

            if tunnel.type != .socksProxy {
                TextField("Remote Host", text: Binding(
                    get: { tunnel.remoteHost ?? "" },
                    set: { tunnel.remoteHost = $0 }
                ))
                TextField("Remote Port", value: Binding(
                    get: { tunnel.remotePort ?? 0 },
                    set: { tunnel.remotePort = $0 }
                ), formatter: portNumberFormatter)
            }

            if tunnel.type == .socksProxy {
                Toggle("Automatically configure system SOCKS proxy", isOn: $tunnel.autoConfigureSystemProxy)
            }
        }
        .formStyle(.grouped)
    }
}

struct TunnelOptionsTab: View {
    @Binding var tunnel: Tunnel

    var body: some View {
        Form {
            Toggle("Compress data", isOn: $tunnel.compress)
            Toggle("Strict host key checking", isOn: $tunnel.strictHostKeyChecking)
            Toggle("Start this connection when WormholeLink launches", isOn: $tunnel.autoStartOnLaunch)
            Toggle("Automatically retry connection on disconnect", isOn: $tunnel.autoReconnect)
            Toggle("Include in menu bar menu", isOn: $tunnel.showInMenuBar)
        }
        .formStyle(.grouped)
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var manager: TunnelManager

    var body: some View {
        let settings = Binding(
            get: { manager.appSettings },
            set: { manager.updateSettings($0) }
        )

        Form {
            Toggle("Launch WormholeLink at login", isOn: settings.launchAtLogin)
            Toggle("Show connection notifications", isOn: settings.useNotificationCenter)
            Toggle("Allow saving administrator password in Keychain", isOn: settings.allowSaveAdminPasswordInKeychain)
            Toggle("Disconnect and reconnect active tunnels on sleep/wake", isOn: settings.reconnectOnSleepWake)
        }
        .padding(24)
        .formStyle(.grouped)
    }
}

struct TunnelSecretField: View {
    let title: String
    let secretKind: KeychainSecretKind
    @ObservedObject var manager: TunnelManager
    let tunnelID: UUID

    @State private var value: String = ""

    var body: some View {
        SecureField(title, text: $value)
            .onAppear {
                value = manager.secret(kind: secretKind, for: tunnelID)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSControl.textDidChangeNotification)) { _ in
                manager.saveSecret(value, kind: secretKind, for: tunnelID)
            }
    }
}