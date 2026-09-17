import SwiftUI
import AppKit
import CloneCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = NSImage(contentsOf: Assets.icon)
        NSApp.activate(ignoringOtherApps: true)
    }
}
@main struct AppDuoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var store = AppStore()
    var body: some Scene {
        WindowGroup("AppDuo", id: "main") { ContentView(store: store).frame(minWidth: 700, minHeight: 520) }
            .defaultSize(width: 820, height: 600)
            .commands {
                CommandGroup(after: .newItem) { Button("新建分身…") { store.editing = nil; store.showingWizard = true }.keyboardShortcut("n").disabled(store.busy) }
            }
        Settings { SettingsView(root: store.root) }
    }
}
