import Foundation
import CloneCore

@main struct NativeCLI {
    static func main() async {
        do { try await run(Array(CommandLine.arguments.dropFirst())) }
        catch { FileHandle.standardError.write(Data(("错误：\(error.localizedDescription)\n").utf8)); exit(1) }
    }
    static func run(_ args: [String]) async throws {
        let command = args.first ?? "help"
        var options: [String: String] = [:], positional: [String] = []
        var i = 1
        while i < args.count {
            if args[i].hasPrefix("--") {
                let key = args[i]
                if ["--with-data", "--yes"].contains(key) { options[key] = "true"; i += 1 }
                else { guard i + 1 < args.count else { throw CloneFailure.invalid("参数缺少值：\(key)") }; options[key] = args[i + 1]; i += 2 }
            } else { positional.append(args[i]); i += 1 }
        }
        let repository = CloneRepository(root: options["--root"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("ATBCloneSwift"))
        let recipes = try Recipes.load(customDirectory: repository.root.appendingPathComponent("recipes"))
        switch command {
        case "list":
            for record in try await repository.load() { let c = record.configuration; print("\(c.name)\t\(c.recipe.strategy.rawValue)\t\(c.destination.path)") }
        case "probe":
            guard let source = positional.first else { throw CloneFailure.invalid("probe 需要 .app 路径") }
            let info = try Inspector.inspect(URL(fileURLWithPath: source)), recipe = Recipes.match(info, recipes: recipes)
            print("\(info.name)\nBundle ID: \(info.bundleID)\nVersion: \(info.version)\nType: \(info.type)\nStrategy: \(recipe.strategy.rawValue)")
        case "recipes": for recipe in recipes { print("\(recipe.bundleID)\t\(recipe.appName)\t\(recipe.strategy.rawValue)") }
        case "doctor":
            print(try Command.run("/usr/bin/sw_vers", ["-productVersion"]))
            print(try Command.run("/usr/bin/xcrun", ["--find", "clang"]))
            print(try Command.run("/usr/bin/codesign", ["--version"]))
        case "clone":
            guard let path = positional.first else { throw CloneFailure.invalid("clone 需要 .app 路径") }
            let info = try Inspector.inspect(URL(fileURLWithPath: path))
            var recipe = Recipes.match(info, recipes: recipes)
            if let raw = options["--strategy"] { guard let value = Strategy(rawValue: raw) else { throw CloneFailure.invalid("strategy 仅支持 hard_clone / soft_clone") }; recipe.strategy = value }
            let name = options["--name"] ?? info.name + " 2"
            let output = options["--output-dir"].map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) } ?? repository.root.appendingPathComponent("Apps")
            let data = options["--data-dir"].map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) } ?? repository.root.appendingPathComponent("Data/" + name)
            var config = CloneConfiguration(source: info.url, name: name, destination: output.appendingPathComponent(name + ".app"), dataDirectory: data, recipe: recipe)
            config.displayName = options["--display-name"] ?? name; config.language = options["--language"] ?? "system"
            config.customIcon = options["--icon"].map { URL(fileURLWithPath: $0) }
            if let raw = options["--injection-strategy"] { guard let value = Injection(rawValue: raw) else { throw CloneFailure.invalid("injection-strategy 仅支持 auto / dylib / launcher") }; config.injection = value }
            if let host = options["--proxy-host"] { config.proxy.enabled = true; config.proxy.host = host; config.proxy.type = options["--proxy-type"] ?? "http"; config.proxy.port = Int(options["--proxy-port"] ?? "7890") ?? 0; config.proxy.username = options["--proxy-user"] ?? "" }
            _ = try await repository.build(config, password: ProcessInfo.processInfo.environment["ATBCLONE_PROXY_PASSWORD"] ?? "", updating: false) { print($0) }
        case "update", "remove":
            guard let name = positional.first, let record = try await repository.load().first(where: { $0.configuration.name == name }) else { throw CloneFailure.invalid("找不到指定分身") }
            if command == "update" {
                _ = try await repository.build(record.configuration, password: Secrets.read(record.id), updating: true) { print($0) }
            } else {
                if options["--yes"] == nil { print("将 \(name) 移到废纸篓？输入 yes：", terminator: " "); guard readLine() == "yes" else { return } }
                _ = try await repository.remove(record.id, withData: options["--with-data"] != nil)
            }
        default:
            print("""
            ATBClone Swift CLI
            clone APP [--name NAME] [--display-name TEXT] [--icon FILE.icns]
                      [--strategy hard_clone|soft_clone] [--injection-strategy auto|dylib|launcher]
                      [--language zh-Hans|en|...] [--output-dir DIR] [--data-dir DIR]
                      [--proxy-host HOST] [--proxy-port PORT] [--proxy-type http|https|socks5] [--proxy-user USER]
            list | update NAME | remove NAME [--with-data] [--yes]
            probe APP | recipes | doctor
            代理密码通过 ATBCLONE_PROXY_PASSWORD 环境变量传入并保存到钥匙串。
            """)
        }
    }
}
