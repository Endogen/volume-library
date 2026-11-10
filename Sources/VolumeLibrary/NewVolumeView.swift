import SwiftUI
import VolumeCore

struct NewVolumeView: View {
    @Bindable var model: AppModel
    let controller: AppController
    @State private var size = "256"
    @State private var password = ""
    @State private var confirmation = ""
    @State private var message: String?
    @State private var creating = false

    private var sizeMiB: Int? { Int(size) }
    private var mismatch: Bool { !confirmation.isEmpty && password != confirmation }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create an encrypted container").font(.title3.bold())
            Text("Standard VeraCrypt volume · AES · FAT")
                .font(.callout).foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                GridRow {
                    Text("Capacity")
                    HStack {
                        TextField("256", text: $size).frame(width: 85).accessibilityLabel("Capacity in MiB")
                        Text("MiB").foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    Text("Password")
                    SecureField("New password", text: $password)
                }
                GridRow {
                    Text("Confirm")
                    SecureField("Repeat password", text: $confirmation)
                }
            }.disabled(creating)
            if let feedback {
                Text(feedback).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HStack {
                if creating {
                    ProgressView().controlSize(.small)
                    Text("Creating volume…").font(.callout)
                }
                Spacer()
                Button("Cancel", action: controller.closeCreation).keyboardShortcut(.cancelAction).disabled(creating)
                Button("Choose Location…", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canCreate || creating || password.isEmpty || password != confirmation ||
                              (sizeMiB ?? 0) < 5 || password.utf8.count > 128)
            }
        }.padding(24)
    }

    private var feedback: String? {
        if (sizeMiB ?? 0) < 5 { return "Enter a whole number of at least 5 MiB." }
        if password.utf8.count > 128 { return "The password exceeds VeraCrypt’s 128-byte limit." }
        if mismatch { return "The passwords don’t match." }
        return message
    }

    private func submit() {
        guard !creating, let sizeMiB, let url = controller.destinationForNewVolume() else { return }
        let credential = password
        password = ""
        confirmation = ""
        creating = true
        message = nil
        Task {
            defer { creating = false }
            do {
                try await model.create(at: url, sizeMiB: sizeMiB, password: credential)
                controller.closeCreation()
                controller.showLibrary()
            } catch BackendError.invalidPassword {
                message = "Use a password without line breaks or NUL characters."
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
