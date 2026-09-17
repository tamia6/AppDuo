import Foundation
import Yams

public enum Recipes {
    public static func decode(_ yaml: String) throws -> Recipe {
        guard let d = try Yams.load(yaml: yaml) as? [String: Any], let id = d["bundle_id"] as? String,
              let name = d["app_name"] as? String, let raw = d["strategy"] as? String, let strategy = Strategy(rawValue: raw) else { throw CloneFailure.invalid("规则缺少 bundle_id、app_name 或 strategy") }
        var r = Recipe(bundleID: id, appName: name, strategy: strategy)
        r.stripSandbox = d["strip_sandbox"] as? Bool ?? false
        r.environment = d["environment_injection"] as? [String: String] ?? [:]
        r.symlinks = d["symlink_whitelist"] as? [String] ?? []
        r.arguments = d["launch_args"] as? [String] ?? []
        r.appType = d["app_type"] as? String ?? "generic"
        r.singleton = d["patch_framework_singleton"] as? Bool ?? false
        r.cef = d["patch_cef"] as? Bool ?? false
        r.lark = d["patch_lark_isolation"] as? Bool ?? false
        r.chatgpt = d["patch_chatgpt_isolation"] as? Bool ?? false
        r.stripURLs = d["strip_url_schemes"] as? Bool ?? false
        r.injection = Injection(rawValue: d["injection_strategy"] as? String ?? "auto") ?? .auto
        return r
    }
    public static func load(customDirectory: URL? = nil) throws -> [Recipe] {
        var recipes: [String: Recipe] = [:]
        for directory in [Assets.root.appendingPathComponent("recipes"), customDirectory].compactMap({ $0 }) {
            if !FileManager.default.fileExists(atPath: directory.path) { continue }
            for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter({ ["yaml", "yml"].contains($0.pathExtension) }) {
                let recipe = try decode(String(contentsOf: url, encoding: .utf8)); recipes[recipe.id] = recipe
            }
        }
        return recipes.values.sorted { $0.appName.localizedStandardCompare($1.appName) == .orderedAscending }
    }
    public static func match(_ info: AppInfo, recipes: [Recipe]) -> Recipe {
        if let match = recipes.first(where: { $0.bundleID == info.bundleID }) { return match }
        var recipe = Recipe(bundleID: info.bundleID, appName: info.name)
        recipe.appType = info.type; recipe.stripSandbox = true
        if ["electron", "chromium"].contains(info.type) { recipe.arguments = ["--user-data-dir={{ATB_DATA_DIR}}"] }
        else if info.type == "firefox" { recipe.strategy = .soft; recipe.arguments = ["-no-remote", "-profile", "{{ATB_DATA_DIR}}"] }
        else { recipe.environment = ["HOME": "{{ATB_DATA_DIR}}/Home", "TMPDIR": "{{ATB_DATA_DIR}}/Tmp"] }
        return recipe
    }
}
