import Foundation

enum VocabularyListTests {
    static func run() {
        parsesEverySeparatorAndTrimsWords()
        roundTripsUntouchedTextExactly()
        emptyAndSeparatorOnlyTextHasNoEntries()
        addAppendsLikeThePasteAction()
        addRejectsEmptyDuplicateAndSeparatorWords()
        renameKeepsSurroundingFormatting()
        renameAllowsCaseChangeButNotCollision()
        deleteRemovesWordAndOneSeparator()
        deleteIgnoresUnknownEntries()
        filterMatchesCaseInsensitiveSubstrings()
    }

    private static func texts(_ list: VocabularyList) -> [String] {
        list.entries.map(\.text)
    }

    private static func parsesEverySeparatorAndTrimsWords() {
        let list = VocabularyList("  Kubernetes ,gRPC;\n Zoë Quill\t;;\n, PostgreSQL  ")
        TestSupport.expectEqual(texts(list), ["Kubernetes", "gRPC", "Zoë Quill", "PostgreSQL"])
        TestSupport.expectEqual(list.entries.map(\.id), [0, 1, 2, 3])
    }

    private static func roundTripsUntouchedTextExactly() {
        let samples = [
            "",
            "Kubernetes",
            "alpha, beta;gamma\ndelta",
            "  lead,  ,trail  \n\n",
            ",;\n",
            "Acme Corp,\nZoë Quill,\n  gRPC ; ",
        ]
        for sample in samples {
            TestSupport.expectEqual(VocabularyList(sample).serialized, sample)
        }
    }

    private static func emptyAndSeparatorOnlyTextHasNoEntries() {
        TestSupport.expectEqual(texts(VocabularyList("")), [])
        TestSupport.expectEqual(texts(VocabularyList(" ,\n ; ")), [])
    }

    private static func addAppendsLikeThePasteAction() {
        var list = VocabularyList("")
        TestSupport.expectEqual(list.add("  Kubernetes \n"), nil)
        TestSupport.expectEqual(list.serialized, "Kubernetes")

        TestSupport.expectEqual(list.add("gRPC"), nil)
        TestSupport.expectEqual(list.serialized, "Kubernetes,\ngRPC")

        var trailingComma = VocabularyList("alpha, beta,  \n")
        trailingComma.add("gamma")
        TestSupport.expectEqual(trailingComma.serialized, "alpha, beta,\ngamma")

        var trailingSemicolon = VocabularyList("alpha;")
        trailingSemicolon.add("beta")
        TestSupport.expectEqual(trailingSemicolon.serialized, "alpha;\nbeta")

        var trailingNewline = VocabularyList("alpha\n\n")
        trailingNewline.add("beta")
        TestSupport.expectEqual(trailingNewline.serialized, "alpha,\nbeta")
        TestSupport.expectEqual(texts(trailingNewline), ["alpha", "beta"])
    }

    private static func addRejectsEmptyDuplicateAndSeparatorWords() {
        let original = "Kubernetes, gRPC"
        var list = VocabularyList(original)
        TestSupport.expectEqual(list.add("   \n"), .empty)
        TestSupport.expectEqual(list.add(" kubernetes "), .duplicate)
        TestSupport.expectEqual(list.add("GRPC"), .duplicate)
        TestSupport.expectEqual(list.add("foo, bar"), .containsSeparator)
        TestSupport.expectEqual(list.add("foo;bar"), .containsSeparator)
        TestSupport.expectEqual(list.add("foo\nbar"), .containsSeparator)
        TestSupport.expectEqual(list.serialized, original)
        TestSupport.expectEqual(list.validationError(for: "Kube"), nil)
    }

    private static func renameKeepsSurroundingFormatting() {
        var list = VocabularyList("  alpha ,\n beta\t; gamma")
        TestSupport.expectEqual(list.rename(1, to: "  Beta Prime "), nil)
        TestSupport.expectEqual(list.serialized, "  alpha ,\n Beta Prime\t; gamma")

        var withBlanks = VocabularyList("one,,two")
        withBlanks.rename(1, to: "TWO")
        TestSupport.expectEqual(withBlanks.serialized, "one,,TWO")
    }

    private static func renameAllowsCaseChangeButNotCollision() {
        var list = VocabularyList("alpha, beta")
        TestSupport.expectEqual(list.rename(0, to: "ALPHA"), nil)
        TestSupport.expectEqual(list.rename(0, to: "Beta"), .duplicate)
        TestSupport.expectEqual(list.rename(1, to: " "), .empty)
        TestSupport.expectEqual(list.rename(1, to: "b;c"), .containsSeparator)
        TestSupport.expectEqual(list.serialized, "ALPHA, beta")
        TestSupport.expectEqual(list.validationError(for: "beta", editing: 1), nil)
        TestSupport.expectEqual(list.validationError(for: "beta", editing: 0), .duplicate)
    }

    private static func deleteRemovesWordAndOneSeparator() {
        let pasted = "alpha,\nbeta,\ngamma"
        var middle = VocabularyList(pasted)
        middle.delete(1)
        TestSupport.expectEqual(middle.serialized, "alpha,\ngamma")

        var first = VocabularyList(pasted)
        first.delete(0)
        TestSupport.expectEqual(first.serialized, "beta,\ngamma")

        var last = VocabularyList(pasted)
        last.delete(2)
        TestSupport.expectEqual(last.serialized, "alpha,\nbeta")

        var inline = VocabularyList("  alpha, beta; gamma\n")
        inline.delete(1)
        TestSupport.expectEqual(inline.serialized, "  alpha, gamma\n")

        var only = VocabularyList(" solo\n")
        only.delete(0)
        TestSupport.expectEqual(texts(only), [])
        TestSupport.expectEqual(only.serialized, " \n")
    }

    private static func deleteIgnoresUnknownEntries() {
        var list = VocabularyList("alpha, beta")
        list.delete(2)
        list.delete(-1)
        TestSupport.expectEqual(list.rename(5, to: "gamma"), nil)
        TestSupport.expectEqual(list.serialized, "alpha, beta")
    }

    private static func filterMatchesCaseInsensitiveSubstrings() {
        let list = VocabularyList("Kubernetes, kubectl, gRPC, Acme Kube Lab")
        TestSupport.expectEqual(list.filtered(by: "  KUBE ").map(\.text), ["Kubernetes", "kubectl", "Acme Kube Lab"])
        TestSupport.expectEqual(list.filtered(by: "kube").map(\.id), [0, 1, 3])
        TestSupport.expectEqual(list.filtered(by: "").count, 4)
        TestSupport.expectEqual(list.filtered(by: "zzz"), [])
    }
}
