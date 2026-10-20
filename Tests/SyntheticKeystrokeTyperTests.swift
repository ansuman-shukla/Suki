import CoreGraphics
import Foundation

enum SyntheticKeystrokeTyperTests {
    static func run() {
        testEventsAreMarkedAndModifierFree()
        testUnmarkedEventsAreNotSynthetic()
        testChunking()
        testShortcutMonitorIgnoresTypedEvents()
    }

    private static func testShortcutMonitorIgnoresTypedEvents() {
        let backend = GlobalShortcutBackend()
        var inputEvents: [ShortcutInputEvent] = []
        backend.onInputEvent = { event in
            inputEvents.append(event)
            return .consume
        }

        let typed = SyntheticKeystrokeTyper.makeEvent(units: Array("hi".utf16), keyDown: true, source: nil)!
        TestSupport.expect(backend.handleEventTap(type: .keyDown, event: typed) != nil, "Typed events pass through to the focused app")
        let typedUp = SyntheticKeystrokeTyper.makeEvent(units: Array("hi".utf16), keyDown: false, source: nil)!
        _ = backend.handleEventTap(type: .keyUp, event: typedUp)
        TestSupport.expect(inputEvents.isEmpty, "Typed events never reach shortcut matching")

        let physical = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
        TestSupport.expect(backend.handleEventTap(type: .keyDown, event: physical) == nil, "Physical keys still reach shortcut matching")
        TestSupport.expect(!inputEvents.isEmpty, "Physical key events are reported to the shortcut controller")
    }

    private static func testEventsAreMarkedAndModifierFree() {
        let units = Array("héllo".utf16)
        for isKeyDown in [true, false] {
            let event = SyntheticKeystrokeTyper.makeEvent(units: units, keyDown: isKeyDown, source: nil)!
            TestSupport.expect(SyntheticKeystrokeTyper.isSynthetic(event), "Typed events carry the Suki marker")
            TestSupport.expect(event.flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn]).isEmpty,
                               "Typed events carry no modifiers")
            var length = 0
            var buffer = [UniChar](repeating: 0, count: 8)
            event.keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer)
            TestSupport.expectEqual(String(utf16CodeUnits: buffer, count: length), "héllo")
        }
    }

    private static func testUnmarkedEventsAreNotSynthetic() {
        let physical = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
        TestSupport.expect(!SyntheticKeystrokeTyper.isSynthetic(physical), "Unmarked key events reach the shortcut monitor")
        physical.setIntegerValueField(.eventSourceUserData, value: 1)
        TestSupport.expect(!SyntheticKeystrokeTyper.isSynthetic(physical), "Other user data is not mistaken for Suki events")
    }

    private static func testChunking() {
        let max = SyntheticKeystrokeTyper.maxUTF16UnitsPerEvent
        let long = String(repeating: "a", count: max * 2 + 3)
        TestSupport.expectEqual(SyntheticKeystrokeTyper.chunks(of: long).map(\.utf16.count), [max, max, 3])
        TestSupport.expectEqual(SyntheticKeystrokeTyper.chunks(of: ""), [])

        let family = "👨‍👩‍👧"
        let text = String(repeating: "b", count: max - 2) + family
        let chunks = SyntheticKeystrokeTyper.chunks(of: text)
        TestSupport.expectEqual(chunks.joined(), text)
        TestSupport.expect(chunks.allSatisfy { $0.utf16.count <= max }, "Chunks respect the per-event limit")
        TestSupport.expectEqual(chunks.last, family)
    }
}
