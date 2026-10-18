// Probe: which bundle IDs appear more than once in urlsForApplications(toOpen:), and via which paths?
// READ-ONLY (changes nothing).   Run: Tests/probe/run.sh dups
//
// The new list can repeat one app (several copies on disk, a Sparkle staging copy in ~/Library/Caches, ...).
// Readers must therefore dedupe by bundle ID and resolve each ID through
// urlForApplication(withBundleIdentifier:), so a staging copy is never handed to a setter.
// READ-ONLY. Which bundle IDs appear more than once in urlsForApplications(toOpen:), and via which URLs?
import AppKit
import UniformTypeIdentifiers
@_silgen_name("_UTCopyDeclaredTypeIdentifiers") func UTCopyDeclaredTypeIdentifiers() -> NSArray
let kept = (UTCopyDeclaredTypeIdentifiers() as! [String]).filter { UTTypeConformsTo($0 as CFString, "public.item" as CFString) || UTTypeConformsTo($0 as CFString, "public.content" as CFString) }
var byID: [String: Set<String>] = [:]; var utisWithDup = 0
for u in kept {
    let urls = NSWorkspace.shared.urlsForApplications(toOpen: UTType(u)!)
    var seen: [String: [URL]] = [:]
    for url in urls { if let id = Bundle(url: url)?.bundleIdentifier?.lowercased() { seen[id, default: []].append(url) } }
    var dup = false
    for (id, list) in seen where list.count > 1 { dup = true; for l in list { byID[id, default: []].insert(l.path) } }
    if dup { utisWithDup += 1 }
}
print("UTIs with a repeated bundle ID: \(utisWithDup)")
for (id, paths) in byID.sorted(by: { $0.key < $1.key }) { print("  \(id):"); for p in paths.sorted() { print("     \(p)") } }
// And: does the legacy path (bundle ID -> NSWorkspace.urlForApplication(withBundleIdentifier:)) pick one?
print("--- resolved by urlForApplication(withBundleIdentifier:) and urlsForApplications(withBundleIdentifier:)")
for id in byID.keys.sorted() {
    let single = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.path ?? "nil"
    let all = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: id).map { $0.path }
    print("  \(id): single=\(single) all=\(all.count)")
}
