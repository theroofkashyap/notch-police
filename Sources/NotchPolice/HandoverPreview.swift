import AppKit
import SwiftUI
import NotchPoliceCore

struct HandoverPreviewView: View {
    var kind: ProviderKind
    var project: String?
    var text: String
    var onCopy: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ProviderMark(kind: kind)
                    .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Handover from \(kind.displayName)")
                        .font(.system(size: 13, weight: .semibold))
                    Text(scopeCopy)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            ScrollView {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text("This is your own conversation text. Read it before pasting it somewhere else.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Close", action: onClose)
                Button("Copy to clipboard", action: onCopy)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 560, height: 520)
    }

    private var scopeCopy: String {
        let where_ = project.map { "project \($0)" } ?? "no project detected"
        return "\(where_) · \(text.count) characters"
    }
}

/// Shows the handover text before it reaches the clipboard. The one-click path
/// on the notch stays as it is; this exists for when you want to see exactly
/// what is about to leave the machine.
@MainActor
final class HandoverPreviewWindow: NSObject {
    private var window: NSWindow?

    func show(kind: ProviderKind, project: String?, text: String) {
        let view = HandoverPreviewView(
            kind: kind,
            project: project,
            text: text,
            onCopy: { [weak self] in
                Clipboard.copy(text)
                self?.close()
            },
            onClose: { [weak self] in self?.close() }
        )
        let controller = NSHostingController(rootView: view)
        if let window {
            window.contentViewController = controller
        } else {
            let created = NSWindow(contentViewController: controller)
            created.styleMask = [.titled, .closable]
            created.title = "Context handover"
            created.isReleasedWhenClosed = false
            created.center()
            window = created
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func close() {
        window?.orderOut(nil)
    }
}
