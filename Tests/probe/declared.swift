// Probe: can per-role handler lists be rebuilt WITHOUT the legacy role API?
// READ-ONLY (changes nothing).   Run: Tests/probe/run.sh declared
//
// Derives "who handles <UTI> as Viewer/Editor/Shell" from urlsForApplications(toOpen:) plus each app's own
// CFBundleTypeRole and compares the result with the legacy answer. It cannot match (see Tests/README.md),
// which is why explicit roles stay on the legacy calls, isolated in LSLegacyRoles.swift.
// The legacy functions are called on purpose, so compiling this file prints deprecation warnings.
// READ-ONLY. Can per-role candidate lists be derived WITHOUT the deprecated role API,
// from urlsForApplications(toOpen:) + each app's declared CFBundleTypeRole?
import AppKit
import UniformTypeIdentifiers
@_silgen_name("_UTCopyDeclaredTypeIdentifiers") func UTCopyDeclaredTypeIdentifiers() -> NSArray

func bid(_ url: URL?) -> String? { url.flatMap { Bundle(url: $0)?.bundleIdentifier?.lowercased() } }
func legacyAll(_ u: String, _ r: LSRolesMask) -> Set<String> { Set(((LSCopyAllRoleHandlersForContentType(u as CFString, r)?.takeRetainedValue() as? [String]) ?? []).map { $0.lowercased() }) }

struct Claim { let types: [UTType]; let role: String }
var claimCache: [String: [Claim]] = [:]
func claims(_ url: URL) -> [Claim] {
    let key = url.path
    if let c = claimCache[key] { return c }
    var out: [Claim] = []
    if let docs = Bundle(url: url)?.infoDictionary?["CFBundleDocumentTypes"] as? [[String: Any]] {
        for d in docs {
            let role = (d["CFBundleTypeRole"] as? String) ?? "Viewer"     // the app's own code treats a missing role as Viewer
            let ts = ((d["LSItemContentTypes"] as? [String]) ?? []).compactMap { UTType($0) }
            out.append(Claim(types: ts, role: role))
        }
    }
    claimCache[key] = out; return out
}
let kept = (UTCopyDeclaredTypeIdentifiers() as! [String]).filter { UTTypeConformsTo($0 as CFString, "public.item" as CFString) || UTTypeConformsTo($0 as CFString, "public.content" as CFString) }
for (roleName, mask) in [("Viewer", LSRolesMask.viewer), ("Editor", .editor), ("Shell", .shell)] {
    var exact = 0, derivedSubset = 0, derivedSuperset = 0, other = 0, missingTotal = 0, extraTotal = 0
    for u in kept {
        let t = UTType(u)!
        let legacy = legacyAll(u, mask)
        var derived = Set<String>()
        for url in NSWorkspace.shared.urlsForApplications(toOpen: t) {
            guard let id = bid(url) else { continue }
            for c in claims(url) where c.role == roleName && c.types.contains(where: { t.conforms(to: $0) }) { derived.insert(id) }
        }
        if derived == legacy { exact += 1 }
        else if derived.isSubset(of: legacy) { derivedSubset += 1; missingTotal += legacy.subtracting(derived).count }
        else if derived.isSuperset(of: legacy) { derivedSuperset += 1; extraTotal += derived.subtracting(legacy).count }
        else { other += 1; missingTotal += legacy.subtracting(derived).count; extraTotal += derived.subtracting(legacy).count }
    }
    print("\(roleName): derived==legacy for \(exact)/\(kept.count); derived⊂legacy \(derivedSubset); derived⊃legacy \(derivedSuperset); mixed \(other); (apps missing \(missingTotal), apps extra \(extraTotal))")
}
