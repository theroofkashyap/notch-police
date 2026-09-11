import ServiceManagement

/// `SMAppService` is the source of truth. We do not persist a parallel bool,
/// because an ad-hoc rebuild can land at a new path and the system status
/// is the only one that actually launches the app.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ on: Bool) -> Bool {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return isEnabled
        } catch {
            return isEnabled
        }
    }
}
