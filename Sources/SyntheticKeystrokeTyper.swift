import CoreGraphics
import Foundation

/// Types text into the focused app with Unicode keyboard events instead of
/// the clipboard. Events carry a private marker so Suki's own shortcut
/// monitor ignores them while the user is still holding the dictation key.
final class SyntheticKeystrokeTyper {
    /// ASCII "SUKIKEYS", stored in the event's source user data field.
    static let eventMarker: Int64 = 0x5355_4B49_4B45_5953
    /// macOS truncates longer Unicode strings attached to one key event.
    static let maxUTF16UnitsPerEvent = 20
    private static let interChunkDelayMicroseconds: useconds_t = 2_000

    private let queue = DispatchQueue(label: "com.ansumanshukla.suki.synthetic-typing")

    /// Types asynchronously in submission order, then calls `completion` on
    /// the main queue.
    func type(_ text: String, completion: (() -> Void)? = nil) {
        queue.async {
            let source = CGEventSource(stateID: .hidSystemState)
            for chunk in Self.chunks(of: text) {
                let units = Array(chunk.utf16)
                for isKeyDown in [true, false] {
                    Self.makeEvent(units: units, keyDown: isKeyDown, source: source)?.post(tap: .cgSessionEventTap)
                }
                usleep(Self.interChunkDelayMicroseconds)
            }
            if let completion {
                DispatchQueue.main.async(execute: completion)
            }
        }
    }

    static func makeEvent(units: [UniChar], keyDown: Bool, source: CGEventSource?) -> CGEvent? {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown) else { return nil }
        // A held dictation modifier must not turn typed text into shortcuts.
        event.flags = []
        event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        event.setIntegerValueField(.eventSourceUserData, value: eventMarker)
        return event
    }

    static func isSynthetic(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == eventMarker
    }

    /// Splits text into event-sized chunks without breaking grapheme clusters.
    static func chunks(of text: String) -> [String] {
        var chunks: [String] = []
        var current = ""
        for character in text {
            if !current.isEmpty, current.utf16.count + character.utf16.count > maxUTF16UnitsPerEvent {
                chunks.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}
