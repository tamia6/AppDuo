import Foundation

enum BinaryPatches {
    static func apply(in app: URL, recipe: Recipe, log: (String) -> Void) throws {
        let frameworks = app.appendingPathComponent("Contents/Frameworks")
        guard FileManager.default.fileExists(atPath: frameworks.path) else { return }
        // Remove stale framework versions before signing, retaining the active version.
        if let iterator = FileManager.default.enumerator(at: frameworks, includingPropertiesForKeys: nil) {
            for case let framework as URL in iterator where framework.pathExtension == "framework" {
                let versions = framework.appendingPathComponent("Versions")
                let current = versions.appendingPathComponent("Current")
                if let link = try? FileManager.default.destinationOfSymbolicLink(atPath: current.path), !link.contains("/") {
                    for version in (try? FileManager.default.contentsOfDirectory(at: versions, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])) ?? [] {
                        let value = try version.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                        if value.isDirectory == true && value.isSymbolicLink != true && version.lastPathComponent != link { try FileManager.default.removeItem(at: version) }
                    }
                }
            }
        }
        for file in try bundleFiles(frameworks) {
            if recipe.cef && file.lastPathComponent == "Chromium Embedded Framework" {
                var data = try Data(contentsOf: file)
                let patches: [(String, [(Int, String)])] = [
                    ("f50302aaf30301aaf40300aa080840b9280800b9", [(12, "28008052")]),
                    ("010a005448260035e8c343391f05007180250054", [(4, "1f2003d5"), (16, "1f2003d5")]),
                    ("e00315aae4010094f80300aa40e5054f", [(0, "34000014")]),
                    ("ff4305d1f44f13a9fd7b14a9fd030591", [(0, "d0ffff17")])
                ]
                var count = 0
                for (needle, replacements) in patches {
                    if let range = data.range(of: hex(needle)) {
                        for (offset, bytes) in replacements { data.replaceSubrange((range.lowerBound + offset)..<(range.lowerBound + offset + 4), with: hex(bytes)) }; count += 1
                    }
                }
                if count > 0 { try data.write(to: file) }
                log("CEF 兼容补丁：匹配 \(count)/4；不同版本需实际启动验证")
            }
            if recipe.singleton {
                let attributes = try file.resourceValues(forKeys: [.fileSizeKey])
                guard (attributes.fileSize ?? 0) >= 1_000_000 else { continue }
                var data = try Data(contentsOf: file, options: .mappedIfSafe)
                guard (try? MachO.integer(data, 0)) == 0xfeedfacf, (try? MachO.integer(data, 4)) == 0x0100000c,
                      let string = data.range(of: Data("Failed to create a ProcessSingleton for your profile directory.".utf8)) else { continue }
                let page = string.lowerBound & ~0xfff, pageOffset = string.lowerBound & 0xfff
                var pc: Int?
                for i in stride(from: 0, to: data.count - 8, by: 4) {
                    let w1 = try MachO.integer(data, i), w2 = try MachO.integer(data, i + 4)
                    if w1 & 0x9f000000 == 0x90000000 {
                        var imm = Int((((w1 >> 5) & 0x7ffff) << 2) | ((w1 >> 29) & 3))
                        if imm & (1 << 20) != 0 { imm -= 1 << 21 }
                        if (i & ~0xfff) + (imm << 12) == page, w2 & 0xffc00000 == 0x91000000, Int((w2 >> 10) & 0xfff) == pageOffset { pc = i; break }
                    }
                }
                guard let pc else { continue }
                var compare: Int?
                for i in stride(from: pc - 4, through: max(0, pc - 300), by: -4) {
                    if try MachO.integer(data, i) & 0xffe0001f == 0x7100001f { compare = i; break }
                }
                guard let compare else { continue }
                for i in stride(from: compare - 4, through: max(0, compare - 40), by: -4) {
                    let word = try MachO.integer(data, i)
                    if word & 0xfc000000 == 0x94000000 {
                        var imm = Int(word & 0x03ffffff); if imm & (1 << 25) != 0 { imm -= 1 << 26 }
                        let target = i + imm * 4
                        guard target >= 0, target <= data.count - 8 else { continue }
                        MachO.put(0x52800000, in: &data, at: target); MachO.put(0xd65f03c0, in: &data, at: target + 4)
                        MachO.put(0x52800000, in: &data, at: i); MachO.put(0xd503201f, in: &data, at: i + 4)
                        try data.write(to: file); log("已应用单实例兼容补丁：\(file.lastPathComponent)"); break
                    }
                }
            }
        }
    }
    private static func hex(_ string: String) -> Data {
        let chars = Array(string); return Data(stride(from: 0, to: chars.count, by: 2).map { UInt8(String(chars[$0...($0 + 1)]), radix: 16)! })
    }
}
