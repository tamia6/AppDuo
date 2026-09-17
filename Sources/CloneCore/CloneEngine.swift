import Foundation
import AppKit

public struct CloneEngine {
    public init() {}
    /// Build beside the destination, verify, then swap. Failure never deletes the old clone.
    public func build(_ config: CloneConfiguration, password: String = "", updating: Bool = false, log: (String) -> Void = { _ in }) throws -> CloneRecord {
        try config.validate()
        let fm = FileManager.default, info = try Inspector.inspect(config.source)
        guard info.bundleID == config.recipe.bundleID else { throw CloneFailure.invalid("所选规则与原应用 Bundle ID 不一致") }
        let destination = config.destination
        if updating && NSWorkspace.shared.runningApplications.contains(where: { $0.bundleURL?.standardizedFileURL.path == destination.standardizedFileURL.path || $0.bundleIdentifier == config.bundleID }) {
            throw CloneFailure.invalid("请先退出分身，再执行更新")
        }
        guard updating || !fm.fileExists(atPath: destination.path) else { throw CloneFailure.invalid("目标应用已存在，请使用更新操作") }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".atb-\(UUID().uuidString).app")
        defer { try? fm.removeItem(at: staging) }
        log("复制应用与资源…")
        let macos = staging.appendingPathComponent("Contents/MacOS"), resources = staging.appendingPathComponent("Contents/Resources")
        if config.recipe.strategy == .hard {
            try Command.run("/bin/cp", ["-cR", config.source.path, staging.path])
            try Command.run("/bin/chmod", ["-R", "u+w", staging.path])
        } else {
            try fm.createDirectory(at: macos, withIntermediateDirectories: true)
            let originalResources = config.source.appendingPathComponent("Contents/Resources")
            if fm.fileExists(atPath: originalResources.path) { try fm.copyItem(at: originalResources, to: resources) }
            try fm.copyItem(at: config.source.appendingPathComponent("Contents/Info.plist"), to: staging.appendingPathComponent("Contents/Info.plist"))
        }
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        try fm.createDirectory(at: config.dataDirectory, withIntermediateDirectories: true)
        let metadataURL = staging.appendingPathComponent("Contents/Info.plist")
        var metadata = try Plist.read(metadataURL)
        metadata["CFBundleIdentifier"] = config.bundleID
        metadata["CFBundleName"] = config.displayName
        metadata["CFBundleDisplayName"] = config.displayName
        metadata.removeValue(forKey: "TeamIdentifier"); metadata.removeValue(forKey: "LSHasLocalizedDisplayName")
        if config.recipe.stripURLs || config.recipe.lark || config.recipe.chatgpt { metadata.removeValue(forKey: "CFBundleURLTypes") }
        // Use installed bytes on update; the original selected file may no longer exist.
        let installedIcon = destination.appendingPathComponent("Contents/Resources/ATBCloneIcon.icns")
        let icon = config.customIcon ?? (updating && fm.fileExists(atPath: installedIcon.path) ? installedIcon : nil)
        if let icon {
            let bytes = try Data(contentsOf: icon)
            guard bytes.count >= 8, bytes.prefix(4) == Data("icns".utf8) else { throw CloneFailure.invalid("请选择有效的 .icns 图标") }
            try bytes.write(to: resources.appendingPathComponent("ATBCloneIcon.icns"), options: .atomic)
            metadata["CFBundleIconFile"] = "ATBCloneIcon.icns"; metadata.removeValue(forKey: "CFBundleIconName")
        }
        try Plist.write(metadata, to: metadataURL)
        for file in try bundleFiles(staging) where file.lastPathComponent == "InfoPlist.strings" {
            if var strings = try? Plist.read(file) {
                for key in ["CFBundleDisplayName", "CFBundleName", "CFBundleGetInfoString"] { strings.removeValue(forKey: key) }
                try Plist.write(strings, to: file)
            }
        }
        let env = try RuntimeBuilder.environment(config, password: password)
        try prepareData(config, env: env)
        let args = RuntimeBuilder.arguments(config)
        log("配置独立数据、语言和进程名称…")
        if config.recipe.strategy == .hard {
            let main = macos.appendingPathComponent(info.executable)
            let frameworks = staging.appendingPathComponent("Contents/Frameworks")
            try fm.createDirectory(at: frameworks, withIntermediateDirectories: true)
            let library = "@executable_path/../Frameworks/libatbclone_env.dylib"
            let raw = try Data(contentsOf: main, options: .mappedIfSafe)
            let injected = try? MachO.inject(raw, library: library)
            let needsHook = config.recipe.lark || config.recipe.chatgpt
            let useDylib = config.injection == .dylib || (config.injection == .auto && args.isEmpty && !needsHook && injected != nil)
            if useDylib {
                guard !needsHook, let injected else { throw CloneFailure.invalid("此应用无法安全使用 dylib 注入，请选择自动或启动器") }
                try RuntimeBuilder.dylib(output: frameworks.appendingPathComponent("libatbclone_env.dylib"), env: env)
                try injected.write(to: main)
            }
            try ProcessNames.rename(in: staging, main: main, name: config.name)
            if !useDylib {
                if needsHook {
                    try RuntimeBuilder.compile(String(contentsOf: Assets.root.appendingPathComponent("Isolation.m"), encoding: .utf8), output: frameworks.appendingPathComponent("libatbclone_hook.dylib"), library: true, objc: true)
                }
                let launcherName = config.name + "-Launcher"
                let launcher = macos.appendingPathComponent(launcherName)
                guard !fm.fileExists(atPath: launcher.path) else { throw CloneFailure.invalid("启动器名称冲突") }
                try RuntimeBuilder.launcher(output: launcher, target: config.name, relative: true, env: env, arguments: args, hook: needsHook)
                var plist = try Plist.read(metadataURL); plist["CFBundleExecutable"] = launcherName; try Plist.write(plist, to: metadataURL)
            }
            try BinaryPatches.apply(in: staging, recipe: config.recipe, log: log)
            try updateHelperIDs(staging, originalID: info.bundleID, newID: config.bundleID)
        } else {
            let launcher = config.name + "-Launcher"
            try RuntimeBuilder.launcher(output: macos.appendingPathComponent(launcher), target: config.source.appendingPathComponent("Contents/MacOS/" + info.executable).path, relative: false, env: env, arguments: args, hook: false)
            metadata = try Plist.read(metadataURL); metadata["CFBundleExecutable"] = launcher; try Plist.write(metadata, to: metadataURL)
        }
        log("重新签名并验证…")
        try Command.run("/usr/bin/xattr", ["-cr", staging.path])
        try sign(staging, stripSandbox: config.recipe.stripSandbox)
        try Command.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", staging.path])
        log("安装已验证的分身…")
        let backup = destination.deletingLastPathComponent().appendingPathComponent(".atb-backup-\(UUID().uuidString).app")
        let hadOld = fm.fileExists(atPath: destination.path)
        if hadOld { try fm.moveItem(at: destination, to: backup) }
        do { try fm.moveItem(at: staging, to: destination) }
        catch { if hadOld { try fm.moveItem(at: backup, to: destination) }; throw error }
        if hadOld { try fm.removeItem(at: backup) }
        _ = try? Command.run("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister", ["-f", destination.path])
        var stored = config; stored.customIcon = nil
        log("完成：\(config.name)")
        return CloneRecord(configuration: stored)
    }
    private func prepareData(_ config: CloneConfiguration, env: [String: String]) throws {
        let fm = FileManager.default
        for key in ["HOME", "TMPDIR", "CODEX_HOME", "GEMINI_HOME", "CLAUDE_CONFIG_DIR"] {
            if let path = env[key] { try fm.createDirectory(atPath: path, withIntermediateDirectories: true) }
        }
        if let home = env["HOME"], home != NSHomeDirectory() {
            for relative in config.recipe.symlinks {
                let source = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(relative)
                let target = URL(fileURLWithPath: home).appendingPathComponent(relative)
                if fm.fileExists(atPath: source.path), !fm.fileExists(atPath: target.path) {
                    try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.createSymbolicLink(at: target, withDestinationURL: source)
                }
            }
        }
        if config.language != "system" {
            let home = URL(fileURLWithPath: env["HOME"] ?? config.dataDirectory.path)
            let prefs = home.appendingPathComponent("Library/Preferences")
            try fm.createDirectory(at: prefs, withIntermediateDirectories: true)
            for filename in [".GlobalPreferences", config.bundleID, config.recipe.bundleID] {
                let file = prefs.appendingPathComponent(filename + ".plist")
                var plist = (try? Plist.read(file)) ?? [:]
                plist["AppleLanguages"] = [config.language]; plist["AppleLocale"] = RuntimeBuilder.localeID(config.language)
                try Plist.write(plist, to: file)
            }
        }
    }
    private func updateHelperIDs(_ app: URL, originalID: String, newID: String) throws {
        for file in try bundleFiles(app) where file.lastPathComponent == "Info.plist" {
            var plist = try Plist.read(file)
            if let id = plist["CFBundleIdentifier"] as? String, id != newID, id.hasPrefix(originalID + ".") {
                plist["CFBundleIdentifier"] = newID + id.dropFirst(originalID.count)
                try Plist.write(plist, to: file)
            }
        }
    }
    private func sign(_ app: URL, stripSandbox: Bool) throws {
        let fm = FileManager.default
        let files = try bundleFiles(app).sorted { a, b in
            let aLibrary = ["dylib", "so"].contains(a.pathExtension), bLibrary = ["dylib", "so"].contains(b.pathExtension)
            if aLibrary != bLibrary { return aLibrary }; return a.path.count > b.path.count
        }
        for file in files where MachO.isExecutable(file) || ["dylib", "so"].contains(file.pathExtension) {
            let entitlements = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".plist")
            defer { try? fm.removeItem(at: entitlements) }
            let raw = try Command.run("/usr/bin/codesign", ["-d", "--entitlements", ":-", file.path], acceptFailure: true)
            var attrs: [String: Any] = [:]
            if let begin = raw.range(of: "<?xml"), let end = raw.range(of: "</plist>", range: begin.lowerBound..<raw.endIndex),
               let parsed = try? PropertyListSerialization.propertyList(from: Data(raw[begin.lowerBound..<end.upperBound].utf8), format: nil) as? [String: Any] { attrs = parsed }
            // Third-party team/application entitlements cannot be granted by ad-hoc signing.
            for key in Array(attrs.keys) where key.hasPrefix("com.apple.developer.") || key.hasPrefix("com.apple.private.") || ["com.apple.application-identifier", "application-identifier", "keychain-access-groups"].contains(key) { attrs.removeValue(forKey: key) }
            if stripSandbox {
                for key in Array(attrs.keys) where key.hasPrefix("com.apple.security.application-groups") || key == "com.apple.security.app-sandbox" || key == "keychain-access-groups" { attrs.removeValue(forKey: key) }
            }
            attrs["com.apple.security.cs.disable-library-validation"] = true
            attrs["com.apple.security.cs.allow-jit"] = true
            attrs["com.apple.security.cs.allow-unsigned-executable-memory"] = true
            try Plist.write(attrs, to: entitlements)
            try Command.run("/usr/bin/codesign", ["--force", "--sign", "-", "--entitlements", entitlements.path, file.path])
        }
        // Sign nested containers deepest-first, then seal the root bundle.
        if let iterator = fm.enumerator(at: app, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
            let containers = iterator.compactMap { $0 as? URL }.filter { ["app", "framework", "appex", "xpc"].contains($0.pathExtension) && (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true }.sorted { $0.path.count > $1.path.count }
            for bundle in containers { try Command.run("/usr/bin/codesign", ["--force", "--sign", "-", "--preserve-metadata=entitlements", bundle.path]) }
        }
        try Command.run("/usr/bin/codesign", ["--force", "--sign", "-", "--preserve-metadata=entitlements", app.path])
    }
}
