import Foundation
import Darwin

public actor CloneRepository {
    public nonisolated let root: URL
    public static let defaultRoot = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("AppDuo")
    public init(root: URL = CloneRepository.defaultRoot) { self.root = root }
    // Existing clones embed their data paths. Keep those paths valid without moving live data.
    static func prepareRoot(_ root: URL, legacy: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: root.path), fm.fileExists(atPath: legacy.path) {
            try fm.createSymbolicLink(at: root, withDestinationURL: legacy)
        }
    }
    private func prepareDefaultRoot() throws {
        if root == Self.defaultRoot {
            try Self.prepareRoot(root, legacy: root.deletingLastPathComponent().appendingPathComponent("ATBCloneSwift"))
        }
    }
    public func load() throws -> [CloneRecord] {
        try prepareDefaultRoot()
        let file = root.appendingPathComponent("clones.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        return try JSONDecoder().decode([CloneRecord].self, from: Data(contentsOf: file))
    }
    private func locked<T>(_ operation: () throws -> T) throws -> T {
        try prepareDefaultRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fd = open(root.appendingPathComponent(".lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw CloneFailure.invalid("无法锁定分身记录") }
        defer { flock(fd, LOCK_UN); close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw CloneFailure.invalid("另一个窗口正在操作分身，请稍后重试") }
        return try operation()
    }
    public func build(_ configuration: CloneConfiguration, password: String, updating: Bool, log: @Sendable (String) -> Void) throws -> [CloneRecord] {
        try locked {
            var records = try load()
            let previous = records.first { $0.id == configuration.id }
            if updating { guard let previous, previous.configuration.destination == configuration.destination else { throw CloneFailure.invalid("找不到待更新分身") } }
            else { guard !records.contains(where: { $0.configuration.destination == configuration.destination || $0.configuration.name == configuration.name }) else { throw CloneFailure.invalid("分身名称或位置已存在") } }
            try Secrets.save(password, id: configuration.id)
            var record = try CloneEngine().build(configuration, password: password, updating: updating, log: log)
            if let previous { record.createdAt = previous.createdAt }
            records.removeAll { $0.id == record.id }; records.append(record)
            try save(records); return records
        }
    }
    public func remove(_ id: UUID, withData: Bool) throws -> [CloneRecord] {
        try locked {
            var records = try load()
            guard let record = records.first(where: { $0.id == id }) else { throw CloneFailure.invalid("找不到分身") }
            try record.configuration.validate()
            if withData {
                let data = record.configuration.dataDirectory.resolvingSymlinksInPath()
                let allowed = root.appendingPathComponent("Data").resolvingSymlinksInPath().path + "/"
                guard data.path.hasPrefix(allowed) else { throw CloneFailure.invalid("自定义数据目录请在 Finder 中手动移除") }
            }
            let app = record.configuration.destination
            if FileManager.default.fileExists(atPath: app.path) {
                let info = try Inspector.inspect(app)
                guard info.bundleID == record.configuration.bundleID else { throw CloneFailure.invalid("目标应用已改变，拒绝删除") }
                // Trash is reversible and does not invoke a privileged shell.
                try FileManager.default.trashItem(at: app, resultingItemURL: nil)
            }
            if withData {
                let data = record.configuration.dataDirectory.resolvingSymlinksInPath()
                let allowed = root.appendingPathComponent("Data").resolvingSymlinksInPath().path + "/"
                guard data.path.hasPrefix(allowed) else { throw CloneFailure.invalid("自定义数据目录请在 Finder 中手动移除") }
                if FileManager.default.fileExists(atPath: data.path) { try FileManager.default.trashItem(at: data, resultingItemURL: nil) }
            }
            records.removeAll { $0.id == id }; try save(records); try Secrets.save("", id: id); return records
        }
    }
    private func save(_ records: [CloneRecord]) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(to: root.appendingPathComponent("clones.json"), options: .atomic)
    }
}
