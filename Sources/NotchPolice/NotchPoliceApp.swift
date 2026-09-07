import AppKit
import SwiftUI
import UserNotifications
import NotchPoliceCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = UsageStore()
    private var notch: NotchWindowController?

    private static let hasLaunchedKey = "notchpolice.hasLaunched"

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableSuddenTermination()
        ProcessInfo.processInfo.disableAutomaticTermination("notch overlay")
        NSApp.setActivationPolicy(store.preferences.showDockIcon ? .regular : .accessory)
        notch = NotchWindowController(store: store)
        store.onLowRemaining = { snap, remaining in
            Self.notify(snap, remaining: remaining)
        }
        store.start()
        notch?.reposition()

        // Only introduce itself once. Opening Settings on every launch forces a
        // Dock icon and steals focus from whatever the user was doing.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Self.hasLaunchedKey) {
            defaults.set(true, forKey: Self.hasLaunchedKey)
            showSettings()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func showSettings() {
        NotchWindowController.showSettings()
    }

    func refresh() {
        Task { await store.refresh() }
    }

    func copyContext() {
        guard let kind = store.hovered ?? store.dyingKind ?? store.visibleSnapshots.first?.kind else { return }
        Task { @MainActor in
            Clipboard.copy(await store.handover(for: kind))
        }
    }

    func previewContext() {
        guard let kind = store.hovered ?? store.dyingKind ?? store.visibleSnapshots.first?.kind else { return }
        notch?.showPreview(for: kind)
    }

    func hideHour() { store.hide(for: 3600) }
    func showNotch() { store.reveal() }

    private static func notify(_ snap: ProviderSnapshot, remaining: Double) {
        let content = UNMutableNotificationContent()
        content.title = "Notch Police"
        content.body = "\(snap.displayName) has \(Int(remaining.rounded()))% left. Hover the notch and copy context to continue on another agent."
        let request = UNNotificationRequest(
            identifier: "notchpolice.\(snap.kind.rawValue).\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        let parts = store.visibleSnapshots.compactMap { snap -> String? in
            guard let remaining = snap.primaryRemaining, snap.isLive else { return nil }
            return "\(snap.kind.shortName) \(Int(remaining.rounded()))"
        }
        Text(parts.isEmpty ? "NP" : parts.joined(separator: "  "))
    }
}

struct MenuBarMenu: View {
    @ObservedObject var store: UsageStore
    var delegate: AppDelegate

    var body: some View {
        SettingsLink { Text("Settings…") }
        Button("Refresh now") { delegate.refresh() }
        Button("Copy dying context") { delegate.copyContext() }
        Button("Preview context…") { delegate.previewContext() }
        Divider()
        Button("Hide notch for 1 hour") { delegate.hideHour() }
        Button("Show notch") { delegate.showNotch() }
        Divider()
        Button("Quit Notch Police") { NSApp.terminate(nil) }
    }
}

@main
struct NotchPoliceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu(store: appDelegate.store, delegate: appDelegate)
        } label: {
            MenuBarLabel(store: appDelegate.store)
        }
        Settings {
            SettingsView(store: appDelegate.store)
        }
    }
}
