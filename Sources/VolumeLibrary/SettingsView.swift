import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Bindable var model: AppModel
    let controller: AppController
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginMessage: String?
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Settings").font(.system(size: 24, weight: .bold))
            VStack(alignment: .leading, spacing: 10) {
                Text("VERACRYPT").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Text(model.setupMessage ?? model.backendInfo.map { "Connected · \($0.version) · \($0.flavor)" } ?? "Checking installation…")
                    .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                Text(model.appPath).font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                HStack {
                    Button("Locate…", action: controller.locateVeraCrypt)
                    Button("Retry") { Task { await model.reconnect(); controller.updateStatusIcon() } }
                    Button("Downloads", action: controller.openDownloads)
                    Button("Open VeraCrypt", action: controller.openVeraCrypt)
                }.disabled(model.busyPath != nil || model.isRefreshing)
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Launch in the menu bar at login", isOn: Binding(
                    get: { launchAtLogin }, set: updateLogin
                ))
                if let loginMessage {
                    Text(loginMessage).font(.system(size: 11)).foregroundStyle(.secondary)
                    Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                }
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }.pickerStyle(.segmented)
                    .onChange(of: appearance) { _, value in
                        controller.applyAppearance(value)
                    }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Explore with demo volumes", isOn: Binding(get: { model.demo }, set: { enabled in
                    Task { await model.setDemo(enabled); controller.updateStatusIcon() }
                })).disabled(model.busyPath != nil || model.isRefreshing)
                Text("Demo volumes are simulated and never touch your files.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text("Volume Library · Local development build 0.1.0")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func updateLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginMessage = SMAppService.mainApp.status == .requiresApproval ? "Allow Volume Library in System Settings to complete setup." : nil
        } catch { loginMessage = "macOS couldn’t update this login item. Check Login Items in System Settings." }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
