import Foundation

struct VocabularyEntry: Identifiable, Equatable {
    let id: Int
    let text: String
}

enum VocabularyEditError: Equatable {
    case empty
    case duplicate
    case containsSeparator
}

/// Editable view of the free-form `custom_vocabulary` string. Entries are split on
/// newlines, commas and semicolons and trimmed, the same rule post-processing uses.
/// Edits only rewrite the touched entry, so the user's own separators and spacing survive.
struct VocabularyList: Equatable {
    static let separators: Set<Character> = ["\n", ",", ";"]

    private var words: [String]
    /// Text around the words: `gaps[i]` precedes `words[i]`, the last gap is the trailing text.
    private var gaps: [String]

    init(_ raw: String) {
        var words: [String] = []
        var gaps: [String] = []
        var pendingGap = ""
        var segment = ""

        func flushSegment() {
            let leading = segment.prefix(while: Self.isTrimmable)
            let rest = segment.dropFirst(leading.count)
            let trailingCount = rest.reversed().prefix(while: Self.isTrimmable).count
            let core = rest.dropLast(trailingCount)
            if core.isEmpty {
                pendingGap += segment
            } else {
                gaps.append(pendingGap + leading)
                words.append(String(core))
                pendingGap = String(rest.suffix(trailingCount))
            }
            segment = ""
        }

        for character in raw {
            if Self.separators.contains(character) {
                flushSegment()
                pendingGap.append(character)
            } else {
                segment.append(character)
            }
        }
        flushSegment()
        gaps.append(pendingGap)

        self.words = words
        self.gaps = gaps
    }

    var serialized: String {
        zip(gaps, words).map { $0 + $1 }.joined() + gaps[words.count]
    }

    var entries: [VocabularyEntry] {
        words.enumerated().map { VocabularyEntry(id: $0.offset, text: $0.element) }
    }

    func filtered(by query: String) -> [VocabularyEntry] {
        let needle = Self.trimmed(query)
        guard !needle.isEmpty else { return entries }
        return entries.filter { $0.text.localizedCaseInsensitiveContains(needle) }
    }

    func validationError(for candidate: String, editing entryID: Int? = nil) -> VocabularyEditError? {
        let word = Self.trimmed(candidate)
        if word.isEmpty { return .empty }
        if word.contains(where: Self.separators.contains) { return .containsSeparator }
        let key = word.lowercased()
        let isDuplicate = words.indices.contains { $0 != entryID && words[$0].lowercased() == key }
        return isDuplicate ? .duplicate : nil
    }

    /// Appends the way the menu bar "Paste Custom Word to Vocabulary" action does: a comma, then a new line.
    @discardableResult
    mutating func add(_ candidate: String) -> VocabularyEditError? {
        if let error = validationError(for: candidate) { return error }
        let word = Self.trimmed(candidate)
        let existing = Self.trimmed(serialized)
        guard let last = existing.last else {
            self = VocabularyList(word)
            return nil
        }
        let joiner = last == "," || last == ";" ? "\n" : ",\n"
        self = VocabularyList(existing + joiner + word)
        return nil
    }

    @discardableResult
    mutating func rename(_ entryID: Int, to candidate: String) -> VocabularyEditError? {
        guard words.indices.contains(entryID) else { return nil }
        if let error = validationError(for: candidate, editing: entryID) { return error }
        words[entryID] = Self.trimmed(candidate)
        return nil
    }

    /// Removes the word together with the separator that follows it (or precedes it, for the last word).
    mutating func delete(_ entryID: Int) {
        guard words.indices.contains(entryID) else { return }
        if words.count == 1 {
            gaps = [gaps[0] + gaps[1]]
        } else if entryID == words.count - 1 {
            gaps.remove(at: entryID)
        } else {
            gaps.remove(at: entryID + 1)
        }
        words.remove(at: entryID)
    }

    private static func isTrimmable(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy(CharacterSet.whitespacesAndNewlines.contains)
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
