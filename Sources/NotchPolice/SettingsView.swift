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
                    LabeledContent(kind.displayName) {
                        HStack(spacing: 8) {
                            if store.preferences.isEnabled(kind) {
                                ringPicker(kind)
                            }
                            Toggle("Show \(kind.displayName) on the notch", isOn: enabledBinding(kind))
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }
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
        .frame(width: 440, height: 620)
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

    @ViewBuilder
    private func ringPicker(_ kind: ProviderKind) -> some View {
        let options = ringOptions(for: kind)
        if options.count >= 2 {
            Picker("Ring", selection: ringBinding(kind)) {
                Text("Tightest").tag(RingWindowPin.tightest)
                ForEach(options) { option in
                    Text(option.label).tag(option.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    private func enabledBinding(_ kind: ProviderKind) -> Binding<Bool> {
        Binding(
            get: { store.preferences.isEnabled(kind) },
            set: { store.preferences.enabled[kind] = $0 }
        )
    }

    private func ringBinding(_ kind: ProviderKind) -> Binding<String> {
        Binding(
            get: { store.preferences.ringWindows[kind] ?? RingWindowPin.tightest },
            set: { id in
                if id == RingWindowPin.tightest {
                    store.preferences.ringWindows[kind] = nil
                } else {
                    store.preferences.ringWindows[kind] = id
                }
            }
        )
    }

    private func ringOptions(for kind: ProviderKind) -> [RingWindowOption] {
        RingWindowPin.options(
            kind: kind,
            windows: store.snapshots.first { $0.kind == kind }?.windows ?? [],
            pinned: store.preferences.ringWindows[kind]
        )
    }
}
