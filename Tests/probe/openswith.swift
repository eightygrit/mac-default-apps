// Probe: which application does Launch Services open each given file with, and what type does the file have?
// READ-ONLY (changes nothing).   Run: Tests/probe/run.sh openswith <file> [file ...]
//
// Prints one tab-separated line per file: path, content type, default application.
// Tests/write-roundtrip.sh uses it to see whether a handler set through --extension reaches a real file.
import AppKit
import UniformTypeIdentifiers

for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.identifier ?? "nil"
    let app = NSWorkspace.shared.urlForApplication(toOpen: url)?.path ?? "nil"
    print("\(path)\ttype=\(type)\topensWith=\(app)")
}
