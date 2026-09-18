import Foundation

public enum CloneUpdates {
    public static func availableVersion(for config: CloneConfiguration) throws -> String? {
        guard config.recipe.strategy == .hard else { return nil }
        let source = try Plist.read(config.source.appendingPathComponent("Contents/Info.plist"))
        let clone = try Plist.read(config.destination.appendingPathComponent("Contents/Info.plist"))
        guard source["CFBundleIdentifier"] as? String == config.recipe.bundleID,
              clone["CFBundleIdentifier"] as? String == config.bundleID else { return nil }
        let newVersion = source["CFBundleShortVersionString"] as? String ?? ""
        let oldVersion = clone["CFBundleShortVersionString"] as? String ?? ""
        let newBuild = source["CFBundleVersion"] as? String ?? ""
        let oldBuild = clone["CFBundleVersion"] as? String ?? ""
        if !newVersion.isEmpty, !oldVersion.isEmpty, newVersion != oldVersion {
            return newVersion.compare(oldVersion, options: .numeric) == .orderedDescending ? newVersion : nil
        }
        if newVersion == oldVersion, !newBuild.isEmpty, !oldBuild.isEmpty,
           newBuild.compare(oldBuild, options: .numeric) == .orderedDescending {
            return newVersion.isEmpty ? newBuild : "\(newVersion) (\(newBuild))"
        }
        return nil
    }
}
