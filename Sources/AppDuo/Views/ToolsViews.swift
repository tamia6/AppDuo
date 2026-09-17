import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CloneCore

struct RecipesView: View {
    @Bindable var store: AppStore
    @State private var search = ""
    @State private var selected: String?
    @State private var editor = ""
    @State private var editing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("应用规则库").font(.largeTitle.bold()); Spacer(); Button("导入 YAML…") { importRecipe() } }.padding(24)
            Text("\(store.recipes.count) 条规则 · 本地覆盖优先").foregroundStyle(.secondary).padding(.horizontal, 24)
            List(store.recipes.filter { search.isEmpty || $0.appName.localizedCaseInsensitiveContains(search) || $0.bundleID.localizedCaseInsensitiveContains(search) }, selection: $selected) { recipe in
                HStack {
                    Image(systemName: recipe.strategy == .hard ? "app.badge" : "link").foregroundStyle(.tint).frame(width: 28)
                    VStack(alignment: .leading, spacing: 5) { Text(recipe.appName).font(.headline); Text(recipe.bundleID).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary) }
                    Spacer(); Text(recipe.strategy.label).font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 8).tag(recipe.id).contextMenu { Button("编辑 YAML…") { edit(recipe) } }
                .onTapGesture(count: 2) { edit(recipe) }
            }.listStyle(.inset)
        }.navigationTitle("规则库").searchable(text: $search, prompt: "搜索应用或 Bundle ID")
        .sheet(isPresented: $editing) {
            VStack(alignment: .leading) {
                Text("编辑应用规则").font(.title2.bold())
                Text("保存为本地覆盖规则；内置规则保持不变。").foregroundStyle(.secondary)
                TextEditor(text: $editor).font(.system(.body, design: .monospaced)).border(.quaternary)
                HStack { Button("取消") { editing = false }; Spacer(); Button("保存") { saveRecipe(editor) }.buttonStyle(.borderedProminent) }
            }.padding(24).frame(width: 690, height: 600)
        }
    }
    private func edit(_ recipe: Recipe) {
        let custom = store.root.appendingPathComponent("recipes/\(recipe.bundleID).yaml")
        let builtin = Assets.root.appendingPathComponent("recipes/\(recipe.bundleID).yaml")
        do { editor = try String(contentsOf: FileManager.default.fileExists(atPath: custom.path) ? custom : builtin, encoding: .utf8); editing = true }
        catch { store.error = error.localizedDescription }
    }
    private func importRecipe() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "yaml") ?? .text, UTType(filenameExtension: "yml") ?? .text]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { editor = try String(contentsOf: url, encoding: .utf8); _ = try Recipes.decode(editor); editing = true } catch { store.error = error.localizedDescription }
    }
    private func saveRecipe(_ source: String) {
        do {
            let recipe = try Recipes.decode(source)
            guard recipe.bundleID.range(of: "^[A-Za-z0-9.-]+$", options: .regularExpression) != nil else { throw CloneFailure.invalid("Bundle ID 无效") }
            let folder = store.root.appendingPathComponent("recipes"); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try source.write(to: folder.appendingPathComponent(recipe.bundleID + ".yaml"), atomically: true, encoding: .utf8)
            editing = false; Task { await store.reload() }
        } catch { store.error = error.localizedDescription }
    }
}
struct ProbeView: View {
    let store: AppStore
    @State private var info: AppInfo?
    @State private var recipe: Recipe?
    var body: some View {
        Form {
            Section {
                Text("了解应用的克隆方式").font(.title.bold())
                Text("读取应用元数据与 Frameworks，匹配内置规则。").foregroundStyle(.secondary)
                Button("选择应用…") {
                    let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]
                    if panel.runModal() == .OK, let url = panel.url {
                        do { let value = try Inspector.inspect(url); info = value; recipe = Recipes.match(value, recipes: store.recipes) }
                        catch { store.error = error.localizedDescription }
                    }
                }
            }
            if let info, let recipe {
                Section(info.name) {
                    LabeledContent("Bundle ID", value: info.bundleID)
                    LabeledContent("版本", value: info.version)
                    LabeledContent("主程序", value: info.executable)
                    LabeledContent("架构类型", value: info.type)
                    LabeledContent("推荐方式", value: recipe.strategy.label)
                    LabeledContent("规则来源", value: store.recipes.contains(where: { $0.bundleID == info.bundleID }) ? "预设规则" : "自动探测")
                    Text(info.url.path).font(.caption).textSelection(.enabled)
                }
            }
        }.formStyle(.grouped).navigationTitle("应用探测")
    }
}
struct DoctorView: View {
    @State private var results: [(String, String, Bool)] = []
    @State private var running = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("环境检查").font(.largeTitle.bold())
            Text("检查编译、重签名工具与 macOS 环境。").foregroundStyle(.secondary)
            Button("开始检查") { run() }.buttonStyle(.borderedProminent).disabled(running)
            if running { ProgressView() }
            ForEach(results.indices, id: \.self) { i in
                HStack(alignment: .top) {
                    Image(systemName: results[i].2 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(results[i].2 ? .green : .orange)
                    VStack(alignment: .leading, spacing: 6) { Text(results[i].0).font(.headline); Text(results[i].1).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            }
            Spacer()
        }.padding(30).navigationTitle("环境检查")
    }
    private func run() {
        running = true
        Task {
            let checks = await Task.detached { () -> [(String, String, Bool)] in
                [("macOS", "/usr/bin/sw_vers", ["-productVersion"]), ("编译器", "/usr/bin/xcrun", ["--find", "clang"]), ("签名工具", "/usr/bin/codesign", ["--version"])].map { title, executable, args in
                    do { return (title, try Command.run(executable, args).trimmingCharacters(in: .whitespacesAndNewlines), true) }
                    catch { return (title, error.localizedDescription, false) }
                }
            }.value
            results = checks; running = false
        }
    }
}
struct LogsView: View {
    let store: AppStore
    var body: some View {
        ScrollView { Text(store.logs.isEmpty ? "尚无操作记录" : store.logs.joined(separator: "\n")).font(.system(.callout, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(24) }.navigationTitle("操作日志")
    }
}
struct SettingsView: View {
    let root: URL
    var body: some View {
        Form {
            Section("AppDuo") { Text("原生 Swift + SwiftUI · macOS 14+"); Text("Swift 版本的数据与原版独立保存。").foregroundStyle(.secondary) }
            Section("数据位置") { Text(root.path).textSelection(.enabled); Button("在 Finder 中打开") { try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); NSWorkspace.shared.open(root) } }
        }.formStyle(.grouped).frame(width: 500, height: 300)
    }
}
