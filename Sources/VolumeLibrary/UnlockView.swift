import SwiftUI
import VolumeCore

struct UnlockView: View {
    @Bindable var model: AppModel
    let controller: AppController
    let volume: SavedVolume
    @State private var password = ""
    @State private var revealed = false
    @State private var expanded = false
    @State private var readOnly = true
    @State private var openAfter = false
    @State private var confirmedNormal = false
    @FocusState private var focused: Bool

    private var busy: Bool { model.busyPath != nil }
    private var valid: Bool { !password.isEmpty && (readOnly || confirmedNormal) && model.canOperate }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Enter the password for this volume.").font(.system(size: 14))
                Spacer()
                if model.demo { DemoLabel() }
            }
            HStack(spacing: 8) {
                Group {
                    if revealed { TextField("Password", text: $password) }
                    else { SecureField("Password", text: $password) }
                }
                .textFieldStyle(.plain).focused($focused)
                .onSubmit(submit).accessibilityLabel("Volume password")
                Button { revealed.toggle() } label: { Image(systemName: revealed ? "eye.slash" : "eye") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel(revealed ? "Hide password" : "Show password")
            }
            .padding(11)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(focused ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: focused ? 2 : 1))
            .disabled(busy)

            DisclosureGroup("Advanced options", isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Mount read-only", isOn: $readOnly)
                    if !readOnly {
                        Toggle("This is a normal volume with no hidden volume to protect", isOn: $confirmedNormal)
                            .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Default PIM · No keyfiles\nFor other credentials or hidden-volume protection, use VeraCrypt.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(.top, 8)
            }.disabled(busy)
                .onChange(of: expanded) { _, value in controller.resizeUnlock(expanded: value) }

            Toggle("Open in Finder after mounting", isOn: $openAfter).disabled(busy)
            if model.demo { Text("Try any password. “wrong” demonstrates an error.").font(.system(size: 11)).foregroundStyle(.secondary) }
            if let notice = model.notice {
                Text(notice).font(.system(size: 11)).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true).accessibilityLabel(notice)
            }
            Spacer(minLength: 0)
            HStack {
                if busy { ProgressView().controlSize(.small); Text("Unlocking…").font(.system(size: 12)).foregroundStyle(.secondary) }
                Spacer()
                Button("Cancel") { password = ""; controller.finishUnlock() }.keyboardShortcut(.cancelAction).disabled(busy)
                Button("Unlock", action: submit).buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction).disabled(!valid || busy)
            }
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { readOnly = volume.readOnly; openAfter = volume.openAfterMount; focused = true }
        .onDisappear { password = ""; revealed = false }
    }

    private func submit() {
        guard valid && !busy else { return }
        let credential = password
        password = ""
        revealed = false
        Task {
            if await model.unlock(volume, password: credential, readOnly: readOnly, openAfter: openAfter) {
                controller.finishUnlock()
            } else { focused = true }
        }
    }
}
