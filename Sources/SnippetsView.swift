import SwiftUI

struct SnippetsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        SnippetsPage(snippets: $appState.voiceMacros)
    }
}

extension SnippetEditError {
    var message: String {
        switch self {
        case .emptyTrigger: return "Add the phrase you'll say."
        case .emptyExpansion: return "Add the text Suki should type."
        case .duplicateTrigger: return "Another snippet already uses that phrase."
        }
    }
}

/// Snippets page over a plain list of voice macros, so it can render from plain data.
struct SnippetsPage: View {
    @Binding var snippets: [VoiceMacro]
    @State private var query = ""
    @State private var editingID: UUID?
    @State private var isAdding = false
    @State private var trigger = ""
    @State private var expansion = ""
    @State private var error: SnippetEditError?

    var body: some View {
        let visible = SnippetList.filtered(snippets, by: query)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HubPageHeader(title: "Snippets", subtitle: "Say a phrase, Suki types the full text") {
                    Button("Add new", action: startAdding)
                        .buttonStyle(HubButtonStyle())
                }

                if !snippets.isEmpty {
                    HubSearchField(text: $query, prompt: "Search snippets")
                }

                VStack(alignment: .leading, spacing: 4) {
                    if !visible.isEmpty {
                        Text(visible.count == 1 ? "1 snippet" : "\(visible.count) snippets")
                            .sectionLabelStyle()
                            .padding(.leading, 2)
                            .padding(.bottom, 6)
                    }
                    if isAdding {
                        editor
                    }
                    ForEach(visible) { snippet in
                        if editingID == snippet.id {
                            editor
                        } else {
                            SnippetRow(
                                trigger: snippet.command,
                                expansion: snippet.payload,
                                onEdit: { startEditing(snippet) },
                                onDelete: { delete(snippet) }
                            )
                        }
                    }
                }

                if snippets.isEmpty && !isAdding {
                    HubEmptyState(
                        title: "No snippets yet",
                        message: "Save text you type often, like your address or a meeting link, and say a short phrase such as “my calendar link” to have Suki type it."
                    )
                } else if visible.isEmpty && !isAdding {
                    HubEmptyState(title: "No matches", message: "No snippet matches “\(query)”.")
                }
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 40)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .animation(.suki, value: isAdding)
        .animation(.suki, value: editingID)
    }

    private var editor: some View {
        SnippetEditor(trigger: $trigger, expansion: $expansion, error: error?.message, onSave: save, onCancel: cancel)
            .onChange(of: trigger) { _ in error = nil }
            .onChange(of: expansion) { _ in error = nil }
    }

    private func startAdding() {
        editingID = nil
        trigger = ""
        expansion = ""
        error = nil
        isAdding = true
    }

    private func startEditing(_ snippet: VoiceMacro) {
        isAdding = false
        trigger = snippet.command
        expansion = snippet.payload
        error = nil
        editingID = snippet.id
    }

    private func save() {
        var updated = snippets
        error = SnippetList.save(trigger: trigger, expansion: expansion, in: &updated, editing: editingID)
        guard error == nil else { return }
        snippets = updated
        cancel()
    }

    private func cancel() {
        isAdding = false
        editingID = nil
        error = nil
    }

    private func delete(_ snippet: VoiceMacro) {
        cancel()
        snippets.removeAll { $0.id == snippet.id }
    }
}

struct SnippetRow: View {
    let trigger: String
    let expansion: String
    var isHovered = false
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HubListRow(isHovered: isHovered, onEdit: onEdit, onDelete: onDelete) {
            HStack(spacing: 10) {
                Text(trigger)
                    .font(SukiFont.ui(14, .medium))
                    .lineLimit(1)
                    .layoutPriority(1)
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                Text(expansion.components(separatedBy: .newlines).joined(separator: " "))
                    .font(SukiFont.ui(14))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: 120, alignment: .leading)
            }
        }
    }
}

struct SnippetEditor: View {
    @Binding var trigger: String
    @Binding var expansion: String
    let error: String?
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HubEditorCard(error: error, onSave: onSave, onCancel: onCancel) {
            field("When you say") {
                HubTextInput(text: $trigger, placeholder: "my calendar link", autoFocus: true, onSubmit: onSave)
            }
            field("Suki types") {
                HubTextInput(text: $expansion, placeholder: "https://cal.example.com/zoe", isMultiline: true)
            }
        }
    }

    private func field<Input: View>(_ label: String, @ViewBuilder input: () -> Input) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(SukiFont.ui(12, .medium))
                .foregroundStyle(Theme.textSecondary)
                .padding(.leading, 2)
            input()
        }
    }
}
