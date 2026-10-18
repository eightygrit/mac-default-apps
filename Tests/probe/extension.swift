// Probe: what does the CLI's --extension (PR #94) turn an extension into, and what type does a real file get?
// READ-ONLY (creates a few empty files and folders in a temporary directory and deletes them again).
// Run: Tests/probe/run.sh extension
//
// Three ways to turn a filename extension into a UTI, over every extension the system declares plus some made up:
//   old      UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, ext, nil)   what #94 calls
//   newAny   UTType(tag: ext, tagClass: .filenameExtension, conformingTo: nil)                the faithful replacement
//   newData  UTType(filenameExtension: ext)    conformingTo defaults to .data: NOT a drop-in
// Then the same for real files and folders, next to what the system says the file's type is.
//
// Known finding (macOS 15.8.1): for an extension the system does not know, old and newAny answer dyn.age8...,
// but a real file with that extension is typed dyn.ah62d4rv4ge8... (the .data-conforming form). A handler set
// on the former may therefore not affect real files; Tests/write-roundtrip.sh unknown-extension answers that.
// The legacy function is called on purpose, so compiling this file prints a deprecation warning.
import Foundation
import UniformTypeIdentifiers
import CoreServices

@_silgen_name("_UTCopyDeclaredTypeIdentifiers") func declaredTypes() -> NSArray

func oldAnswer(_ ext: String) -> String? {
    UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, ext as CFString, nil)?.takeRetainedValue() as String?
}
func newData(_ ext: String) -> String? { UTType(filenameExtension: ext)?.identifier }
func newAny(_ ext: String) -> String? { UTType(tag: ext, tagClass: .filenameExtension, conformingTo: nil)?.identifier }

var exts = Set<String>()
for id in (declaredTypes() as? [String]) ?? [] {
    if let t = UTType(id) { for e in t.tags[.filenameExtension] ?? [] { exts.insert(e) } }
}
for e in ["foobar", "zzzzqq", "md", "MD", "Pdf", "gz", "swift", "yml", "ts"] { exts.insert(e) }

var same = 0, differ = 0, oldOnly = 0, newOnly = 0, samples: [String] = []
var dataDiffer = 0
for e in exts.sorted() {
    let o = oldAnswer(e), n = newAny(e)
    switch (o, n) {
    case (nil, nil): break
    case (let a?, let b?): if a == b { same += 1 } else { differ += 1; if samples.count < 12 { samples.append("\(e): old=\(a) newAny=\(b)") } }
    case (_?, nil): oldOnly += 1
    case (nil, _?): newOnly += 1
    }
    if o != newData(e) { dataDiffer += 1 }
}
print("newAny vs old over \(exts.count) extensions: same=\(same) differ=\(differ) oldOnly=\(oldOnly) newOnly=\(newOnly)")
for s in samples { print("  ", s) }
print("newData (UTType(filenameExtension:)) differs from old for \(dataDiffer) of \(exts.count) extensions")

print("\nWhat does a real file or folder with that extension get (URLResourceValues.contentType)?")
let fm = FileManager.default
let dir = fm.temporaryDirectory.appendingPathComponent("swda-extension-probe-\(UUID().uuidString)")
try fm.createDirectory(at: dir, withIntermediateDirectories: true)
let files = ["x.foobar", "x.zzzzqq", "x.md", "x.pdf", "x.swift", "x.action", "x.appex", "x.app"]
let folders = ["dir.app", "dir.action", "dir.foobar"]
for name in files { fm.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data()) }
for name in folders { try fm.createDirectory(at: dir.appendingPathComponent(name), withIntermediateDirectories: true) }
for name in files + folders {
    let url = dir.appendingPathComponent(name)
    let ext = url.pathExtension
    let real = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.identifier ?? "nil"
    print(String(format: "%-12@ real=%@  old=%@  newData=%@  newAny=%@", name as NSString, real as NSString,
                 (oldAnswer(ext) ?? "nil") as NSString, (newData(ext) ?? "nil") as NSString, (newAny(ext) ?? "nil") as NSString))
}
try? fm.removeItem(at: dir)
