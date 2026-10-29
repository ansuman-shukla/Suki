import Foundation

/// A snippet: saying `command` on its own makes Suki type `payload`.
struct VoiceMacro: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var command: String
    var payload: String
}

enum SnippetEditError: Equatable {
    case emptyTrigger
    case emptyExpansion
    case duplicateTrigger
}

enum SnippetList {
    /// How dictation matches a snippet: the whole transcript, lowercased, with punctuation
    /// removed and outer whitespace trimmed, must equal the normalized trigger.
    static func normalizedTrigger(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.punctuationCharacters)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func validationError(
        trigger: String,
        expansion: String,
        in snippets: [VoiceMacro],
        editing snippetID: UUID? = nil
    ) -> SnippetEditError? {
        let key = normalizedTrigger(trigger)
        if key.isEmpty { return .emptyTrigger }
        if expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .emptyExpansion }
        let isDuplicate = snippets.contains { $0.id != snippetID && normalizedTrigger($0.command) == key }
        return isDuplicate ? .duplicateTrigger : nil
    }

    /// Replaces the snippet with `snippetID`, or appends a new one. The expansion is kept verbatim.
    @discardableResult
    static func save(
        trigger: String,
        expansion: String,
        in snippets: inout [VoiceMacro],
        editing snippetID: UUID? = nil
    ) -> SnippetEditError? {
        if let error = validationError(trigger: trigger, expansion: expansion, in: snippets, editing: snippetID) {
            return error
        }
        let command = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = snippets.firstIndex(where: { $0.id == snippetID }) {
            snippets[index].command = command
            snippets[index].payload = expansion
        } else {
            snippets.append(VoiceMacro(command: command, payload: expansion))
        }
        return nil
    }

    static func filtered(_ snippets: [VoiceMacro], by query: String) -> [VoiceMacro] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return snippets }
        return snippets.filter {
            $0.command.localizedCaseInsensitiveContains(needle)
                || $0.payload.localizedCaseInsensitiveContains(needle)
        }
    }
}
