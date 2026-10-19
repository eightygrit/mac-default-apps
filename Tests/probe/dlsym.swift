// Probe: are the private and legacy symbols still reachable through dlsym?
// READ-ONLY (changes nothing).   Run: Tests/probe/run.sh dlsym
//
// LSPrivate.swift and LSLegacyRoles.swift resolve their symbols this way. dlsym takes the C name exactly as
// declared, leading underscore included (the three private functions start with one), so each name below
// must report "found as [<that name>]". The last one does not exist and must report "found as []".
import Foundation
for s in ["_LSCopySchemesAndHandlerURLs", "_LSCopyAllApplicationURLs", "_UTCopyDeclaredTypeIdentifiers", "LSCopyDefaultRoleHandlerForContentType", "LSCopyAllRoleHandlersForContentType", "LSSetDefaultRoleHandlerForContentType", "_LSNoSuchSymbolForTest"] {
    // Also try the name without its leading underscore: it must NOT resolve (that would be a different function).
    let name = s.hasPrefix("_") ? String(s.dropFirst()) : s
    let candidates = s.hasPrefix("_") ? [s, name] : [s]
    var found: [String] = []
    for c in candidates { if dlsym(UnsafeMutableRawPointer(bitPattern: -2), c) != nil { found.append(c) } }  // RTLD_DEFAULT = -2
    print("\(s): dlsym found as \(found)")
}
