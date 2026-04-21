import SwiftUI
import LaunchAtLogin

struct SettingsView: View {
    @EnvironmentObject private var menuBarManager: MenuBarManager
    @AppStorage("enableAnnouncements") private var enableAnnouncements = true

    var body: some View {
        Form {
            Section("General") {
                Toggle("Hide Dock Icon", isOn: $menuBarManager.isMenuBarOnly)

                LaunchAtLogin.Toggle("Launch at Login")

                Toggle("Show Announcements", isOn: $enableAnnouncements)
                    .onChange(of: enableAnnouncements) { _, newValue in
                        if newValue {
                            AnnouncementsService.shared.start()
                        } else {
                            AnnouncementsService.shared.stop()
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Power Mode Defaults (kept for legacy callers in RecorderUIManager)

enum PowerModeDefaults {
    static let autoRestoreKey = "powerModeAutoRestoreEnabled"
}
