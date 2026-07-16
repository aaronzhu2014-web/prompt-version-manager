import SwiftUI
import PromptVersionCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var selectedTab = "content"

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.importFile()
                } label: {
                    Label("导入", systemImage: "square.and.arrow.down")
                }

                Button {
                    model.presentedSheet = .create
                } label: {
                    Label("新建 Prompt", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .sheet(item: $model.presentedSheet) { sheet in
            sheetView(sheet)
        }
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("好") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text(model.status)
                Spacer()
                Text("数据库：\(model.databaseURL.path)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.bar)
        }
    }

    private var sidebar: some View {
        VStack(spacing: 10) {
            TextField("搜索标题、标签和历史正文", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .onChange(of: model.searchText) { _ in model.refresh() }

            Picker(
                "标签",
                selection: Binding(
                    get: { model.tagFilter ?? "" },
                    set: {
                        model.tagFilter = $0.isEmpty ? nil : $0
                        model.refresh()
                    }
                )
            ) {
                Text("全部标签").tag("")
                ForEach(model.tags) { tag in
                    Text("\(tag.name) (\(tag.count))").tag(tag.name)
                }
            }
            .labelsHidden()

            List(model.prompts, selection: $model.selectedPromptID) { prompt in
                PromptRow(prompt: prompt)
                    .tag(prompt.id)
            }
            .listStyle(.sidebar)
        }
        .padding(.top, 10)
        .navigationTitle("Prompt 库")
    }

    @ViewBuilder
    private var detail: some View {
        if let prompt = model.selectedPrompt {
            VStack(spacing: 0) {
                header(prompt)
                TabView(selection: $selectedTab) {
                    contentTab
                        .tabItem { Label("内容", systemImage: "doc.text") }
                        .tag("content")
                    historyTab
                        .tabItem { Label("历史", systemImage: "clock.arrow.circlepath") }
                        .tag("history")
                    diffTab
                        .tabItem { Label("Diff", systemImage: "arrow.left.arrow.right") }
                        .tag("diff")
                }
                .padding(.horizontal, 18)
            }
        } else {
            VStack(spacing: 14) {
                Image(systemName: "text.badge.plus")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("还没有 Prompt")
                    .font(.title2.bold())
                Text("点击工具栏中的“新建 Prompt”开始。")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ prompt: Prompt) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(prompt.title)
                        .font(.largeTitle.bold())
                    Text("\(String(prompt.id.prefix(12))) · v\(prompt.latestVersion.number)")
                        .foregroundStyle(.secondary)
                    if !prompt.description.isEmpty {
                        Text(prompt.description)
                    }
                    if !prompt.tags.isEmpty {
                        FlowTags(tags: prompt.tags)
                    }
                }
                Spacer()
                Button("编辑信息") { model.presentedSheet = .metadata }
                Button("管理标签") { model.presentedSheet = .tags }
                Button {
                    model.presentedSheet = .newVersion
                } label: {
                    Label("新版本", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            HStack {
                Menu("导出") {
                    Button("导出 JSON") { model.exportFile(markdown: false) }
                    Button("导出 Markdown") { model.exportFile(markdown: true) }
                }
                Button("刷新") { model.refresh(selecting: prompt.id) }
            }
        }
        .padding(22)
    }

    private var contentTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let version = model.displayedVersion {
                HStack {
                    Text(versionSummary(version))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if version.number != model.selectedPrompt?.latestVersion.number {
                        Text("历史版本")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.orange.opacity(0.15), in: Capsule())
                    }
                }
                TextEditor(text: .constant(version.content))
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
            }
        }
        .padding(.vertical, 12)
    }

    private var historyTab: some View {
        Table(model.history) {
            TableColumn("版本") { version in
                Button("v\(version.number)") {
                    model.showVersion(version)
                    selectedTab = "content"
                }
                .buttonStyle(.link)
            }
            .width(70)
            TableColumn("时间", value: \.createdAt)
                .width(min: 180, ideal: 220)
            TableColumn("模型") { Text($0.model ?? "—") }
            TableColumn("评分") { Text($0.rating.map { "\($0)/5" } ?? "—") }
                .width(70)
            TableColumn("备注", value: \.note)
        }
        .padding(.vertical, 12)
    }

    private var diffTab: some View {
        VStack(spacing: 10) {
            HStack {
                Picker("从", selection: $model.diffFrom) {
                    ForEach(model.history.reversed()) { version in
                        Text("v\(version.number)").tag(Optional(version.number))
                    }
                }
                .frame(width: 130)
                Picker("到", selection: $model.diffTo) {
                    ForEach(model.history.reversed()) { version in
                        Text("v\(version.number)").tag(Optional(version.number))
                    }
                }
                .frame(width: 130)
                Spacer()
            }
            DiffTextView(text: model.diffText)
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func sheetView(_ sheet: PresentedSheet) -> some View {
        switch sheet {
        case .create:
            PromptEditorSheet(
                title: "新建 Prompt",
                initial: PromptDraft(),
                includesPromptFields: true,
                saveLabel: "创建",
                onSave: model.create
            )
        case .newVersion:
            PromptEditorSheet(
                title: "保存新版本",
                initial: PromptDraft(content: model.selectedPrompt?.latestVersion.content ?? ""),
                includesPromptFields: false,
                saveLabel: "保存新版本",
                onSave: model.addVersion
            )
        case .metadata:
            MetadataEditorSheet(
                title: model.selectedPrompt?.title ?? "",
                description: model.selectedPrompt?.description ?? "",
                onSave: model.editMetadata
            )
        case .tags:
            TagsEditorSheet(
                tags: model.selectedPrompt?.tags ?? [],
                onSave: model.updateTags
            )
        }
    }

    private func versionSummary(_ version: PromptVersion) -> String {
        let model = version.model ?? "未记录模型"
        let rating = version.rating.map { "\($0)/5" } ?? "未评分"
        let note = version.note.isEmpty ? "" : " · \(version.note)"
        return "v\(version.number) · \(model) · \(rating)\(note)"
    }
}

private struct PromptRow: View {
    let prompt: Prompt

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(prompt.title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                Text("v\(prompt.latestVersion.number)")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(prompt.tags.joined(separator: " · "))
                    .lineLimit(1)
                Spacer()
                Text(prompt.latestVersion.rating.map { "\($0)/5" } ?? "—")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct FlowTags: View {
    let tags: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.12), in: Capsule())
            }
        }
    }
}

private struct DiffTextView: View {
    let text: String

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                    Text(line.isEmpty ? " " : line)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(color(for: line))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(background(for: line))
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
    }

    private func color(for line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return .green }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return .red }
        if line.hasPrefix("---") || line.hasPrefix("+++") { return .accentColor }
        return .primary
    }

    private func background(for line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return .green.opacity(0.10) }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return .red.opacity(0.10) }
        return .clear
    }
}
