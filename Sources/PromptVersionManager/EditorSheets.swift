import SwiftUI
import PromptVersionCore

struct PromptEditorSheet: View {
    let title: String
    let includesPromptFields: Bool
    let saveLabel: String
    let onSave: (PromptDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: PromptDraft
    @State private var tagsText: String
    @State private var rating = 0

    init(
        title: String,
        initial: PromptDraft,
        includesPromptFields: Bool,
        saveLabel: String,
        onSave: @escaping (PromptDraft) -> Void
    ) {
        self.title = title
        self.includesPromptFields = includesPromptFields
        self.saveLabel = saveLabel
        self.onSave = onSave
        _draft = State(initialValue: initial)
        _tagsText = State(initialValue: initial.tags.joined(separator: ", "))
        _rating = State(initialValue: initial.rating ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title2.bold())

            if includesPromptFields {
                TextField("标题", text: $draft.title)
                TextField("描述 / 笔记", text: $draft.description)
                TextField("标签（用逗号分隔）", text: $tagsText)
            }

            TextField(
                "使用模型（可选）",
                text: Binding(
                    get: { draft.model ?? "" },
                    set: { draft.model = $0.isEmpty ? nil : $0 }
                )
            )

            HStack {
                Picker("效果评分", selection: $rating) {
                    Text("未评分").tag(0)
                    ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                }
                TextField("版本备注", text: $draft.note)
            }

            Text("Prompt 正文")
                .font(.headline)
            TextEditor(text: $draft.content)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 260)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(saveLabel) {
                    draft.tags = parseTags(tagsText)
                    draft.rating = rating == 0 ? nil : rating
                    onSave(draft)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(includesPromptFields && draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 680, height: includesPromptFields ? 660 : 570)
    }
}

struct MetadataEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var description: String
    let onSave: (String, String) -> Void

    init(title: String, description: String, onSave: @escaping (String, String) -> Void) {
        _title = State(initialValue: title)
        _description = State(initialValue: description)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("编辑 Prompt 信息")
                .font(.title2.bold())
            TextField("标题", text: $title)
            TextField("描述 / 笔记", text: $description)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") { onSave(title, description) }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

struct TagsEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tagsText: String
    let onSave: ([String]) -> Void

    init(tags: [String], onSave: @escaping ([String]) -> Void) {
        _tagsText = State(initialValue: tags.joined(separator: ", "))
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("管理标签")
                .font(.title2.bold())
            TextField("标签（用逗号分隔）", text: $tagsText)
            Text("保存后会添加新标签，并移除不再列出的标签。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") { onSave(parseTags(tagsText)) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

private func parseTags(_ value: String) -> [String] {
    var seen = Set<String>()
    return value.split(separator: ",", omittingEmptySubsequences: false).compactMap { component in
        let clean = component.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        let key = clean.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        guard seen.insert(key).inserted else { return nil }
        return clean
    }
}
