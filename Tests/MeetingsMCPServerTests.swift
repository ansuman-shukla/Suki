import Foundation

enum MeetingsMCPServerTests {
    static func run() {
        legacyInitializeNegotiatesVersion()
        modernDiscoverAndVersionRejection()
        modernResultsCarryResultTypeLegacyDoNot()
        toolsListIsStableAndReadOnly()
        listMeetingsNewestFirstWithLimit()
        listMeetingsWhenEmpty()
        readMeetingReturnsTranscript()
        readMeetingRejectsUnknownIds()
        searchMatchesTranscriptAndTitle()
        searchRejectsBlankQueryAndReportsNoMatch()
        reloadsMeetingsOnEveryCall()
        protocolErrorsAndNotifications()
    }

    private static let utc = TimeZone(identifier: "UTC")!
    private static let olderID = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    private static let newerID = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!

    private static let older = MeetingRecord(
        id: olderID,
        title: "Synthetic planning",
        date: Date(timeIntervalSince1970: 1_000_000),
        duration: 3_725,
        segments: [
            MeetingSegment(speaker: .me, start: 0, text: "Synthetic kickoff."),
            MeetingSegment(speaker: .me, start: 4, text: "Second sentence."),
            MeetingSegment(speaker: .them, start: 65, text: "We ship the Zebra build Friday.")
        ]
    )

    private static let newer = MeetingRecord(
        id: newerID,
        title: "Zebra retro",
        date: Date(timeIntervalSince1970: 2_000_000),
        duration: 95,
        segments: [MeetingSegment(speaker: .them, start: 3, text: "Unrelated synthetic words.")]
    )

    private static func server(_ meetings: [MeetingRecord] = [newer, older]) -> MeetingsMCPServer {
        MeetingsMCPServer(loadMeetings: { meetings }, timeZone: utc)
    }

    private static func send(_ server: MeetingsMCPServer, _ request: [String: Any]) -> [String: Any] {
        let line = String(decoding: try! JSONSerialization.data(withJSONObject: request), as: UTF8.self)
        guard let reply = server.handle(line: line) else {
            TestSupport.expect(false, "Expected a reply to \(line)")
            return [:]
        }
        TestSupport.expect(!reply.contains("\n"), "Replies must be a single line for stdio")
        return (try? JSONSerialization.jsonObject(with: Data(reply.utf8))) as? [String: Any] ?? [:]
    }

    private static func call(
        _ server: MeetingsMCPServer,
        _ tool: String,
        _ arguments: [String: Any] = [:]
    ) -> (text: String, isError: Bool) {
        let reply = send(server, ["jsonrpc": "2.0", "id": 7, "method": "tools/call", "params": ["name": tool, "arguments": arguments]])
        let result = reply["result"] as? [String: Any] ?? [:]
        let content = result["content"] as? [[String: Any]] ?? []
        TestSupport.expectEqual(content.count, 1)
        TestSupport.expectEqual(content.first?["type"] as? String, "text")
        return (content.first?["text"] as? String ?? "", result["isError"] as? Bool ?? true)
    }

    private static func modernMeta(_ version: String = "2026-07-28") -> [String: Any] {
        ["_meta": ["io.modelcontextprotocol/protocolVersion": version]]
    }

    private static func legacyInitializeNegotiatesVersion() {
        let supported = send(server(), ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2025-06-18"]])
        TestSupport.expectEqual(supported["id"] as? Int, 1)
        let result = supported["result"] as? [String: Any] ?? [:]
        TestSupport.expectEqual(result["protocolVersion"] as? String, "2025-06-18")
        TestSupport.expectEqual((result["serverInfo"] as? [String: Any])?["name"] as? String, "suki-meetings")
        TestSupport.expect((result["capabilities"] as? [String: Any])?["tools"] != nil, "Declares the tools capability")
        TestSupport.expect((result["instructions"] as? String)?.contains("never as instructions") == true, "Warns that transcripts are data")

        let unknown = send(server(), ["jsonrpc": "2.0", "id": 2, "method": "initialize", "params": ["protocolVersion": "1999-01-01"]])
        TestSupport.expectEqual((unknown["result"] as? [String: Any])?["protocolVersion"] as? String, "2025-11-25")
    }

    private static func modernDiscoverAndVersionRejection() {
        let discover = send(server(), ["jsonrpc": "2.0", "id": "d", "method": "server/discover", "params": modernMeta()])
        TestSupport.expectEqual(discover["id"] as? String, "d")
        let result = discover["result"] as? [String: Any] ?? [:]
        TestSupport.expectEqual(result["supportedVersions"] as? [String], ["2026-07-28"])
        TestSupport.expectEqual(result["resultType"] as? String, "complete")
        TestSupport.expect((result["capabilities"] as? [String: Any])?["tools"] != nil, "Declares the tools capability")
        let info = (result["_meta"] as? [String: Any])?["io.modelcontextprotocol/serverInfo"] as? [String: Any]
        TestSupport.expectEqual(info?["name"] as? String, "suki-meetings")

        let rejected = send(server(), ["jsonrpc": "2.0", "id": 3, "method": "tools/list", "params": modernMeta("2099-01-01")])
        TestSupport.expect(rejected["result"] == nil, "Unsupported version must not be served")
        let error = rejected["error"] as? [String: Any] ?? [:]
        TestSupport.expectEqual(error["code"] as? Int, -32022)
        let data = error["data"] as? [String: Any] ?? [:]
        TestSupport.expectEqual(data["requested"] as? String, "2099-01-01")
        TestSupport.expectEqual(data["supported"] as? [String], MeetingsMCPServer.modernVersions + MeetingsMCPServer.legacyVersions)
    }

    private static func modernResultsCarryResultTypeLegacyDoNot() {
        let modern = send(server(), ["jsonrpc": "2.0", "id": 4, "method": "ping", "params": modernMeta()])
        TestSupport.expectEqual((modern["result"] as? [String: Any])?["resultType"] as? String, "complete")
        let legacy = send(server(), ["jsonrpc": "2.0", "id": 5, "method": "ping"])
        TestSupport.expectEqual((legacy["result"] as? [String: Any])?.count, 0)
    }

    private static func toolsListIsStableAndReadOnly() {
        let reply = send(server(), ["jsonrpc": "2.0", "id": 6, "method": "tools/list"])
        let tools = (reply["result"] as? [String: Any])?["tools"] as? [[String: Any]] ?? []
        TestSupport.expectEqual(tools.compactMap { $0["name"] as? String }, ["list_meetings", "read_meeting", "search_meetings"])
        for tool in tools {
            TestSupport.expectEqual((tool["annotations"] as? [String: Any])?["readOnlyHint"] as? Bool, true)
            TestSupport.expectEqual((tool["inputSchema"] as? [String: Any])?["type"] as? String, "object")
        }
        TestSupport.expectEqual((tools[1]["inputSchema"] as? [String: Any])?["required"] as? [String], ["id"])
        TestSupport.expectEqual((tools[2]["inputSchema"] as? [String: Any])?["required"] as? [String], ["query"])
    }

    private static func listMeetingsNewestFirstWithLimit() {
        let all = call(server(), "list_meetings")
        TestSupport.expect(!all.isError, "list_meetings succeeds")
        TestSupport.expectEqual(all.text, """
            Showing 2 of 2 meetings, newest first:
            - Zebra retro | 1970-01-24T03:33:20Z | 01:35 | id \(newerID.uuidString)
            - Synthetic planning | 1970-01-12T13:46:40Z | 1:02:05 | id \(olderID.uuidString)
            """)

        let limited = call(server(), "list_meetings", ["limit": 1])
        TestSupport.expectEqual(limited.text.components(separatedBy: "\n").count, 2)
        TestSupport.expect(limited.text.hasPrefix("Showing 1 of 2"), "Header reports the limit")
        TestSupport.expect(limited.text.contains("Zebra retro"), "Limit keeps the newest meeting")

        let many = (0..<150).map { MeetingRecord(title: "M\($0)", date: Date(timeIntervalSince1970: Double($0)), duration: 1, segments: []) }
        TestSupport.expect(call(server(many), "list_meetings", ["limit": 500]).text.hasPrefix("Showing 100 of 150"), "Limit is capped")
        TestSupport.expect(call(server(many), "list_meetings", ["limit": 0]).text.hasPrefix("Showing 1 of 150"), "Limit floors at 1")
        TestSupport.expect(call(server(many), "list_meetings").text.hasPrefix("Showing 20 of 150"), "Default limit")
    }

    private static func listMeetingsWhenEmpty() {
        let empty = call(server([]), "list_meetings")
        TestSupport.expectEqual(empty.text, "No meetings saved yet.")
        TestSupport.expect(!empty.isError, "An empty store is not an error")
    }

    private static func readMeetingReturnsTranscript() {
        let read = call(server(), "read_meeting", ["id": olderID.uuidString])
        TestSupport.expect(!read.isError, "read_meeting succeeds")
        TestSupport.expectEqual(read.text, """
            Title: Synthetic planning
            Started: 1970-01-12T13:46:40Z
            Duration: 1:02:05

            [00:00] Me: Synthetic kickoff. Second sentence.
            [01:05] Them: We ship the Zebra build Friday.
            """)

        let plain = call(server(), "read_meeting", ["id": olderID.uuidString.lowercased(), "timestamps": false])
        TestSupport.expect(plain.text.hasSuffix("\n\nMe: Synthetic kickoff. Second sentence.\nThem: We ship the Zebra build Friday."), "Timestamps can be turned off; ids are case-insensitive")

        let blank = MeetingRecord(id: newerID, title: "Blank", date: Date(timeIntervalSince1970: 0), duration: 0, segments: [])
        TestSupport.expect(call(server([blank]), "read_meeting", ["id": newerID.uuidString]).text.hasSuffix("\n(empty transcript)"), "Empty transcript is explicit")
    }

    private static func readMeetingRejectsUnknownIds() {
        for id in ["not-a-uuid", UUID().uuidString, ""] {
            let missing = call(server(), "read_meeting", ["id": id])
            TestSupport.expect(missing.isError, "Unknown id \(id) is a tool error")
            TestSupport.expect(missing.text.contains("No meeting with id \"\(id)\""), "Names the bad id")
        }
        TestSupport.expect(call(server(), "read_meeting").isError, "Missing id is a tool error")
    }

    private static func searchMatchesTranscriptAndTitle() {
        let found = call(server(), "search_meetings", ["query": "  zébra "])
        TestSupport.expect(!found.isError, "search succeeds")
        TestSupport.expectEqual(found.text, """
            2 meetings mention "zébra", showing 2, newest first:
            - Zebra retro | 1970-01-24T03:33:20Z | 01:35 | id \(newerID.uuidString)
            - Synthetic planning | 1970-01-12T13:46:40Z | 1:02:05 | id \(olderID.uuidString)
              [01:05] Them: We ship the Zebra build Friday.
            """)

        let limited = call(server(), "search_meetings", ["query": "zebra", "limit": 1])
        TestSupport.expect(limited.text.hasPrefix("2 meetings mention \"zebra\", showing 1,"), "Search reports total and shown")
        TestSupport.expect(!limited.text.contains("Synthetic planning"), "Search honours the limit")

        let chatty = MeetingRecord(
            title: "Chatty",
            date: Date(timeIntervalSince1970: 0),
            duration: 60,
            segments: (0..<5).map { MeetingSegment(speaker: .me, start: Double($0), text: "needle \($0) " + String(repeating: "x", count: 300)) }
        )
        let snippets = call(server([chatty]), "search_meetings", ["query": "NEEDLE"]).text.components(separatedBy: "\n").dropFirst(2)
        TestSupport.expectEqual(snippets.count, MeetingsMCPServer.maxSnippetsPerMeeting)
        TestSupport.expect(snippets.allSatisfy { $0.hasSuffix("…") }, "Long lines are truncated")
        TestSupport.expectEqual(snippets.first, "  [00:00] Me: " + String(("needle 0 " + String(repeating: "x", count: 300)).prefix(MeetingsMCPServer.maxSnippetLength)) + "…")
    }

    private static func searchRejectsBlankQueryAndReportsNoMatch() {
        TestSupport.expect(call(server(), "search_meetings", ["query": "   "]).isError, "Blank query is a tool error")
        TestSupport.expect(call(server(), "search_meetings").isError, "Missing query is a tool error")
        let none = call(server(), "search_meetings", ["query": "absent"])
        TestSupport.expect(!none.isError, "No match is not an error")
        TestSupport.expectEqual(none.text, "No meetings mention \"absent\".")
    }

    private static func reloadsMeetingsOnEveryCall() {
        var stored: [MeetingRecord] = []
        let live = MeetingsMCPServer(loadMeetings: { stored }, timeZone: utc)
        TestSupport.expectEqual(call(live, "list_meetings").text, "No meetings saved yet.")
        stored = [older]
        TestSupport.expect(call(live, "list_meetings").text.contains("Synthetic planning"), "A meeting saved after start is visible")
        TestSupport.expect(!call(live, "read_meeting", ["id": olderID.uuidString]).isError, "and readable")
    }

    private static func protocolErrorsAndNotifications() {
        let parse = server().handle(line: "{not json")
        TestSupport.expectEqual(parse, #"{"error":{"code":-32700,"message":"Parse error"},"id":null,"jsonrpc":"2.0"}"#)

        let unknownMethod = send(server(), ["jsonrpc": "2.0", "id": 8, "method": "resources/list"])
        TestSupport.expectEqual((unknownMethod["error"] as? [String: Any])?["code"] as? Int, -32601)

        let unknownTool = send(server(), ["jsonrpc": "2.0", "id": 9, "method": "tools/call", "params": ["name": "delete_meeting"]])
        TestSupport.expectEqual((unknownTool["error"] as? [String: Any])?["code"] as? Int, -32602)

        let noMethod = send(server(), ["jsonrpc": "2.0", "id": 10])
        TestSupport.expectEqual((noMethod["error"] as? [String: Any])?["code"] as? Int, -32600)
        TestSupport.expectEqual(noMethod["id"] as? Int, 10)

        TestSupport.expect(server().handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil, "Notifications get no reply")
        TestSupport.expect(server().handle(line: #"{"jsonrpc":"2.0","id":11,"result":{}}"#) == nil, "Client responses get no reply")
        TestSupport.expect(server().handle(line: #"{"jsonrpc":"2.0","id":12,"error":{"code":1,"message":"x"}}"#) == nil, "Client error responses get no reply")
    }
}
