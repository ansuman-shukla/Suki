import SwiftUI

struct DictionaryView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        DictionaryPage(vocabulary: $appState.customVocabulary)
    }
}

extension VocabularyEditError {
    var message: String {
        switch self {
        case .empty: return "Type a word or phrase first."
        case .duplicate: return "That word is already in your dictionary."
        case .containsSeparator: return "Add one entry at a time, without commas, semicolons or line breaks."
        }
    }
}

/// Dictionary page over the raw `custom_vocabulary` text, so it can render from plain data.
struct DictionaryPage: View {
    @Binding var vocabulary: String
    @State private var query = ""
    @State private var editingID: Int?
    @State private var isAdding = false
    @State private var draft = ""
    @State private var error: VocabularyEditError?

    private var list: VocabularyList { VocabularyList(vocabulary) }

    var body: some View {
        let list = list
        let entries = list.filtered(by: query)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HubPageHeader(title: "Dictionary", subtitle: "Words Suki should always spell your way") {
                    Button("Add new", action: startAdding)
                        .buttonStyle(HubButtonStyle())
                }

                if !list.entries.isEmpty {
                    HubSearchField(text: $query, prompt: "Search words")
                }

                VStack(alignment: .leading, spacing: 4) {
                    if !entries.isEmpty {
                        Text(entries.count == 1 ? "1 word" : "\(entries.count) words")
                            .sectionLabelStyle()
                            .padding(.leading, 2)
                            .padding(.bottom, 6)
                    }
                    if isAdding {
                        editor(placeholder: "New word, name or phrase")
                    }
                    ForEach(entries) { entry in
                        if editingID == entry.id {
                            editor(placeholder: entry.text)
                        } else {
                            DictionaryRow(
                                text: entry.text,
                                onEdit: { startEditing(entry) },
                                onDelete: { delete(entry) }
                            )
                        }
                    }
                }

                if list.entries.isEmpty && !isAdding {
                    HubEmptyState(
                        title: "Your dictionary is empty",
                        message: "Add names, jargon or brand words like “Kubernetes” or “Zoë Quill” and Suki will spell them exactly that way."
                    )
                } else if entries.isEmpty && !isAdding {
                    HubEmptyState(title: "No matches", message: "Nothing in your dictionary matches “\(query)”.")
                }
            }
            .hubPageLayout()
        }
        .animation(.suki, value: isAdding)
        .animation(.suki, value: editingID)
    }

    private func editor(placeholder: String) -> some View {
        HubEditorCard(error: error?.message, onSave: save, onCancel: cancel) {
            HubTextInput(text: $draft, placeholder: placeholder, autoFocus: true, onSubmit: save)
        }
        .onChange(of: draft) { _ in error = nil }
    }

    private func startAdding() {
        editingID = nil
        draft = ""
        error = nil
        isAdding = true
    }

    private func startEditing(_ entry: VocabularyEntry) {
        isAdding = false
        draft = entry.text
        error = nil
        editingID = entry.id
    }

    private func save() {
        var updated = list
        error = editingID.map { updated.rename($0, to: draft) } ?? updated.add(draft)
        guard error == nil else { return }
        vocabulary = updated.serialized
        cancel()
    }

    private func cancel() {
        isAdding = false
        editingID = nil
        error = nil
    }

    private func delete(_ entry: VocabularyEntry) {
        var updated = list
        updated.delete(entry.id)
        cancel()
        vocabulary = updated.serialized
    }
}

struct DictionaryRow: View {
    let text: String
    var isHovered = false
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HubListRow(isHovered: isHovered, onEdit: onEdit, onDelete: onDelete) {
            Text(text)
                .font(SukiFont.ui(14))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
