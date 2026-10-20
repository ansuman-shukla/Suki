import Foundation

enum LiveTypingCoreTests {
    static func run() {
        testTypesOnlyNewText()
        testDivergenceStopsTyping()
        testRemainderAtStop()
        testRemainderWhenFinalRevisesTypedText()
    }

    private static func testTypesOnlyNewText() {
        var core = LiveTypingCore()
        TestSupport.expectEqual(core.textToType(forStable: " Hello"), "Hello")
        TestSupport.expectEqual(core.textToType(forStable: " Hello,"), ",")
        TestSupport.expectEqual(core.textToType(forStable: "Hello, this"), " this")
        TestSupport.expectEqual(core.textToType(forStable: "Hello, this"), "")
        TestSupport.expectEqual(core.textToType(forStable: ""), "")
        TestSupport.expectEqual(core.typedText, "Hello, this")
        TestSupport.expect(!core.hasDiverged, "Shorter empty snapshot before speech does not diverge")
    }

    private static func testDivergenceStopsTyping() {
        var core = LiveTypingCore()
        _ = core.textToType(forStable: "Their going")
        TestSupport.expectEqual(core.textToType(forStable: "They're going home"), "")
        TestSupport.expect(core.hasDiverged, "A revised prefix marks the session diverged")
        TestSupport.expectEqual(core.textToType(forStable: "Their going home"), "")
        TestSupport.expectEqual(core.typedText, "Their going")
    }

    private static func testRemainderAtStop() {
        var core = LiveTypingCore()
        _ = core.textToType(forStable: "Ship it")
        TestSupport.expectEqual(core.remainder(forFinal: " Ship it today. \n"), " today. ")
        TestSupport.expectEqual(core.typedText, "Ship it today.")

        var question = LiveTypingCore()
        TestSupport.expectEqual(question.remainder(forFinal: "Ready?"), "Ready? ")

        var unpunctuated = LiveTypingCore()
        _ = unpunctuated.textToType(forStable: "note to self")
        TestSupport.expectEqual(unpunctuated.remainder(forFinal: "note to self"), "")
    }

    private static func testRemainderWhenFinalRevisesTypedText() {
        var core = LiveTypingCore()
        _ = core.textToType(forStable: "twenty three")
        TestSupport.expect(core.remainder(forFinal: "23 times.") == nil, "Final that rewrites typed text cannot be appended")

        var diverged = LiveTypingCore()
        _ = diverged.textToType(forStable: "a")
        _ = diverged.textToType(forStable: "b")
        TestSupport.expect(diverged.remainder(forFinal: "a b") == nil, "Diverged sessions never resume typing")
    }
}
