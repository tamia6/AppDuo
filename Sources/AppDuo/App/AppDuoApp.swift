import SwiftUI
import AppKit
import CloneCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    var isBusy: () -> Bool = { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { isBusy() ? .terminateCancel : .terminateNow }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = NSImage(contentsOf: Assets.icon)
        NSApp.activate(ignoringOtherApps: true)
    }
}
@main enum AppDuoMain {
    static func main() {
        if CommandLine.arguments.contains("--check-resources") {
            do {
                let root = Assets.root.resolvingSymlinksInPath()
                let packaged = Bundle.main.resourceURL!.resolvingSymlinksInPath().path + "/"
                guard root.path.hasPrefix(packaged), NSImage(contentsOf: Assets.icon) != nil,
                      FileManager.default.fileExists(atPath: root.appendingPathComponent("Isolation.m").path),
                      !(try Recipes.load()).isEmpty else {
                    throw CloneFailure.invalid("打包资源缺失或来自构建目录")
                }
                print("Packaged resources OK: \(root.path)")
            } catch {
                FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
                exit(1)
            }
            return
        }
        AppDuoApp.main()
    }
}

struct AppDuoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var store = AppStore()
    @StateObject private var updater = AppUpdater()
    var body: some Scene {
        WindowGroup("AppDuo", id: "main") { ContentView(store: store).frame(minWidth: 700, minHeight: 520)
            .onAppear {
                delegate.isBusy = { store.busy }
                store.busyDidChange = { [weak updater = updater] busy in updater?.cloneOperationChanged(isBusy: busy) }
                updater.start(isBusy: { store.busy })
            } }
            .defaultSize(width: 820, height: 600)
            .commands {
                CommandGroup(after: .appInfo) { Button("检查更新…") { updater.checkForUpdates() }.disabled(!updater.canCheckForUpdates) }
                CommandGroup(after: .newItem) { Button("新建分身…") { store.editing = nil; store.showingWizard = true }.keyboardShortcut("n").disabled(store.busy) }
            }
        Settings { SettingsView(root: store.root) }
    }
}
