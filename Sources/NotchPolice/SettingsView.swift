import SwiftUI
import NotchPoliceCore

struct SettingsView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        Form {
            Section("Notch") {
                Picker("Edge", selection: $store.preferences.edge) {
                    ForEach(ScreenEdge.allCases) { edge in
                        Text(edge.rawValue.capitalized).tag(edge)
                    }
                }
                Picker("Show", selection: $store.preferences.displayMode) {
                    Text("Remaining").tag(DisplayMode.remaining)
                    Text("Used").tag(DisplayMode.used)
                }
                Toggle("Dock icon", isOn: $store.preferences.showDockIcon)
                Toggle("Demo data", isOn: $store.preferences.demo)
            }

            Section("Agents") {
                ForEach(ProviderKind.allCases) { kind in
                    Toggle(kind.displayName, isOn: enabledBinding(kind))
                }
            }

            Section("Polling") {
                Stepper(
                    "Every \(store.preferences.pollSeconds) seconds",
                    value: $store.preferences.pollSeconds,
                    in: 30...600,
                    step: 15
                )
                Stepper(
                    store.preferences.notifyBelow == 0
                        ? "Notifications off"
                        : "Notify under \(store.preferences.notifyBelow)% left",
                    value: $store.preferences.notifyBelow,
                    in: 0...40,
                    step: 5
                )
            }

            Section("How it reads") {
                Text("Notch Police never signs in as you. It borrows sessions already stored by Claude Code, Cursor, Codex, and Grok CLI. Antigravity is read from its loopback-only language server while the app or `agy` is running.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 520)
        .onChange(of: store.preferences.demo) { _, _ in
            Task { await store.refresh() }
        }
        .onChange(of: store.preferences.pollSeconds) { _, _ in
            store.reschedule()
        }
        .onChange(of: store.preferences.showDockIcon) { _, show in
            NSApp.setActivationPolicy(show ? .regular : .accessory)
        }
    }

    private func enabledBinding(_ kind: ProviderKind) -> Binding<Bool> {
        Binding(
            get: { store.preferences.isEnabled(kind) },
            set: { store.preferences.enabled[kind] = $0 }
        )
    }
}
