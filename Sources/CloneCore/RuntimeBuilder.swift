import Foundation

/// Small native runtime shims are compiled with Apple's toolchain; orchestration stays in Swift.
enum RuntimeBuilder {
    static func literal(_ value: String) -> String {
        // Octal byte escapes avoid C interpolation and hexadecimal escape ambiguity.
        "\"" + value.utf8.map { String(format: "\\%03o", $0) }.joined() + "\""
    }
    static func compile(_ source: String, output: URL, library: Bool = false, objc: Bool = false) throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + (objc ? ".m" : ".c"))
        try source.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        var args = ["--sdk", "macosx", "clang", "-O2", "-arch", "arm64", "-arch", "x86_64", "-Wl,-headerpad_max_install_names"]
        if library { args += ["-dynamiclib"] }
        if objc { args += ["-framework", "Foundation"] }
        args += [file.path, "-o", output.path]
        try Command.run("/usr/bin/xcrun", args)
    }
    static func environment(_ config: CloneConfiguration, password: String) throws -> [String: String] {
        var env = config.recipe.environment.mapValues { $0.replacingOccurrences(of: "{{ATB_DATA_DIR}}", with: config.dataDirectory.path) }
        if config.recipe.strategy == .hard && !config.recipe.arguments.contains(where: { $0.contains("{{ATB_DATA_DIR}}") }) && !config.recipe.environment.values.contains(where: { $0.contains("{{ATB_DATA_DIR}}") }) {
            env["HOME"] = config.dataDirectory.appendingPathComponent("Home").path
            env["TMPDIR"] = config.dataDirectory.appendingPathComponent("Tmp").path
        }
        env["REAL_USER_HOME"] = NSHomeDirectory()
        if config.language != "system" {
            let locale = localeID(config.language)
            env["LANG"] = locale + ".UTF-8"; env["LC_ALL"] = locale + ".UTF-8"; env["LANGUAGE"] = config.language
        }
        if config.proxy.enabled {
            let url = try config.proxy.url(password: password)
            for key in ["HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy"] { env[key] = url }
            env["NO_PROXY"] = config.proxy.noProxy; env["no_proxy"] = config.proxy.noProxy
        }
        return env
    }
    static func localeID(_ language: String) -> String {
        ["zh-Hans": "zh_CN", "zh-Hant": "zh_TW", "en": "en_US", "ja": "ja_JP", "ko": "ko_KR", "de": "de_DE", "fr": "fr_FR", "es": "es_ES", "ru": "ru_RU"][language] ?? language
    }
    static func arguments(_ config: CloneConfiguration) -> [String] {
        var args = config.recipe.arguments.map { $0.replacingOccurrences(of: "{{ATB_DATA_DIR}}", with: config.dataDirectory.path) }
        if config.language != "system" {
            if ["chromium", "electron"].contains(config.recipe.appType) {
                args.removeAll { $0.hasPrefix("--lang=") }
                let lang = ["zh-Hans": "zh-CN", "zh-Hant": "zh-TW"][config.language] ?? config.language
                args.append("--lang=" + lang)
            } else if config.recipe.appType != "firefox" {
                args += ["-AppleLanguages", "(\(config.language))", "-AppleLocale", localeID(config.language)]
            }
        }
        return args
    }
    static func launcher(output: URL, target: String, relative: Bool, env: [String: String], arguments: [String], hook: Bool) throws {
        let setenvs = env.sorted(by: { $0.key < $1.key }).map { "setenv(\(literal($0.key)), \(literal($0.value)), 1);" }.joined(separator: "\n")
        let args = arguments.enumerated().map { "args[\($0.offset + 1)] = \(literal($0.element));" }.joined(separator: "\n")
        let targetCode = relative ? "snprintf(target, sizeof(target), \"%s/%s\", dirname(exe), \(literal(target)));" : "snprintf(target, sizeof(target), \"%s\", \(literal(target)));"
        try compile("""
        #include <stdlib.h>
        #include <stdio.h>
        #include <unistd.h>
        #include <limits.h>
        #include <libgen.h>
        #include <mach-o/dyld.h>
        int main(int argc, char **argv) {
            char exe[PATH_MAX], target[PATH_MAX]; uint32_t n = sizeof(exe);
            if (_NSGetExecutablePath(exe, &n) != 0) return 1;
            \(setenvs)
            \(hook ? "char hook[PATH_MAX]; char copy[PATH_MAX]; snprintf(copy, sizeof(copy), \"%s\", exe); snprintf(hook, sizeof(hook), \"%s/../Frameworks/libatbclone_hook.dylib\", dirname(copy)); setenv(\"DYLD_INSERT_LIBRARIES\", hook, 1);" : "")
            \(targetCode)
            char **args = calloc((size_t)argc + \(arguments.count) + 1, sizeof(char *));
            if (!args) return 1; args[0] = target;
            \(args)
            for (int i = 1; i < argc; ++i) args[\(arguments.count) + i] = argv[i];
            execv(target, args); perror("ATBClone launch"); return 1;
        }
        """, output: output)
    }
    static func dylib(output: URL, env: [String: String]) throws {
        let lines = env.sorted(by: { $0.key < $1.key }).map { "setenv(\(literal($0.key)), \(literal($0.value)), 1);" }.joined(separator: "\n")
        try compile("#include <stdlib.h>\n__attribute__((constructor)) static void initialize(void) {\n\(lines)\n}\n", output: output, library: true)
    }
}
