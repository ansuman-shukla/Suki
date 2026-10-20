import Foundation

/// Tracks what live typing already inserted into the focused app so each
/// transcript update types only the new tail. Typed text cannot be taken
/// back, so once a provider revises earlier words the session stops typing.
struct LiveTypingCore {
    private(set) var typedText = ""
    private(set) var hasDiverged = false

    /// Returns the new text to type for a stable transcript snapshot. Empty
    /// when nothing is new or the snapshot no longer extends the typed text.
    mutating func textToType(forStable stableText: String) -> String {
        guard !hasDiverged else { return "" }
        let snapshot = LiveTranscriptText.trimmingLeadingWhitespace(stableText)
        guard !snapshot.isEmpty else { return "" }
        guard snapshot.hasPrefix(typedText) else {
            hasDiverged = true
            return ""
        }
        let newText = String(snapshot.dropFirst(typedText.count))
        typedText = snapshot
        return newText
    }

    /// Returns what is left to type once the final transcript is known, or
    /// nil when the final transcript does not extend what was typed. Like
    /// pasted dictation, a sentence-ending transcript gets a trailing space
    /// so the next dictation does not jam against it.
    mutating func remainder(forFinal finalTranscript: String) -> String? {
        let final = finalTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hasDiverged, final.hasPrefix(typedText) else { return nil }
        var remaining = String(final.dropFirst(typedText.count))
        if let last = final.last, ".!?".contains(last) {
            remaining += " "
        }
        typedText = final
        return remaining
    }
}
