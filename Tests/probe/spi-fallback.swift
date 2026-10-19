// Probe: how well do public-API enumerations reproduce the three private SPI enumerators?
// READ-ONLY (changes nothing).   Run: Tests/probe/run.sh spi-fallback
//
// The reference is _LSCopySchemesAndHandlerURLs / _LSCopyAllApplicationURLs / _UTCopyDeclaredTypeIdentifiers.
// The candidates scan the file system and Spotlight and read Info.plist files. They recover only part of the
// answer (see Tests/README.md), which is why the SPI stays, behind dlsym in LSPrivate.swift, for now.
// The legacy functions are called on purpose, so compiling this file prints deprecation warnings.
// READ-ONLY. How well do public-API enumerations reproduce the three private SPI enumerators?
import AppKit
import UniformTypeIdentifiers
import CoreServices

@_silgen_name("_UTCopyDeclaredTypeIdentifiers") func UTCopyDeclaredTypeIdentifiers() -> NSArray
@_silgen_name("_LSCopySchemesAndHandlerURLs") func LSCopySchemesAndHandlerURLs(_: UnsafeMutablePointer<NSArray?>, _: UnsafeMutablePointer<NSMutableArray?>) -> OSStatus
@_silgen_name("_LSCopyAllApplicationURLs") func LSCopyAllApplicationURLs(_: UnsafeMutablePointer<NSMutableArray?>) -> OSStatus

func plist(_ url: URL) -> [String: Any]? {
    let candidates = [url.appendingPathComponent("Contents/Info.plist"), url.appendingPathComponent("Info.plist"), url.appendingPathComponent("Resources/Info.plist"), url.appendingPathComponent("Versions/A/Resources/Info.plist")]
    for c in candidates {
        if let d = try? Data(contentsOf: c), let o = try? PropertyListSerialization.propertyList(from: d, options: [], format: nil) as? [String: Any] { return o }
    }
    return nil
}
func schemes(in info: [String: Any]) -> Set<String> {
    var s = Set<String>()
    for t in (info["CFBundleURLTypes"] as? [[String: Any]]) ?? [] { for x in (t["CFBundleURLSchemes"] as? [String]) ?? [] { s.insert(x.lowercased()) } }
    return s
}
func utis(in info: [String: Any]) -> Set<String> {
    var s = Set<String>()
    for d in (info["CFBundleDocumentTypes"] as? [[String: Any]]) ?? [] { for x in (d["LSItemContentTypes"] as? [String]) ?? [] { s.insert(x) } }
    for key in ["UTExportedTypeDeclarations", "UTImportedTypeDeclarations"] {
        for d in (info[key] as? [[String: Any]]) ?? [] { if let id = d["UTTypeIdentifier"] as? String { s.insert(id) } }
    }
    return s
}

// ---- reference (SPI)
var spiApps: NSMutableArray?; _ = LSCopyAllApplicationURLs(&spiApps)
let spiAppURLs = (spiApps as! [URL]).map { $0.standardizedFileURL }
var sch: NSArray?; var hs: NSMutableArray?; _ = LSCopySchemesAndHandlerURLs(&sch, &hs)
let spiSchemes = Set((sch as! [String]).map { $0.lowercased() })
let declared = Set(UTCopyDeclaredTypeIdentifiers() as! [String])
let kept = Set(declared.filter { UTTypeConformsTo($0 as CFString, "public.item" as CFString) || UTTypeConformsTo($0 as CFString, "public.content" as CFString) })
var withHandler = Set<String>()
for u in kept { if LSCopyDefaultRoleHandlerForContentType(u as CFString, .all) != nil || (LSCopyAllRoleHandlersForContentType(u as CFString, [.viewer, .editor])?.takeRetainedValue() as? [String] ?? []).count > 0 { withHandler.insert(u) } }
print("SPI: apps=\(spiAppURLs.count) schemes=\(spiSchemes.count) declaredUTIs=\(declared.count) keptUTIs=\(kept.count) keptWithAnyHandler=\(withHandler.count)")

// ---- candidate A: public enumeration of the file system
let fm = FileManager.default
let roots = ["/Applications", "/System/Applications", "/Applications/Utilities", "/System/Applications/Utilities", NSHomeDirectory() + "/Applications", "/System/Library/CoreServices", "/System/Library/CoreServices/Applications", "/Library/Application Support", "/System/Cryptexes/App/System/Applications", "/System/Volumes/Preboot/Cryptexes/App/System/Applications"]
var fsApps = Set<URL>()
func scan(_ dir: URL, depth: Int) {
    guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
    for i in items {
        if i.pathExtension == "app" { fsApps.insert(i.standardizedFileURL) }
        else if depth > 0, (try? i.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { scan(i, depth: depth - 1) }
    }
}
for r in roots { scan(URL(fileURLWithPath: r), depth: r == "/Library/Application Support" ? 2 : 2) }
let spiSet = Set(spiAppURLs)
print("[apps] FileManager scan of standard folders (depth 2): \(fsApps.count) apps; in SPI list: \(fsApps.intersection(spiSet).count); SPI apps missed: \(spiSet.subtracting(fsApps).count)")

// ---- candidate B: Spotlight (public MDQuery)
var mdApps = Set<URL>()
if let q = MDQueryCreate(kCFAllocatorDefault, "kMDItemContentTypeTree == 'com.apple.application-bundle'" as CFString, nil, nil) {
    MDQueryExecute(q, CFOptionFlags(kMDQuerySynchronous.rawValue))
    for i in 0..<MDQueryGetResultCount(q) {
        let item = Unmanaged<MDItem>.fromOpaque(MDQueryGetResultAtIndex(q, i)).takeUnretainedValue()
        if let p = MDItemCopyAttribute(item, kMDItemPath) as? String { mdApps.insert(URL(fileURLWithPath: p).standardizedFileURL) }
    }
}
print("[apps] Spotlight query: \(mdApps.count) apps; in SPI list: \(mdApps.intersection(spiSet).count); SPI apps missed: \(spiSet.subtracting(mdApps).count)")
let both = fsApps.union(mdApps)
print("[apps] FileManager ∪ Spotlight: \(both.count); SPI apps missed: \(spiSet.subtracting(both).count)")

// how many of the SPI apps actually declare something the pane can list (URL schemes or UTIs in CFBundleDocumentTypes)?
var spiRelevant = Set<URL>(); var relevantByInfo = [URL: (Set<String>, Set<String>)]()
for u in spiAppURLs { if let i = plist(u) { let s = schemes(in: i); var d = Set<String>(); for x in (i["CFBundleDocumentTypes"] as? [[String: Any]]) ?? [] { for y in (x["LSItemContentTypes"] as? [String]) ?? [] { d.insert(y) }; for y in (x["CFBundleTypeExtensions"] as? [String]) ?? [] { d.insert("ext:" + y) } }; if !s.isEmpty || !d.isEmpty { spiRelevant.insert(u) }; relevantByInfo[u] = (s, d) } }
print("[apps] SPI apps that declare >=1 scheme/document type (what the Applications tab keeps): \(spiRelevant.count) of \(spiAppURLs.count)")
print("[apps] ...of those, missed by FileManager∪Spotlight: \(spiRelevant.subtracting(both).count)")
for u in spiRelevant.subtracting(both).sorted(by: { $0.path < $1.path }).prefix(8) { print("   e.g. missed \(u.path)") }

// ---- schemes
func collectSchemes(_ urls: [URL]) -> Set<String> { var s = Set<String>(); for u in urls { if let i = plist(u) { s.formUnion(schemes(in: i)) } }; return s }
let schFromSPIApps = collectSchemes(spiAppURLs)
let schFromPublicApps = collectSchemes(Array(both))
print("[schemes] union of CFBundleURLSchemes over SPI app list: \(schFromSPIApps.count); covers SPI schemes: \(schFromSPIApps.intersection(spiSchemes).count)/\(spiSchemes.count)")
print("[schemes] union over public-enumerated apps: \(schFromPublicApps.count); covers SPI schemes: \(schFromPublicApps.intersection(spiSchemes).count)/\(spiSchemes.count); missed: \(spiSchemes.subtracting(schFromPublicApps).sorted().prefix(25))")
print("[schemes] extra (public candidate has, SPI does not): \(schFromPublicApps.subtracting(spiSchemes).count)")

// ---- UTIs
func collectUTIs(_ urls: [URL], extra: [URL]) -> Set<String> { var s = Set<String>(); for u in urls { if let i = plist(u) { s.formUnion(utis(in: i).filter { !$0.hasPrefix("ext:") }) } }; for e in extra { if let i = plist(e) { s.formUnion(utis(in: i)) } }; return s }
let coreTypes = URL(fileURLWithPath: "/System/Library/CoreServices/CoreTypes.bundle")
let uSPIApps = collectUTIs(spiAppURLs, extra: [coreTypes])
let uPublic = collectUTIs(Array(both), extra: [coreTypes])
let uPublicNoCore = collectUTIs(Array(both), extra: [])
for (name, set) in [("SPI apps + CoreTypes", uSPIApps), ("public apps + CoreTypes", uPublic), ("public apps only", uPublicNoCore)] {
    print("[utis] \(name): \(set.count) ids; covers kept: \(set.intersection(kept).count)/\(kept.count); covers kept-with-handler: \(set.intersection(withHandler).count)/\(withHandler.count); covers declared: \(set.intersection(declared).count)/\(declared.count)")
}
// add ancestors (supertypes) of everything found - cheap closure through the public UTType API
var closure = uPublic
for id in uPublic { if let t = UTType(id) { for s in t.supertypes { closure.insert(s.identifier) } } }
print("[utis] public apps + CoreTypes + supertypes closure: \(closure.count); covers kept: \(closure.intersection(kept).count)/\(kept.count); covers kept-with-handler: \(closure.intersection(withHandler).count)/\(withHandler.count)")
let missedWithHandler = withHandler.subtracting(closure)
print("[utis] kept-with-handler NOT recovered: \(missedWithHandler.count) e.g. \(missedWithHandler.sorted().prefix(12))")
