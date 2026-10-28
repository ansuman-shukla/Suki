import Foundation

let usage = """
    usage: suki-mcp [--app NAME]

    Read-only MCP server (stdio) for meetings saved by Suki.
      --app NAME   Read the meetings of another Suki build, e.g. "Suki Dev".
                   Defaults to the app this binary ships inside, else "Suki".

    """

var appName = AppName.displayName
var arguments = CommandLine.arguments.dropFirst()
while let argument = arguments.popFirst() {
    switch argument {
    case "--app" where !(arguments.first ?? "").isEmpty:
        appName = arguments.removeFirst()
    case "-h", "--help":
        FileHandle.standardError.write(Data(usage.utf8))
        exit(0)
    default:
        FileHandle.standardError.write(Data("suki-mcp: unexpected argument \(argument)\n\n\(usage)".utf8))
        exit(64)
    }
}

let store = MeetingStore(directory: MeetingStore.directory(forApp: appName))
let server = MeetingsMCPServer(loadMeetings: store.loadAll)
while let line = readLine() {
    guard !line.isEmpty, let reply = server.handle(line: line) else { continue }
    FileHandle.standardOutput.write(Data((reply + "\n").utf8))
}
