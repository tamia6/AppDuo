import SwiftUI
import AppKit
import CloneCore

@MainActor @Observable final class AppStore {
    var records: [CloneRecord] = []
    var recipes: [Recipe] = []
    var busy = false
    var progress = ""
    var logs: [String] = []
    var error: String?
    var showingWizard = false
    var editing: CloneRecord?
    let repository = CloneRepository()
    var root: URL { repository.root }
    init() { Task { await reload() } }
    func reload() async {
        do {
            records = try await repository.load()
            recipes = try Recipes.load(customDirectory: root.appendingPathComponent("recipes"))
        } catch { self.error = error.localizedDescription }
    }
    func addLog(_ line: String) {
        progress = line; logs.append("\(Date().formatted(date: .omitted, time: .standard))  \(line)")
        if logs.count > 1000 { logs.removeFirst(logs.count - 1000) }
    }
    func build(_ config: CloneConfiguration, password: String, updating: Bool) async -> Bool {
        guard !busy else { return false }
        if updating && isRunning(config) { error = "请先退出该分身，再修改或更新。"; return false }
        busy = true; defer { busy = false }
        do {
            records = try await repository.build(config, password: password, updating: updating) { [weak self] line in
                Task { @MainActor in self?.addLog(line) }
            }
            return true
        } catch { self.error = error.localizedDescription; addLog("失败：\(error.localizedDescription)"); return false }
    }
    func update(_ record: CloneRecord) async {
        do { _ = await build(record.configuration, password: try Secrets.read(record.id), updating: true) }
        catch { self.error = error.localizedDescription }
    }
    func remove(_ record: CloneRecord, withData: Bool) async {
        if isRunning(record.configuration) { error = "请先退出该分身。"; return }
        busy = true; defer { busy = false }
        do { records = try await repository.remove(record.id, withData: withData) }
        catch { self.error = error.localizedDescription }
    }
    func isRunning(_ config: CloneConfiguration) -> Bool {
        NSWorkspace.shared.runningApplications.contains { Inspector.sameApplication($0.bundleURL, as: config.destination) }
    }
    func launch(_ record: CloneRecord) {
        let destination = record.configuration.destination
        if let running = NSWorkspace.shared.runningApplications.first(where: { Inspector.sameApplication($0.bundleURL, as: destination) }) {
            running.unhide()
            NSApp.yieldActivation(to: running)
            running.activate(from: .current, options: [.activateAllWindows])
            return
        }
        let config = NSWorkspace.OpenConfiguration(); config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: destination, configuration: config) { app, error in
            Task { @MainActor in
                if let error { self.error = error.localizedDescription }
                else if !Inspector.sameApplication(app?.bundleURL, as: destination) { self.error = "系统未打开指定的分身，请检查分身应用是否完整。" }
            }
        }
    }
}
