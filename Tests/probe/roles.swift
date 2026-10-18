// Probe: which legacy role mask does each new NSWorkspace getter correspond to?
// READ-ONLY (changes nothing).   Run: Tests/probe/run.sh roles      (takes about a minute)
//
// Compares LSCopyDefaultRoleHandlerForContentType / LSCopyAllRoleHandlersForContentType, mask by mask,
// with NSWorkspace.urlForApplication(toOpen:) / urlsForApplications(toOpen:) over every UTI the app lists.
// The row to read is viewer|editor|shell: the new getters answer exactly that mask, not the "all" mask.
// That is the evidence behind the role-less read path (see Tests/README.md for the reference numbers).
// The legacy functions are called on purpose, so compiling this file prints deprecation warnings.
// READ-ONLY. Which legacy role mask does each new NSWorkspace getter correspond to?
import AppKit
import UniformTypeIdentifiers
@_silgen_name("_UTCopyDeclaredTypeIdentifiers") func UTCopyDeclaredTypeIdentifiers() -> NSArray

func bid(_ url: URL?) -> String? { url.flatMap { Bundle(url: $0)?.bundleIdentifier?.lowercased() } }
func def(_ u: String, _ r: LSRolesMask) -> String? { (LSCopyDefaultRoleHandlerForContentType(u as CFString, r)?.takeRetainedValue() as String?)?.lowercased() }
func all(_ u: String, _ r: LSRolesMask) -> Set<String> { Set(((LSCopyAllRoleHandlersForContentType(u as CFString, r)?.takeRetainedValue() as? [String]) ?? []).map { $0.lowercased() }) }

let kept = (UTCopyDeclaredTypeIdentifiers() as! [String]).filter { UTTypeConformsTo($0 as CFString, "public.item" as CFString) || UTTypeConformsTo($0 as CFString, "public.content" as CFString) }
let masks: [(String, LSRolesMask)] = [("all", .all), ("viewer|editor", [.viewer, .editor]), ("viewer", .viewer), ("editor", .editor), ("viewer|editor|shell", [.viewer, .editor, .shell]), ("none", .none)]

print("== default handler: legacy(mask) vs NSWorkspace.urlForApplication(toOpen:) over \(kept.count) UTIs")
for (name, m) in masks {
    var agree = 0, differ = 0, legacyNilNewSome = 0, legacySomeNewNil = 0, bothNil = 0
    for u in kept {
        let o = def(u, m); let n = bid(NSWorkspace.shared.urlForApplication(toOpen: UTType(u)!))
        switch (o, n) { case (nil, nil): bothNil += 1; case (nil, _): legacyNilNewSome += 1; case (_, nil): legacySomeNewNil += 1; case let (a?, b?): if a == b { agree += 1 } else { differ += 1 } }
    }
    print(String(format: "  %-22@ agree=%4d differ=%3d legacyNil/newSome=%3d legacySome/newNil=%3d bothNil=%3d", name as NSString, agree, differ, legacyNilNewSome, legacySomeNewNil, bothNil))
}
print("== all handlers: legacy(mask) set vs set(urlsForApplications(toOpen:)) (bundle IDs)")
for (name, m) in masks {
    var equal = 0, newSuper = 0, newSub = 0, other = 0, dupURLs = 0
    for u in kept {
        let o = all(u, m)
        let urls = NSWorkspace.shared.urlsForApplications(toOpen: UTType(u)!)
        let ids = urls.compactMap { bid($0) }
        if Set(ids).count != ids.count { dupURLs += 1 }
        let n = Set(ids)
        if o == n { equal += 1 } else if n.isSuperset(of: o) { newSuper += 1 } else if o.isSuperset(of: n) { newSub += 1 } else { other += 1 }
    }
    print(String(format: "  %-22@ equal=%4d newSuperset=%3d newSubset=%3d other=%3d | UTIs where new list repeats a bundle ID: %d", name as NSString, equal, newSuper, newSub, other, dupURLs))
}
// ordering: is the legacy default always the first element of urlsForApplications?
var firstIsDefault = 0, tot = 0
for u in kept { let t = UTType(u)!; let urls = NSWorkspace.shared.urlsForApplications(toOpen: t); guard let d = NSWorkspace.shared.urlForApplication(toOpen: t) else { continue }; tot += 1; if urls.first == d { firstIsDefault += 1 } }
print("== urlForApplication(toOpen:) == urlsForApplications(toOpen:).first for \(firstIsDefault) of \(tot) UTIs that have a default")
