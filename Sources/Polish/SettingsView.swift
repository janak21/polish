import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    // Drafts: only written to the Keychain / UserDefaults when Save is pressed.
    @State private var apiKey = Keychain.apiKey ?? ""
    @State private var actions = CustomActions.shared.items
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var saved = false

    private var hasChanges: Bool {
        apiKey != (Keychain.apiKey ?? "") || actions != CustomActions.shared.items
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Claude") {
                    SecureField("API key", text: $apiKey)
                    Link("Get an API key", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                }
                Section("General") {
                    KeyboardShortcuts.Recorder("Proofread shortcut:", name: .proofread)
                    Toggle("Start at login", isOn: $launchAtLogin)
                }
                Section("Custom actions") {
                    ForEach($actions) { $action in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading) {
                                TextField("Name", text: $action.name, prompt: Text("Name, e.g. Client reply"))
                                TextField("Instruction", text: $action.instruction,
                                          prompt: Text("Instruction, e.g. Rewrite as a polite reply to a client"),
                                          axis: .vertical)
                                    .lineLimit(2...6)
                            }
                            .labelsHidden()
                            Button { actions.removeAll { $0.id == action.id } } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                        }
                    }
                    Button("Add action") { actions.append(Action(name: "", instruction: "")) }
                }
            }
            .formStyle(.grouped)

            HStack {
                if saved { Label("Saved", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                Spacer()
                Button("Save", action: save)
                    .keyboardShortcut("s")
                    .disabled(!hasChanges)
            }
            .padding()
        }
        .frame(width: 560, height: 520)
        .onChange(of: apiKey) { saved = false }
        .onChange(of: actions) { saved = false }
        .onChange(of: launchAtLogin) { _, on in
            _ = try? (on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister())
        }
    }

    private func save() {
        apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.apiKey = apiKey
        CustomActions.shared.items = actions
        saved = true
    }
}
