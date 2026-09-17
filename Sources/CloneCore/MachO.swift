import Foundation

/// Bounds-checked Mach-O reads; malformed or unsupported binaries are never patched.
public enum MachO {
    static func integer(_ data: Data, _ offset: Int, _ count: Int = 4, big: Bool = false) throws -> UInt64 {
        guard offset >= 0, count <= 8, offset <= data.count - count else { throw CloneFailure.invalid("Mach-O 数据越界") }
        var result: UInt64 = 0
        for i in 0..<count { result |= UInt64(data[offset + i]) << (8 * (big ? count - i - 1 : i)) }; return result
    }
    static func put(_ value: UInt64, in data: inout Data, at offset: Int, count: Int = 4) {
        for i in 0..<count { data[offset + i] = UInt8(truncatingIfNeeded: value >> (8 * i)) }
    }
    static func slices(_ data: Data) throws -> [(Int, Int)] {
        let magic = try integer(data, 0, big: true)
        if magic == 0xcafebabe || magic == 0xcafebabf {
            let wide = magic == 0xcafebabf, n = Int(try integer(data, 4, big: true)), stride = wide ? 32 : 20
            guard n > 0, n <= 32 else { throw CloneFailure.invalid("无效的通用二进制架构数") }
            return try (0..<n).map { i in
                let p = 8 + i * stride
                let offset = try integer(data, p + 8, wide ? 8 : 4, big: true)
                let size = try integer(data, p + (wide ? 16 : 12), wide ? 8 : 4, big: true)
                guard offset <= data.count, size <= data.count - Int(offset) else { throw CloneFailure.invalid("无效的 Mach-O slice") }
                return (Int(offset), Int(size))
            }
        }
        return [(0, data.count)]
    }
    public static func isExecutable(_ url: URL) -> Bool {
        guard let file = try? FileHandle(forReadingFrom: url) else { return false }; defer { try? file.close() }
        guard let header = try? file.read(upToCount: 4096), header.count >= 16 else { return false }
        do {
            let magic = try integer(header, 0, big: true)
            if magic == 0xcafebabe || magic == 0xcafebabf {
                let offset = try integer(header, 16, magic == 0xcafebabf ? 8 : 4, big: true)
                try file.seek(toOffset: offset)
                guard let slice = try file.read(upToCount: 16) else { return false }
                return try executableHeader(slice)
            }
            return try executableHeader(header)
        } catch { return false }
    }
    static func executableHeader(_ data: Data) throws -> Bool {
        let magic = try integer(data, 0)
        let big = magic == 0xcffaedfe || magic == 0xcefaedfe
        guard [0xfeedfacf, 0xfeedface, 0xcffaedfe, 0xcefaedfe].contains(magic) else { return false }
        return try integer(data, 12, big: big) == 2
    }
    public static func inject(_ original: Data, library: String) throws -> Data {
        var data = original
        let path = Array(library.utf8) + [0], length = 24 + ((path.count + 7) & ~7)
        for (offset, size) in try slices(data) {
            guard try integer(data, offset) == 0xfeedfacf, try integer(data, offset + 12) == 2 else { throw CloneFailure.invalid("注入仅支持 64 位 Mach-O 可执行文件") }
            let commands = Int(try integer(data, offset + 16)), bytes = Int(try integer(data, offset + 20))
            guard bytes <= size - 32, commands <= bytes / 8 else { throw CloneFailure.invalid("无效的 Mach-O load commands") }
            var p = offset + 32, first = size, alreadyLoaded = false
            let end = offset + 32 + bytes
            for _ in 0..<commands {
                let cmd = try integer(data, p), len = Int(try integer(data, p + 4))
                guard len >= 8, p <= end - len else { throw CloneFailure.invalid("Mach-O load command 越界") }
                if cmd == 0xc, len >= 24 {
                    let strOffset = Int(try integer(data, p + 8))
                    if strOffset >= 24, strOffset < len {
                        let actual = data[(p + strOffset)..<(p + len)].prefix(while: { $0 != 0 })
                        alreadyLoaded = alreadyLoaded || String(decoding: actual, as: UTF8.self) == library
                    }
                }
                if cmd == 0x19 {
                    guard len >= 72 else { throw CloneFailure.invalid("无效的 segment") }
                    let count = Int(try integer(data, p + 64)); guard count <= (len - 72) / 80 else { throw CloneFailure.invalid("无效的 section") }
                    for s in 0..<count {
                        let section = p + 72 + s * 80
                        let start = Int(try integer(data, section + 48)), n = try integer(data, section + 40, 8)
                        if n > 0, start > 0 { first = min(first, start) }
                    }
                }
                p += len
            }
            if alreadyLoaded { continue }
            guard p == end, first <= size, first - (32 + bytes) >= length,
                  data[end..<(end + length)].allSatisfy({ $0 == 0 }) else { throw CloneFailure.invalid("Mach-O 头部空间不足，改用启动器方案") }
            put(0xc, in: &data, at: end); put(UInt64(length), in: &data, at: end + 4); put(24, in: &data, at: end + 8)
            data.replaceSubrange((end + 24)..<(end + 24 + path.count), with: path)
            put(UInt64(commands + 1), in: &data, at: offset + 16); put(UInt64(bytes + length), in: &data, at: offset + 20)
        }
        return data
    }
}
public enum ProcessNames {
    /// Retain compatibility aliases, rejecting all collisions before touching files.
    public static func rename(in app: URL, main: URL, name: String) throws {
        try validateName(name)
        let fm = FileManager.default
        var moves: [URL: URL] = [:], plists: [URL] = []
        for file in try bundleFiles(app) {
            if file.lastPathComponent == "Info.plist" { plists.append(file) }
            if fm.isExecutableFile(atPath: file.path), MachO.isExecutable(file) {
                let target = file.deletingLastPathComponent().appendingPathComponent(file.standardizedFileURL.path == main.standardizedFileURL.path ? name : name + "-" + file.lastPathComponent)
                if target.path != file.path { moves[file] = target }
            }
        }
        let targets = Set(moves.values)
        guard targets.count == moves.count else { throw CloneFailure.invalid("进程名冲突") }
        for target in targets {
            if (try? target.resourceValues(forKeys: [.isSymbolicLinkKey])) != nil { throw CloneFailure.invalid("进程名与已有文件冲突：\(target.lastPathComponent)") }
        }
        var updates: [(URL, [String: Any])] = []
        for plist in plists {
            var d = try Plist.read(plist)
            if let exe = d["CFBundleExecutable"] as? String {
                let folder = plist.deletingLastPathComponent()
                let binary = (folder.lastPathComponent == "Contents" ? folder.appendingPathComponent("MacOS") : folder).appendingPathComponent(exe)
                if let target = moves.first(where: { $0.key.path == binary.path })?.value { d["CFBundleExecutable"] = target.lastPathComponent; updates.append((plist, d)) }
            }
        }
        for (old, target) in moves { try fm.moveItem(at: old, to: target); try fm.createSymbolicLink(atPath: old.path, withDestinationPath: target.lastPathComponent) }
        for (url, plist) in updates { try Plist.write(plist, to: url) }
    }
}
func bundleFiles(_ app: URL) throws -> [URL] {
    var failure: Error?
    guard let iterator = FileManager.default.enumerator(at: app, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], errorHandler: { _, error in failure = error; return false }) else { throw CloneFailure.invalid("无法遍历应用") }
    var files: [URL] = []
    for case let url as URL in iterator {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        if values.isRegularFile == true && values.isSymbolicLink != true { files.append(url) }
    }
    if let failure { throw failure }; return files
}
