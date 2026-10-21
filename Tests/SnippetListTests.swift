import Foundation

enum SnippetListTests {
    private static let introID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private static let linkID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    private static let snippets = [
        VoiceMacro(id: introID, command: "Intro email", payload: "Hi there, thanks for reaching out."),
        VoiceMacro(id: linkID, command: "my link", payload: "https://example.com/profile"),
    ]

    static func run() {
        normalizesLikeMacroMatching()
        rejectsEmptyTriggerOrExpansion()
        detectsDuplicateTriggersAfterNormalizing()
        editingKeepsItsOwnTrigger()
        saveAppendsNewSnippets()
        saveReplacesEditedSnippetInPlace()
        saveLeavesListUntouchedOnError()
        decodesStoredVoiceMacros()
        filterSearchesTriggerAndExpansion()
    }

    private static func normalizesLikeMacroMatching() {
        TestSupport.expectEqual(SnippetList.normalizedTrigger("  Intro, Email! \n"), "intro email")
        TestSupport.expectEqual(SnippetList.normalizedTrigger("Sign-off."), "signoff")
        TestSupport.expectEqual(SnippetList.normalizedTrigger("?!."), "")
    }

    private static func rejectsEmptyTriggerOrExpansion() {
        TestSupport.expectEqual(SnippetList.validationError(trigger: "  ", expansion: "text", in: snippets), .emptyTrigger)
        TestSupport.expectEqual(SnippetList.validationError(trigger: "...", expansion: "text", in: snippets), .emptyTrigger)
        TestSupport.expectEqual(SnippetList.validationError(trigger: "", expansion: "", in: snippets), .emptyTrigger)
        TestSupport.expectEqual(SnippetList.validationError(trigger: "sign off", expansion: " \n ", in: snippets), .emptyExpansion)
        TestSupport.expectEqual(SnippetList.validationError(trigger: "sign off", expansion: "Cheers", in: snippets), nil)
    }

    private static func detectsDuplicateTriggersAfterNormalizing() {
        TestSupport.expectEqual(SnippetList.validationError(trigger: "INTRO EMAIL", expansion: "x", in: snippets), .duplicateTrigger)
        TestSupport.expectEqual(SnippetList.validationError(trigger: " my link. ", expansion: "x", in: snippets), .duplicateTrigger)
        TestSupport.expectEqual(SnippetList.validationError(trigger: "my links", expansion: "x", in: snippets), nil)
    }

    private static func editingKeepsItsOwnTrigger() {
        TestSupport.expectEqual(
            SnippetList.validationError(trigger: "intro email", expansion: "x", in: snippets, editing: introID),
            nil
        )
        TestSupport.expectEqual(
            SnippetList.validationError(trigger: "My Link", expansion: "x", in: snippets, editing: introID),
            .duplicateTrigger
        )
    }

    private static func saveAppendsNewSnippets() {
        var list = snippets
        TestSupport.expectEqual(SnippetList.save(trigger: "  sign off \n", expansion: "  Cheers,\nSam\n", in: &list), nil)
        TestSupport.expectEqual(list.count, 3)
        TestSupport.expectEqual(Array(list.prefix(2)), snippets)
        TestSupport.expectEqual(list[2].command, "sign off")
        TestSupport.expectEqual(list[2].payload, "  Cheers,\nSam\n")
        TestSupport.expect(!snippets.map(\.id).contains(list[2].id), "new snippet needs a fresh id")
    }

    private static func saveReplacesEditedSnippetInPlace() {
        var list = snippets
        TestSupport.expectEqual(SnippetList.save(trigger: " Intro Email ", expansion: "Hello!", in: &list, editing: introID), nil)
        TestSupport.expectEqual(list, [
            VoiceMacro(id: introID, command: "Intro Email", payload: "Hello!"),
            snippets[1],
        ])
    }

    private static func saveLeavesListUntouchedOnError() {
        var list = snippets
        TestSupport.expectEqual(SnippetList.save(trigger: "my link", expansion: "x", in: &list), .duplicateTrigger)
        TestSupport.expectEqual(SnippetList.save(trigger: "intro email", expansion: "", in: &list, editing: introID), .emptyExpansion)
        TestSupport.expectEqual(list, snippets)
    }

    private static func decodesStoredVoiceMacros() {
        let stored = #"[{"id":"00000000-0000-0000-0000-000000000002","command":"my link","payload":"https://example.com/profile"}]"#
        let decoded = try? JSONDecoder().decode([VoiceMacro].self, from: Data(stored.utf8))
        TestSupport.expectEqual(decoded, [snippets[1]])
    }

    private static func filterSearchesTriggerAndExpansion() {
        TestSupport.expectEqual(SnippetList.filtered(snippets, by: " INTRO ").map(\.id), [introID])
        TestSupport.expectEqual(SnippetList.filtered(snippets, by: "example.com").map(\.id), [linkID])
        TestSupport.expectEqual(SnippetList.filtered(snippets, by: "e").map(\.id), [introID, linkID])
        TestSupport.expectEqual(SnippetList.filtered(snippets, by: "").count, 2)
        TestSupport.expectEqual(SnippetList.filtered(snippets, by: "zzz"), [])
    }
}
