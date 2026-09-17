import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CloneCore

struct WizardView: View {
    @Bindable var store: AppStore
    let record: CloneRecord?
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var source: URL?
    @State private var info: AppInfo?
    @State private var recipe: Recipe?
    @State private var name = ""
    @State private var displayName = ""
    @State private var language = "system"
    @State private var icon: URL?
    @State private var destination = ""
    @State private var dataDirectory = ""
    @State private var proxy = ProxySettings()
    @State private var password = ""
    @State private var injection: Injection = .auto
    @State private var issue: String?
    @State private var submitting = false
    private let stages = ["选择应用", "克隆方式", "名称与图标", "网络与存储", "确认创建"]
    private var windowHeight: CGFloat {
        switch step {
        case 0: return info == nil ? 320 : 420
        case 1: return 430
        case 2: return 510
        case 3: return proxy.enabled ? 620 : 440
        default: return 480
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 6) { Text(record == nil ? "新建应用分身" : "修改分身").font(.title2.bold()); Text("\(step + 1) / 5  ·  \(stages[step])").foregroundStyle(.secondary) }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary) }.buttonStyle(.plain).disabled(submitting)
            }.padding(24)
            HStack(spacing: 6) { ForEach(0..<5) { index in Capsule().fill(index <= step ? Color.accentColor : Color.secondary.opacity(0.18)).frame(height: 4) } }.padding(.horizontal, 24)
            Form {
                switch step {
                case 0: sourceForm
                case 1: strategyForm
                case 2: identityForm
                case 3: networkForm
                default: summaryForm
                }
            }.formStyle(.grouped)
            if let issue { Text(issue).font(.callout).foregroundStyle(.red).textSelection(.enabled).padding(.horizontal, 24) }
            if submitting { HStack { ProgressView().controlSize(.small); Text(store.progress).font(.callout) }.padding() }
            Divider()
            HStack {
                Button("取消") { dismiss() }.disabled(submitting)
                Spacer()
                if step > (record == nil ? 0 : 2) { Button("上一步") { step -= 1 }.disabled(submitting) }
                Button(step == 4 ? (record == nil ? "创建分身" : "保存并更新") : "下一步") { advance() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(submitting || (step == 0 && info == nil))
            }.padding(20)
        }.frame(width: 600, height: windowHeight).interactiveDismissDisabled(submitting).onAppear { restore() }
    }
    private var sourceForm: some View {
        Section {
            HStack(spacing: 18) {
                Image(nsImage: source.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: "选择应用")!).resizable().frame(width: 70, height: 70)
                VStack(alignment: .leading, spacing: 8) { Text(info?.name ?? "选择要分身的应用").font(.title3.bold()); Text(source?.path ?? "支持 macOS .app 应用").font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                Spacer()
                Button("选择…") { selectSource() }
            }.padding(.vertical, 12)
            if let info { LabeledContent("Bundle ID", value: info.bundleID); LabeledContent("版本", value: info.version); LabeledContent("检测类型", value: info.type) }
        }
    }
    private var strategyForm: some View {
        Section("已匹配规则：\(recipe?.appName ?? "自动探测")") {
            Picker("克隆方式", selection: Binding(get: { recipe?.strategy ?? .hard }, set: { recipe?.strategy = $0 })) { ForEach(Strategy.allCases, id: \.self) { Text($0.label).tag($0) } }
            Text("硬分身复制完整应用，可自定义主进程及辅助进程名称。软分身使用原应用程序，适合支持独立配置目录的应用。").font(.callout).foregroundStyle(.secondary)
            Picker("环境注入", selection: $injection) { Text("自动选择").tag(Injection.auto); Text("进程内动态库").tag(Injection.dylib); Text("原生启动器").tag(Injection.launcher) }.disabled(recipe?.strategy == .soft)
            Toggle("移除应用沙盒限制", isOn: Binding(get: { recipe?.stripSandbox ?? false }, set: { recipe?.stripSandbox = $0 }))
        }
    }
    private var identityForm: some View {
        Group {
            Section("分身身份") {
                TextField("分身名称 / 进程名", text: $name).disabled(record != nil)
                TextField("显示名称", text: $displayName)
                Picker("应用界面语言", selection: $language) { ForEach(supportedLanguages, id: \.self) { Text($0 == "system" ? "跟随系统" : Locale.current.localizedString(forLanguageCode: $0) ?? $0).tag($0) } }
            }
            Section("应用图标") {
                HStack(spacing: 18) {
                    Image(nsImage: previewIcon).resizable().frame(width: 76, height: 76)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(icon?.lastPathComponent ?? (record == nil ? "使用原应用图标" : "保留当前图标")).font(.callout)
                        HStack { Button("选择 .icns…") { chooseIcon() }; Button("恢复当前默认") { icon = nil } }
                    }
                }.padding(.vertical, 8)
                Text("图标会复制进分身；之后修改设置或更新时自动保留。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var networkForm: some View {
        Group {
            Section("独立网络") {
                Toggle("启用代理", isOn: $proxy.enabled)
                if proxy.enabled {
                    Picker("类型", selection: $proxy.type) { ForEach(["http", "https", "socks5"], id: \.self) { Text($0.uppercased()).tag($0) } }
                    TextField("服务器", text: $proxy.host)
                    TextField("端口", value: $proxy.port, format: .number.grouping(.never))
                    TextField("用户名（可选）", text: $proxy.username)
                    SecureField("密码（保存到钥匙串）", text: $password)
                    TextField("绕过代理", text: $proxy.noProxy)
                    Text("应用必须支持代理环境变量；最终连接是否走代理需在客户端中验证。").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("存储位置") {
                TextField("分身应用", text: $destination).disabled(record != nil)
                TextField("独立数据", text: $dataDirectory).disabled(record != nil)
                Text("默认保存到用户目录，无需管理员权限。更新保留数据。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var summaryForm: some View {
        Section("即将\(record == nil ? "创建" : "更新")") {
            LabeledContent("应用", value: info?.name ?? recipe?.appName ?? "")
            LabeledContent("分身", value: name)
            LabeledContent("方式", value: recipe?.strategy.label ?? "")
            LabeledContent("语言", value: language)
            LabeledContent("网络", value: proxy.enabled ? "\(proxy.type)://\(proxy.host):\(proxy.port)" : "系统网络")
            Text(destination).font(.caption).textSelection(.enabled)
            if recipe?.strategy == .hard {
                Text("主进程：\(name)\n辅助进程：\(name)-原名称").font(.system(.callout, design: .monospaced))
            }
        }
    }
    private var previewIcon: NSImage {
        if let icon, let image = NSImage(contentsOf: icon) { return image }
        if let url = record?.configuration.destination ?? source { return NSWorkspace.shared.icon(forFile: url.path) }
        return NSImage(systemSymbolName: "app", accessibilityDescription: "应用图标")!
    }
    private func selectSource() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let inspected = try Inspector.inspect(url); source = url; info = inspected
            let r = Recipes.match(inspected, recipes: store.recipes); recipe = r; injection = r.injection
            name = inspected.name + " 2"; displayName = name; icon = nil
            destination = store.root.appendingPathComponent("Apps/\(name).app").path
            dataDirectory = store.root.appendingPathComponent("Data/\(name)").path; issue = nil
        } catch { issue = error.localizedDescription }
    }
    private func chooseIcon() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "icns")!]
        if panel.runModal() == .OK { icon = panel.url }
    }
    private func configuration() throws -> CloneConfiguration {
        guard let source, let recipe else { throw CloneFailure.invalid("请选择应用") }
        var c = record?.configuration ?? CloneConfiguration(source: source, name: name, destination: URL(fileURLWithPath: destination), dataDirectory: URL(fileURLWithPath: dataDirectory), recipe: recipe)
        c.name = name; c.displayName = displayName.isEmpty ? name : displayName; c.recipe = recipe
        c.destination = URL(fileURLWithPath: NSString(string: destination).expandingTildeInPath)
        c.dataDirectory = URL(fileURLWithPath: NSString(string: dataDirectory).expandingTildeInPath)
        c.proxy = proxy; c.language = language; c.customIcon = icon; c.injection = injection
        try c.validate(); return c
    }
    private func advance() {
        issue = nil
        do {
            if step == 2 {
                try validateName(name)
                if record == nil { destination = store.root.appendingPathComponent("Apps/\(name).app").path; dataDirectory = store.root.appendingPathComponent("Data/\(name)").path }
            }
            if step >= 3 { _ = try configuration() }
            if step < 4 { step += 1; return }
            let config = try configuration(); submitting = true
            Task { let success = await store.build(config, password: password, updating: record != nil); submitting = false; if success { dismiss() } else { issue = store.error; store.error = nil } }
        } catch { issue = error.localizedDescription }
    }
    private func restore() {
        guard let record else { return }
        let c = record.configuration; source = c.source; info = try? Inspector.inspect(c.source); recipe = c.recipe
        name = c.name; displayName = c.displayName; language = c.language; proxy = c.proxy; injection = c.injection
        destination = c.destination.path; dataDirectory = c.dataDirectory.path; step = 2
        do { password = try Secrets.read(c.id) } catch { issue = error.localizedDescription }
    }
}
