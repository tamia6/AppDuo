import Foundation
import Security

public enum Command {
    @discardableResult public static func run(_ executable: String, _ arguments: [String], acceptFailure: Bool = false) throws -> String {
        let task = Process(); task.executableURL = URL(fileURLWithPath: executable); task.arguments = arguments
        // A file avoids pipe-buffer deadlocks for verbose codesign/compiler output.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: url) }
        let output = try FileHandle(forWritingTo: url); defer { try? output.close() }
        task.standardOutput = output; task.standardError = output
        try task.run(); task.waitUntilExit()
        let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        if task.terminationStatus != 0 && !acceptFailure { throw CloneFailure.command("\(URL(fileURLWithPath: executable).lastPathComponent) 失败（\(task.terminationStatus)）\n\(text.suffix(5000))") }
        return text
    }
}
public enum Plist {
    public static func read(_ url: URL) throws -> [String: Any] {
        guard let data = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any] else { throw CloneFailure.invalid("无法读取 \(url.lastPathComponent)") }; return data
    }
    public static func write(_ data: [String: Any], to url: URL) throws {
        try PropertyListSerialization.data(fromPropertyList: data, format: .xml, options: 0).write(to: url, options: .atomic)
    }
}
public enum Inspector {
    public static func sameApplication(_ actual: URL?, as expected: URL) -> Bool {
        actual?.resolvingSymlinksInPath().standardizedFileURL.path == expected.resolvingSymlinksInPath().standardizedFileURL.path
    }
    public static func inspect(_ url: URL) throws -> AppInfo {
        let metadata = try Plist.read(url.appendingPathComponent("Contents/Info.plist"))
        guard url.pathExtension == "app", let id = metadata["CFBundleIdentifier"] as? String,
              let exe = metadata["CFBundleExecutable"] as? String, !exe.contains("/"), exe != "..",
              FileManager.default.isExecutableFile(atPath: url.appendingPathComponent("Contents/MacOS/" + exe).path) else { throw CloneFailure.invalid("请选择有效的 macOS .app 应用（不支持 iOS 包装应用）") }
        let binary = url.appendingPathComponent("Contents/MacOS/" + exe)
        guard binary.resolvingSymlinksInPath().path.hasPrefix(url.resolvingSymlinksInPath().path + "/") else { throw CloneFailure.invalid("主程序不能指向应用外部") }
        let frameworks = (try? FileManager.default.contentsOfDirectory(atPath: url.appendingPathComponent("Contents/Frameworks").path)) ?? []
        let type = frameworks.contains(where: { $0.contains("Electron") }) ? "electron" : frameworks.contains(where: { $0.contains("Chromium") || $0.contains("Chrome") }) ? "chromium" : id.contains("firefox") ? "firefox" : "cocoa"
        return AppInfo(url: url, bundleID: id, name: metadata["CFBundleDisplayName"] as? String ?? metadata["CFBundleName"] as? String ?? url.deletingPathExtension().lastPathComponent, executable: exe, version: metadata["CFBundleShortVersionString"] as? String ?? "", type: type)
    }
}
public enum Secrets {
    static let service = "com.atbclone.swift.proxy"
    public static func read(_ id: UUID) throws -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id.uuidString, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?; let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data else { throw CloneFailure.invalid("钥匙串读取失败：\(status)") }
        return String(decoding: data, as: UTF8.self)
    }
    public static func save(_ password: String, id: UUID) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id.uuidString]
        if password.isEmpty { SecItemDelete(query as CFDictionary); return }
        let values = [kSecValueData as String: Data(password.utf8)]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            let added = SecItemAdd(query.merging(values) { _, b in b } as CFDictionary, nil)
            guard added == errSecSuccess else { throw CloneFailure.invalid("钥匙串保存失败：\(added)") }
        } else if status != errSecSuccess { throw CloneFailure.invalid("钥匙串保存失败：\(status)") }
    }
}
