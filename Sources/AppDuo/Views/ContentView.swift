import SwiftUI
import AppKit
import CloneCore

struct ContentView: View {
    @Bindable var store: AppStore
    @State private var query = ""
    @State private var removing: CloneRecord?
    var body: some View {
        NavigationSplitView {
            List(selection: $store.selection) {
                Section("工作空间") {
                    Label("我的分身", systemImage: "square.stack.3d.up").tag("clones")
                    Label("规则库", systemImage: "slider.horizontal.3").tag("recipes")
                }
                Section("工具") {
                    Label("应用探测", systemImage: "viewfinder").tag("probe")
                    Label("环境检查", systemImage: "stethoscope").tag("doctor")
                    Label("操作日志", systemImage: "text.alignleft").tag("logs")
                }
            }
            .navigationTitle("AppDuo")
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Image(nsImage: NSImage(contentsOf: Assets.icon) ?? NSImage()).resizable().frame(width: 30, height: 30)
                    VStack(alignment: .leading) { Text("AppDuo").font(.caption.bold()); Text("原生 macOS 分身管理").font(.caption2).foregroundStyle(.secondary) }
                    Spacer()
                }.padding()
            }
        } detail: {
            Group {
                switch store.selection {
                case "recipes": RecipesView(store: store)
                case "probe": ProbeView(store: store)
                case "doctor": DoctorView()
                case "logs": LogsView(store: store)
                default: clones
                }
            }
            .toolbar {
                ToolbarItem { Button { Task { await store.reload() } } label: { Label("刷新", systemImage: "arrow.clockwise") }.disabled(store.busy) }
                ToolbarItem { Button { store.editing = nil; store.showingWizard = true } label: { Label("新建分身", systemImage: "plus") }.disabled(store.busy) }
            }
            .safeAreaInset(edge: .bottom) {
                if store.busy { HStack(spacing: 10) { ProgressView().controlSize(.small); Text(store.progress).font(.callout); Spacer() }.padding(12).background(.bar) }
            }
        }
        .sheet(isPresented: $store.showingWizard) { WizardView(store: store, record: store.editing) }
        .alert("操作未完成", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("好") { store.error = nil } } message: { Text(store.error ?? "") }
        .confirmationDialog("将分身移到废纸篓？", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            if let record = removing {
                Button("移除应用，保留数据", role: .destructive) { Task { await store.remove(record, withData: false) } }
                Button("移除应用及数据", role: .destructive) { Task { await store.remove(record, withData: true) } }
            }
            Button("取消", role: .cancel) {}
        } message: { Text("默认保留聊天记录与登录数据。自定义数据目录需要手动管理。") }
    }
    private var clones: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("每个身份，独立空间。").font(.largeTitle.bold())
                        Text("管理应用分身、独立数据与网络设置。").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(store.records.count) 个分身").font(.callout).padding(.horizontal, 14).padding(.vertical, 8).background(.quaternary, in: Capsule())
                }
                if store.records.isEmpty {
                    ContentUnavailableView {
                        Label("创建你的第一个分身", systemImage: "square.on.square.dashed")
                    } description: { Text("选择一个应用，为工作与生活保留各自的空间。") } actions: {
                        Button("新建分身") { store.editing = nil; store.showingWizard = true }.buttonStyle(.borderedProminent).disabled(store.busy)
                    }.frame(maxWidth: .infinity, minHeight: 340)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 18)], spacing: 18) {
                        ForEach(store.records.filter { query.isEmpty || $0.configuration.name.localizedCaseInsensitiveContains(query) }) { record in
                            CloneCard(record: record, busy: store.busy, launch: { store.launch(record) }, edit: { store.editing = record; store.showingWizard = true }, update: { Task { await store.update(record) } }, remove: { removing = record })
                        }
                    }
                }
            }.padding(30)
        }.navigationTitle("我的分身").searchable(text: $query, prompt: "搜索分身")
    }
}
struct CloneCard: View {
    let record: CloneRecord
    let busy: Bool
    let launch: () -> Void, edit: () -> Void, update: () -> Void, remove: () -> Void
    var body: some View {
        let c = record.configuration
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: c.destination.path)).resizable().frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 5) { Text(c.displayName).font(.title3.bold()); Text(c.recipe.appName).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Menu { Button("编辑设置…", action: edit); Button("更新分身", action: update); Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([c.destination]) }; Divider(); Button("移除…", role: .destructive, action: remove) } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 22).disabled(busy)
            }
            HStack(spacing: 12) {
                Label(c.recipe.strategy == .hard ? "硬分身" : "软分身", systemImage: "square.stack").font(.caption)
                Label(c.proxy.enabled ? "独立代理" : "系统网络", systemImage: c.proxy.enabled ? "network" : "globe").font(.caption)
            }.foregroundStyle(.secondary)
            Divider()
            HStack {
                Text(c.name).font(.system(.caption, design: .monospaced)).lineLimit(1)
                Spacer()
                Button("打开", action: launch).buttonStyle(.borderedProminent).disabled(busy)
            }
        }.padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary))
    }
}
