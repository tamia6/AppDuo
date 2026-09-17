import SwiftUI
import AppKit
import CloneCore

final class AppDelegate: NSObject, NSApplicationDelegate {
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
        WindowGroup("AppDuo", id: "main") { ContentView(store: store).frame(minWidth: 940, minHeight: 650) }
            .defaultSize(width: 1120, height: 760)
            .commands {
                CommandGroup(after: .newItem) { Button("新建分身…") { store.editing = nil; store.showingWizard = true }.keyboardShortcut("n").disabled(store.busy) }
            }
        Settings { SettingsView(root: store.root) }
        MenuBarExtra("AppDuo", systemImage: "square.on.square") {
            ForEach(store.records) { record in Button(String(record.configuration.name.prefix(28))) { store.launch(record) } }
            Divider()
            Button("打开主窗口") { NSApp.activate(ignoringOtherApps: true); NSApp.windows.first { $0.identifier?.rawValue.contains("main") == true }?.makeKeyAndOrderFront(nil) }
            Button("退出") { NSApp.terminate(nil) }
        }
    }
}
