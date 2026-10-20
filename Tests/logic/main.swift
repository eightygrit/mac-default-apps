// Checks of the shared sources that need no GUI and change nothing in Launch Services.
// Build and run with Tests/logic/run.sh. Add a check next to the behavior it pins, and change an expected
// value only together with the code change that makes it change on purpose.
import AppKit
import UniformTypeIdentifiers


// Nothing in this file may write a default handler or register an application for real: every call of a setter is given
// a stand-in that only records what it is asked (`run.sh` refuses a call that is not), and the scripts that run this set
// SWDA_READ_ONLY=1, so that even a call that slipped through could change nothing.
// A stand-in for the three calls that change a default: it records what it is asked and answers as told, so that the
// checks see exactly which call a request reaches, with which arguments.
final class Calls { var log: [String] = [] }
func recorder(_ calls: Calls, system error: Error? = nil, roles status: OSStatus = 0) -> LSWrappers.HandlerSetter {
    LSWrappers.HandlerSetter(
        forUTI: { url, type, done in calls.log.append("uti \(url.path) \(type.identifier)"); done(error) },
        forScheme: { url, scheme, done in calls.log.append("scheme \(url.path) \(scheme)"); done(error) },
        forRoles: { uti, roles, id in calls.log.append("roles \(uti) \(roles.rawValue) \(id)"); return status })
}
func outcome(_ operation: (@escaping (Result<Void, E>) -> Void) -> Void) -> [OSStatus] {
    var reports: [OSStatus] = []
    operation { reports.append(code($0)) }
    return reports
}

// MARK: - LSErrors: raw values and messages (the CLI prints both)

section("LSErrors")
typealias E = LSWrappers.LSErrors
let statusTable: [(OSStatus, E)] = [
    (-67857, .invalidBundle), (-30774, .invalidScheme), (-10825, .incompatibleSys), (-10822, .serverErr),
    (-10814, .appNotFound), (-10811, .notAnApp), (-10810, .defaultErr), (-10660, .deletedApp),
    (262, .invalidFileURL), (-10815, .unknownUTI), (-128, .canceled), (-54, .permissionDenied), (-1712, .timedOut), (0, .noError),
]
for (status, error) in statusTable {
    check("LSErrors(value: \(status))", E(value: status), error)
    check("\(error).rawValue", error.rawValue, status)
}
check("an unknown status maps to defaultErr", E(value: -43), .defaultErr)

check("message: notAnApp", E.notAnApp.print(argument: (app: "Foo", content: nil)),
      "SwiftDefaultApps ERROR -10811: Foo is not a valid application.")
check("message: appNotFound", E.appNotFound.print(argument: (app: "Foo", content: nil)),
      "SwiftDefaultApps ERROR -10814: No application found for Foo")
check("message: appNotFound for Do Nothing", E.appNotFound.print(argument: (app: "None", content: nil)),
      "SwiftDefaultApps ERROR -10814: No application found for None (This error occurs when ThisAppDoesNothing.app is not found.)")
check("message: invalidScheme", E.invalidScheme.print(argument: (app: nil, content: "bad scheme")),
      "SwiftDefaultApps ERROR -30774: bad scheme is not a valid URI Scheme.")
check("message: invalidFileURL", E.invalidFileURL.print(argument: (app: "http://x", content: nil)),
      "SwiftDefaultApps ERROR 262: http://x is not a valid filesystem URL.")
check("message: deletedApp", E.deletedApp.print(argument: (app: "Foo", content: nil)),
      "SwiftDefaultApps ERROR -10660: Foo cannot be accessed because it is in the Trash.")
check("message: serverErr", E.serverErr.print(argument: (app: nil, content: nil)),
      "SwiftDefaultApps ERROR -10822: There was an error trying to communicate with the Launch Services Server.")
check("message: incompatibleSys", E.incompatibleSys.print(argument: (app: "Foo", content: nil)),
      "SwiftDefaultApps ERROR -10825: Foo is not compatible with the currently installed version of macOS.")
check("message: invalidBundle", E.invalidBundle.print(argument: (app: "Foo", content: nil)),
      "SwiftDefaultApps ERROR -67857: Foo is not a valid Package.")
check("message: defaultErr", E.defaultErr.print(argument: (app: nil, content: nil)),
      "SwiftDefaultApps ERROR -10810: An unknown error has occurred.")
check("message: unknownUTI", E.unknownUTI.print(argument: (app: "Foo", content: "no.such.uti")),
      "SwiftDefaultApps ERROR -10815: no.such.uti is not a known UTI.")
check("message: canceled", E.canceled.print(argument: (app: "Foo", content: "public.json")),
      "SwiftDefaultApps ERROR -128: Changing the default handler for public.json was canceled.")
check("message: permissionDenied", E.permissionDenied.print(argument: (app: "Foo", content: "public.json")),
      "SwiftDefaultApps ERROR -54: macOS did not allow changing the default handler for public.json.")
check("message: timedOut", E.timedOut.print(argument: (app: "Foo", content: "public.json")),
      "SwiftDefaultApps ERROR -1712: Timed out waiting for the change of the default handler for public.json.")
check("message: noError", E.noError.print(argument: (app: "Foo", content: nil)),
      "SwiftDefaultApps SUCCESS: Default handler has successfully changed to Foo")
// A missing argument used to be force-unwrapped, which crashed.
for error in [E.notAnApp, .appNotFound, .invalidScheme, .invalidFileURL, .unknownUTI, .deletedApp, .invalidBundle, .incompatibleSys, .canceled, .permissionDenied, .timedOut, .noError] {
    check("message without arguments: \(error)", error.print(argument: (app: nil, content: nil)).hasPrefix(error == .noError ? "SwiftDefaultApps SUCCESS: " : "SwiftDefaultApps ERROR \(error.rawValue): "), true)
}

// MARK: - LSErrors from the errors NSWorkspace reports

section("LSErrors from an Error")
func cocoa(_ code: Int, underlying: NSError? = nil) -> NSError {
    NSError(domain: NSCocoaErrorDomain, code: code, userInfo: underlying.map { [NSUnderlyingErrorKey: $0] } ?? [:])
}
func osStatus(_ code: Int) -> NSError { NSError(domain: NSOSStatusErrorDomain, code: code) }
check("NSUserCancelledError", E(cocoa(NSUserCancelledError)), .canceled)
check("OSStatus -128", E(osStatus(-128)), .canceled)
check("OSStatus -54", E(osStatus(-54)), .permissionDenied)
check("OSStatus of one of our own cases", E(osStatus(-10814)), .appNotFound)
check("a canceled prompt under a file error", E(cocoa(256, underlying: osStatus(-128))), .canceled)
check("a denial under a file error", E(cocoa(256, underlying: osStatus(-54))), .permissionDenied)
check("no permission to write", E(cocoa(NSFileWriteNoPermissionError)), .permissionDenied)
check("no permission to write, a level down", E(cocoa(256, underlying: cocoa(NSFileWriteNoPermissionError))), .permissionDenied)
check("POSIX: operation not permitted", E(NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))), .permissionDenied)
check("POSIX: permission denied", E(NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))), .permissionDenied)
check("another POSIX error", E(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))), .defaultErr)
check("two levels down", E(cocoa(256, underlying: cocoa(4, underlying: osStatus(-128)))), .canceled)
check("a file error alone", E(cocoa(256)), .defaultErr)
check("an unknown OSStatus", E(osStatus(-43)), .defaultErr)
check("OSStatus 0 is not an error", E(osStatus(0)), .defaultErr)
check("another domain with a familiar code", E(NSError(domain: "org.example", code: -128)), .defaultErr)
check("one of ours passes through", E(E.timedOut), .timedOut)
check("one of ours passes through as a plain Error", E(E.deletedApp as Error), .deletedApp)

// MARK: - Which application did the user mean? (stock Apple applications only, so the table holds on any Mac)

section("application resolution")
func resolve(_ input: String) -> (status: OSStatus, bundleID: String?) {
    switch LSWrappers.resolveApp(input) {
    case .success(let app): return (0, app.bundleID)
    case .failure(let error): return (error.rawValue, nil)
    }
}
let resolveTable: [(input: String, status: OSStatus, bundleID: String?)] = [
    ("TextEdit", 0, "com.apple.TextEdit"),
    ("textedit", 0, "com.apple.TextEdit"),
    ("TextEdit.app", 0, "com.apple.TextEdit"),
    ("com.apple.TextEdit", 0, "com.apple.TextEdit"),
    ("/System/Applications/TextEdit.app", 0, "com.apple.TextEdit"),
    ("file:///System/Applications/TextEdit.app", 0, "com.apple.TextEdit"),
    ("Finder", 0, "com.apple.finder"),
    ("/System/Library/CoreServices/Finder.app", 0, "com.apple.finder"),
    ("NoSuchAppAnywhere", -10811, nil),              // a name that matches nothing is "not an application"
    ("org.nonexistent.app", -10811, nil),            // so is a bundle ID that matches nothing
    ("/nonexistent/Foo.app", -10814, nil),           // but a path to nothing is "application not found"
    ("file:///nonexistent/Foo.app", -10814, nil),
    ("/etc/hosts", -10811, nil),                     // a file that is not an application
    ("file:///etc/hosts", -10811, nil),
    ("http://example.com", 262, nil),                // a URL that is not a file URL
]
for row in resolveTable {
    let got = resolve(row.input)
    check("resolve [\(row.input)] status", got.status, row.status)
    check("resolve [\(row.input)] bundle ID", got.bundleID, row.bundleID)
}
// "None" selects Do Nothing, which has to exist somewhere for the answer to be a success.
if DoNothingApp.copyURL() != nil {
    check("resolve [None] finds Do Nothing", resolve("None").bundleID, DoNothingApp.bundleID)
} else {
    check("resolve [None] without a copy of Do Nothing", resolve("None").status, E.appNotFound.rawValue)
}
check("resolve [com.apple.textedit] answers with the identifier the application declares", resolve("com.apple.textedit").bundleID, "com.apple.TextEdit")
check("Do Nothing is selected by None", DoNothingApp.isNamed("None"), true)
check("Do Nothing is selected by its bundle identifier", DoNothingApp.isNamed(DoNothingApp.bundleID), true)
check("Do Nothing is not selected by another spelling", DoNothingApp.isNamed("none"), false)
check("Do Nothing is not selected by nothing", DoNothingApp.isNamed(nil), false)

section("finding applications by name")
check("a name finds the application", LSWrappers.copyAppPaths(named: "TextEdit").map { $0.hasSuffix("/TextEdit.app") }, [true])
check("the name is case-insensitive and .app is optional", LSWrappers.copyAppPaths(named: "textedit.APP"), LSWrappers.copyAppPaths(named: "TextEdit"))
check("a path is returned unchanged", LSWrappers.copyAppPaths(named: "/some/where/Foo.app"), ["/some/where/Foo.app"])
check("a home-relative path is returned unchanged", LSWrappers.copyAppPaths(named: "~/Applications/Foo"), ["~/Applications/Foo"])
check("an unknown name finds nothing", LSWrappers.copyAppPaths(named: "NoSuchAppAnywhere"), [])
check("a registered bundle identifier is installed", LSWrappers.isAppInstalled(withBundleID: "com.apple.TextEdit"), true)
check("an unknown bundle identifier is not installed", LSWrappers.isAppInstalled(withBundleID: "org.nonexistent.app"), false)

// MARK: - Look-alikes: a copy somebody planted must never be the one a name finds

section("planted copies")
let planting = FileManager.default.temporaryDirectory.appendingPathComponent("swda-logic-\(ProcessInfo.processInfo.processIdentifier)")
try? FileManager.default.removeItem(at: planting)
func plant(_ relativePath: String, bundleID: String) -> String { plantAt(planting.appendingPathComponent(relativePath), bundleID: bundleID) }
func plantAt(_ bundle: URL, bundleID: String) -> String {
    let name = bundle.deletingPathExtension().lastPathComponent
    let macOS = bundle.appendingPathComponent("Contents/MacOS")
    try? FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
    let info: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundlePackageType": "APPL", "CFBundleExecutable": name]
    (info as NSDictionary).write(to: bundle.appendingPathComponent("Contents/Info.plist"), atomically: true)
    FileManager.default.createFile(atPath: macOS.appendingPathComponent(name).path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
    return bundle.path
}
let fakeHome = planting.appendingPathComponent("home/Applications").path
let textEdit = "/System/Applications/TextEdit.app"
let inFakeHome = plant("home/Applications/TextEdit.app", bundleID: "com.apple.TextEdit")
let inDownloads = plant("Downloads/TextEdit.app", bundleID: "com.apple.TextEdit")
let inDisk = plant("Volumes/Disk/Foo.app", bundleID: "org.example.foo")
let inDownloads2 = plant("Downloads/Foo.app", bundleID: "org.example.foo2")
let nestedInDisk = plant("Volumes/Disk/Foo.app/Contents/Helpers/Foo.app", bundleID: "org.example.foo.helper")
let inFakeHomeAlone = plant("home/Applications/Alone.app", bundleID: "org.example.alone")
try? FileManager.default.createSymbolicLink(atPath: planting.appendingPathComponent("Link.app").path, withDestinationPath: inDisk)

func best(_ paths: [String]) -> [String] { LSWrappers.copyBestApps(among: paths, userApplications: fakeHome) }
check("a copy in the user's Applications loses to the system's", best([inFakeHome, textEdit]), [textEdit])
check("whatever the order they are given in", best([textEdit, inFakeHome, inDownloads]), [textEdit])
check("a copy in the user's Applications beats one anywhere else", best([inDownloads, inFakeHome]), [inFakeHome])
check("a copy anywhere else is still found when it is the only one", best([inFakeHomeAlone]), [inFakeHomeAlone])
check("a copy inside another bundle loses to one outside", best([nestedInDisk, inDisk]), [inDisk])
check("two different applications in one place tie", best([inDownloads2, inDisk]), [inDisk, inDownloads2].sorted())
check("two paths to one file count once", best([inDisk, planting.appendingPathComponent("Link.app").path]).count, 1)
check("nothing in, nothing out", best([]), [])
for (path, location) in [("/Applications/Foo.app", LSWrappers.AppLocation.system),
                         ("/Applications/Utilities/Terminal.app", .system),
                         ("/System/Applications/TextEdit.app", .system),
                         ("/System/Library/CoreServices/Finder.app", .system),
                         ("/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app", .system),
                         ("/System/Volumes/Data/Applications/Foo.app", .system),
                         ("/System/Volumes/Data/Users/someone/Downloads/Foo.app", .elsewhere),
                         ("/Library/Foo/Helper.app", .system),
                         ("/Users/someone/Downloads/Foo.app", .elsewhere),
                         ("/Volumes/Disk/Foo.app", .elsewhere),
                         ("/tmp/Applications/Foo.app", .elsewhere),
                         ("/Applicationsx/Foo.app", .elsewhere),
                         ("\(fakeHome)/Foo.app", .user),
                         ("\(fakeHome)x/Foo.app", .elsewhere)] {
    check("location of \(path)", LSWrappers.AppLocation(path: path, userApplications: fakeHome), location)
}
for (text, shaped) in [("com.apple.TextEdit", true), ("cl.fail.lordkamina.ThisAppDoesNothing", true), ("com.example.my-app_1", true),
                       ("Safari", false), ("TextEdit.app", false), ("Visual Studio Code", false), ("/Applications/Foo.app", false), ("~/Foo.bar", false),
                       ("", false), (".", false), ("com..x", false), ("com.example.", false), ("com.ex\u{00E4}mple.x", false), ("com.example.x\n", false)] {
    check("isBundleID(\(text.debugDescription))", LSWrappers.isBundleID(text), shaped)
}
check("a planted Do Nothing with the right identifier is not genuine", DoNothingApp.isGenuine(URL(fileURLWithPath: plant("Downloads/ThisAppDoesNothing.app", bundleID: DoNothingApp.bundleID))), false)
var registrations: [URL] = []
check("a planted Do Nothing is not registered on demand", LSWrappers.ensureRegistered(LSWrappers.ResolvedApp(url: URL(fileURLWithPath: planting.appendingPathComponent("Downloads/ThisAppDoesNothing.app").path), bundleID: DoNothingApp.bundleID), register: { registrations.append($0); return true }), false)
check("... and nothing was registered", registrations, [])
// Do Nothing is handed out from a folder the program ships it in. A copy there is taken for Do Nothing only if it is Do Nothing:
// the same name and place, with another identifier or without a program to run, is not. (`Bundle` remembers a bundle by its
// path, so each case has a folder of its own.)
func genuine(_ folder: String, bundleID: String, programmed: Bool = true, allowing allowed: String? = nil) -> Bool {
    let home = planting.appendingPathComponent(folder)
    let copy = home.appendingPathComponent(DoNothingApp.fileName)
    _ = plantAt(copy, bundleID: bundleID)
    if !programmed { try? FileManager.default.removeItem(at: copy.appendingPathComponent("Contents/MacOS")) }
    return DoNothingApp.isGenuine(copy, allowed: [planting.appendingPathComponent(allowed ?? folder)])
}
check("a copy of Do Nothing in a folder it ships in is genuine", genuine("Shipped", bundleID: DoNothingApp.bundleID), true)
check("... but not in any other folder", genuine("Shipped2", bundleID: DoNothingApp.bundleID, allowing: "Somewhere Else"), false)
check("a copy with another identifier in the same place is not", genuine("Impostor", bundleID: "org.example.not-do-nothing"), false)
check("a copy with no program to run in the same place is not", genuine("Hollow", bundleID: DoNothingApp.bundleID, programmed: false), false)
check("an application that is not Do Nothing is not genuine", DoNothingApp.isGenuine(URL(fileURLWithPath: textEdit)), false)
check("a missing Do Nothing is not genuine", DoNothingApp.isGenuine(URL(fileURLWithPath: "/nonexistent/ThisAppDoesNothing.app")), false)
check("an ambiguous name asks for a path", E.ambiguousApp.print(argument: (app: "NoSuchAppAnywhere", content: nil)),
      "SwiftDefaultApps ERROR 1001: NoSuchAppAnywhere matches more than one application. Give the path of the one you mean.")
check("1001 is ours", E(value: 1001), .ambiguousApp)
check("1001 from the system is not", E(NSError(domain: NSOSStatusErrorDomain, code: 1001)), .defaultErr)
check("what was typed is shown with its control characters escaped", E.notAnApp.print(argument: (app: "a\u{1B}[2J", content: nil)),
      "SwiftDefaultApps ERROR -10811: a\\u{1B}[2J is not a valid application.")
func plantBundle(_ relativePath: String, packageType: String?, bundleID: String?) -> String {
    let bundle = planting.appendingPathComponent(relativePath)
    try? FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents"), withIntermediateDirectories: true)
    var info: [String: Any] = [:]
    if let packageType { info["CFBundlePackageType"] = packageType }
    if let bundleID { info["CFBundleIdentifier"] = bundleID }
    (info as NSDictionary).write(to: bundle.appendingPathComponent("Contents/Info.plist"), atomically: true)
    return bundle.path
}
func resolved(_ input: String, copyPaths: @escaping (String) -> [String] = { LSWrappers.copyAppPaths(named: $0) }) -> (status: OSStatus, bundleID: String?, path: String?) {
    switch LSWrappers.resolveApp(input, copyPaths: copyPaths) {
    case .success(let app): return (0, app.bundleID, app.url.resolvingSymlinksInPath().path)
    case .failure(let error): return (error.rawValue, nil, nil)
    }
}
let planted = resolved(plant("Elsewhere/Planted.app", bundleID: "org.example.planted"))
check("a path to an application resolves to its own identifier", planted.bundleID, "org.example.planted")
check("a path to an application resolves to that very copy", planted.path, planting.appendingPathComponent("Elsewhere/Planted.app").resolvingSymlinksInPath().path)
check("a name that two applications share is not guessed at", resolved("Foo", copyPaths: { _ in [inDisk, inDownloads2] }).status, E.ambiguousApp.rawValue)
check("a name that one application has resolves to it", resolved("Foo", copyPaths: { _ in [inDisk] }).bundleID, "org.example.foo")
check("a name that nothing has is not an application", resolved("Foo", copyPaths: { _ in [] }).status, E.notAnApp.rawValue)
check("a plug-in bundle is not an application", resolved(plantBundle("Elsewhere/Plugin.app", packageType: "BNDL", bundleID: "org.example.plugin")).status, E.notAnApp.rawValue)
check("a bundle without a package type is not a valid package", resolved(plantBundle("Elsewhere/Bare.app", packageType: nil, bundleID: "org.example.bare")).status, E.invalidBundle.rawValue)
check("an application without a bundle identifier is not usable", resolved(plantBundle("Elsewhere/Nameless.app", packageType: "APPL", bundleID: nil)).status, E.notAnApp.rawValue)
check("a directory that is not a bundle is not a valid package", resolved(planting.appendingPathComponent("Elsewhere").path).status, E.invalidBundle.rawValue)
check("a file URL to an application resolves too", resolved(URL(fileURLWithPath: planted.path ?? "").absoluteString).bundleID, "org.example.planted")
check("a file URL to a plug-in bundle is not an application", resolved(URL(fileURLWithPath: planting.appendingPathComponent("Elsewhere/Plugin.app").path).absoluteString).status, E.notAnApp.rawValue)
try? FileManager.default.removeItem(at: planting)

// MARK: - Setters: requests that must be refused before anything is written

section("setters refuse before writing")
let noWrites = Calls()
let untouched = recorder(noWrites)
// A refusal reports at once, exactly once, and before the setter returns.
func refusal(_ operation: (@escaping (Result<Void, E>) -> Void) -> Void) -> E? {
    var reports: [Result<Void, E>] = []
    operation { reports.append($0) }
    guard reports.count == 1, case .failure(let error) = reports[0] else { return nil }
    return error
}
// Every request below names an application that does not exist, or a UTI that does not exist, or, where a real UTI is needed so that the
// application is what gets refused, one that nobody depends on: were a check ever skipped, nothing of value could be changed.
let harmlessUTI = "public.xbitmap-image"
let missingApp = LSWrappers.ResolvedApp(url: URL(fileURLWithPath: "/nonexistent/Foo.app"), bundleID: "org.nonexistent.app")
check("scheme with a space", refusal { LSWrappers.Schemes.setDefaultHandler("bad scheme", missingApp, setter: untouched, completion: $0) }, .invalidScheme)
check("scheme starting with a digit", refusal { LSWrappers.Schemes.setDefaultHandler("1bad", missingApp, setter: untouched, completion: $0) }, .invalidScheme)
check("scheme handler that is not installed", refusal { LSWrappers.Schemes.setDefaultHandler("nosuchscheme", missingApp, setter: untouched, completion: $0) }, .appNotFound)
check("UTI handler that is not installed", refusal { LSWrappers.UTIs.setDefaultHandler(harmlessUTI, missingApp, .all, setter: untouched, completion: $0) }, .appNotFound)
check("UTI handler that is not installed, for one role", refusal { LSWrappers.UTIs.setDefaultHandler(harmlessUTI, missingApp, .viewer, setter: untouched, completion: $0) }, .appNotFound)
check("an application that is not installed is not registered on demand", LSWrappers.ensureRegistered(missingApp, register: { _ in false }), false)
if case .success(let textEdit) = LSWrappers.resolveApp("com.apple.TextEdit") {
    check("a UTI nobody declared, for an installed application", refusal { LSWrappers.UTIs.setDefaultHandler("no.such.uti", textEdit, setter: untouched, completion: $0) }, .unknownUTI)
} else {
    check("TextEdit resolves", false, true)
}
check("a UTI nobody declared, for a missing application", refusal { LSWrappers.UTIs.setDefaultHandler("no.such.uti", missingApp, setter: untouched, completion: $0) }, .unknownUTI)
check("a UTI nobody declared, for one role and a missing application", refusal { LSWrappers.UTIs.setDefaultHandler("no.such.uti", missingApp, .viewer, setter: untouched, completion: $0) }, .unknownUTI)
if case .success(let textEdit) = LSWrappers.resolveApp("com.apple.TextEdit") {
    check("a UTI nobody declared, for one role and an installed application", refusal { LSWrappers.UTIs.setDefaultHandler("no.such.uti", textEdit, .viewer, setter: untouched, completion: $0) }, .unknownUTI)
    check("a UTI nobody declared, for viewer and editor", refusal { LSWrappers.UTIs.setDefaultHandler("no.such.uti", textEdit, [.viewer, .editor], setter: untouched, completion: $0) }, .unknownUTI)
}
check("none of the refusals reached the system", noWrites.log, [])

// MARK: - Setters: what a request that gets through asks the system for

section("setters call the system as asked")
if case .success(let editor) = LSWrappers.resolveApp("com.apple.TextEdit") {
    let path = editor.url.path
    func uti(_ roles: LSRolesMask, _ setter: LSWrappers.HandlerSetter) -> [OSStatus] { outcome { LSWrappers.UTIs.setDefaultHandler(harmlessUTI, editor, roles, setter: setter, completion: $0) } }
    let calls = Calls()
    check("All roles go through NSWorkspace, once", uti(.all, recorder(calls)), [0])
    check("... as the application at that path and the UTI", calls.log, ["uti \(path) \(harmlessUTI)"])
    calls.log = []
    check("Viewer, Editor and Shell together are All roles", uti([.viewer, .editor, .shell], recorder(calls)), [0])
    check("... and go through NSWorkspace too", calls.log, ["uti \(path) \(harmlessUTI)"])
    for (name, roles) in [("Viewer", LSRolesMask.viewer), ("Editor", .editor), ("Shell", .shell), ("Viewer and Editor", [.viewer, .editor]), ("Editor and Shell", [.editor, .shell])] {
        calls.log = []
        check("\(name) alone is not widened: it reports once", uti(roles, recorder(calls)), [0])
        check("\(name) alone is one call for those roles, by bundle identifier", calls.log, ["roles \(harmlessUTI) \(roles.rawValue) com.apple.TextEdit"])
    }
    calls.log = []
    check("a status from the per-role call is the answer", uti(.viewer, recorder(calls, roles: -54)), [E.permissionDenied.rawValue])
    check("an unknown status from the per-role call is a plain failure", uti(.viewer, recorder(calls, roles: -43)), [E.defaultErr.rawValue])
    check("a canceled confirmation is reported as canceled", uti(.all, recorder(calls, system: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))), [E.canceled.rawValue])
    check("a refusal from the system is reported as it is", uti(.all, recorder(calls, system: NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError))), [E.permissionDenied.rawValue])
    calls.log = []
    check("a scheme goes through NSWorkspace, once", outcome { LSWrappers.Schemes.setDefaultHandler("web+example", editor, setter: recorder(calls), completion: $0) }, [0])
    check("... with the scheme as given", calls.log, ["scheme \(path) web+example"])
    // Nothing that is refused up front reaches the system at all.
    calls.log = []
    check("a UTI nobody declared writes nothing", uti(.viewer, recorder(calls)).count, 1)
    check("an invalid scheme is refused", outcome { LSWrappers.Schemes.setDefaultHandler("bad scheme", editor, setter: recorder(calls), completion: $0) }, [E.invalidScheme.rawValue])
    check("an application that is not installed is refused", outcome { LSWrappers.UTIs.setDefaultHandler(harmlessUTI, missingApp, .all, setter: recorder(calls), completion: $0) }, [E.appNotFound.rawValue])
    check("... for one role too", outcome { LSWrappers.UTIs.setDefaultHandler(harmlessUTI, missingApp, .viewer, setter: recorder(calls), completion: $0) }, [E.appNotFound.rawValue])
    check("... for a scheme too", outcome { LSWrappers.Schemes.setDefaultHandler("web+example", missingApp, setter: recorder(calls), completion: $0) }, [E.appNotFound.rawValue])
    check("an unknown UTI is refused", outcome { LSWrappers.UTIs.setDefaultHandler("no.such.uti", editor, .all, setter: recorder(calls), completion: $0) }, [E.unknownUTI.rawValue])
    check("the refusals wrote nothing", calls.log.filter { !$0.hasPrefix("roles \(harmlessUTI)") }, [])
} else {
    check("TextEdit resolves", false, true)
}

// MARK: - Waiting for a completion (the command line, and the app on a background queue)

section("awaitCompletion")
func code(_ result: Result<Void, E>) -> OSStatus {
    switch result {
    case .success: return 0
    case .failure(let error): return error.rawValue
    }
}
func timed(_ body: () -> Result<Void, E>) -> (code: OSStatus, seconds: TimeInterval) {
    let start = Date()
    let result = body()
    return (code(result), Date().timeIntervalSince(start))
}
check("an immediate success", code(LSWrappers.awaitCompletion { $0(.success(())) }), 0)
check("an immediate failure", code(LSWrappers.awaitCompletion { $0(.failure(.canceled)) }), E.canceled.rawValue)
let slow = timed { LSWrappers.awaitCompletion { completion in DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { completion(.failure(.permissionDenied)) } } }
check("a report from another queue", slow.code, E.permissionDenied.rawValue)
check("it waited for it", slow.seconds >= 0.2 && slow.seconds < 2, true)
let hop = timed { LSWrappers.awaitCompletion { completion in DispatchQueue.main.async { completion(.failure(.canceled)) } } }
check("a report dispatched to the main queue still arrives", hop.code, E.canceled.rawValue)
check("without waiting for the timeout", hop.seconds < 2, true)
check("the first report wins", code(LSWrappers.awaitCompletion { completion in completion(.success(())); completion(.failure(.canceled)) }), 0)
var lateReport: ((Result<Void, E>) -> Void)?
let expired = timed { LSWrappers.awaitCompletion(timeout: 0.3) { lateReport = $0 } }
check("no report in time", expired.code, E.timedOut.rawValue)
check("the time is up when it says", expired.seconds >= 0.3 && expired.seconds < 2, true)
// A report that comes after the time is up changes nothing anyone can see, since the caller already has its answer. It only has to return.
lateReport?(.success(()))
check("an operation that never reports and has no time", code(LSWrappers.awaitCompletion(timeout: 0) { _ in }), E.timedOut.rawValue)
check("no error is success", code(Result(error: nil)), 0)
check("an NSError is mapped", code(Result(error: NSError(domain: NSOSStatusErrorDomain, code: -128))), E.canceled.rawValue)
// What macOS said about an error nothing explains goes to the unified log (os.Logger in LSWrappers.swift), which a test cannot
// read cheaply; the user still gets the unknown error.
check("an error nothing explains is the unknown error", code(Result(error: NSError(domain: "org.example", code: 7, userInfo: [NSLocalizedDescriptionKey: "100% odd %@ %n"]))), E.defaultErr.rawValue)

// MARK: - Extension to UTI (PR #94)

section("extension to UTI")
check("pdf", LSWrappers.UTIs.copyUTIForExtension("pdf"), "com.adobe.pdf")
check(".pdf (leading dot)", LSWrappers.UTIs.copyUTIForExtension(".pdf"), "com.adobe.pdf")
check("html", LSWrappers.UTIs.copyUTIForExtension("html"), "public.html")
check("txt", LSWrappers.UTIs.copyUTIForExtension("txt"), "public.plain-text")
check("empty", LSWrappers.UTIs.copyUTIForExtension(""), nil)
check("dots only", LSWrappers.UTIs.copyUTIForExtension("..."), nil)
check("extensions of a UTI", LSWrappers.UTIs.copyExtensionsFor("com.adobe.pdf")?.contains("pdf"), true)
check("a UTI without extensions", LSWrappers.UTIs.copyExtensionsFor("public.item"), nil)
check("an unknown UTI has no extensions", LSWrappers.UTIs.copyExtensionsFor("no.such.uti"), nil)
let everyUTI = LSWrappers.UTIs.copyAllUTIs() ?? [:]
check("copyAllUTIs lists public.html", everyUTI["public.html"] != nil, true)
check("copyAllUTIs does not list an unknown UTI", everyUTI["no.such.uti"] == nil, true)
check("copyAllUTIs is not trivially small", everyUTI.count > 500, true)

// MARK: - The private enumerations (looked up with dlsym, so a missing one is nil, never a crash)

section("private enumerations")
check("a symbol that does not exist is nil", LSPrivate.symbol("_LSNoSuchFunctionForTest", as: (@convention(c) () -> Int32).self) == nil, true)
let declaredUTIs = LSPrivate.copyDeclaredTypeIdentifiers()
check("declared UTIs are listed", (declaredUTIs?.count ?? 0) > 1000, true)
check("declared UTIs include public.html", declaredUTIs?.contains("public.html"), true)
let registeredApps = LSPrivate.copyAllApplicationURLs()
check("applications are listed", (registeredApps?.count ?? 0) > 50, true)
check("Finder is registered", registeredApps?.contains { $0.lastPathComponent == "Finder.app" }, true)
let schemeList = LSPrivate.copySchemesAndHandlerURLs()
check("schemes and handlers pair up", schemeList.map { $0.schemes.count == $0.handlers.count }, true)
check("http is a registered scheme", schemeList?.schemes.contains("http"), true)
check("copySchemesAndHandlers maps http to an application", LSWrappers.Schemes.copySchemesAndHandlers()?["http"]?.hasSuffix(".app"), true)
check("copyAllApps returns paths", LSWrappers.copyAllApps()?.first?.hasPrefix("/"), true)

// MARK: - Handlers as the callers want them (NSWorkspace answers with application URLs)

section("copyHandlers")
let textEditURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit")!
let calculatorURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.calculator")!
check("bundle identifiers, repeated applications counted once", LSWrappers.copyHandlers(from: [textEditURL, calculatorURL, textEditURL], asPath: false), ["com.apple.TextEdit", "com.apple.calculator"])
check("paths keep the order given", LSWrappers.copyHandlers(from: [calculatorURL, textEditURL], asPath: true), [calculatorURL.path, textEditURL.path])
let applicationsFolder = textEditURL.deletingLastPathComponent()
let roundabout = URL(fileURLWithPath: applicationsFolder.path + "/../" + applicationsFolder.lastPathComponent + "/" + textEditURL.lastPathComponent)
check("the URL used below really spells the path differently", roundabout.path != textEditURL.path, true)
check("a path comes from the bundle identifier, not the URL given", LSWrappers.copyHandlers(from: [roundabout], asPath: true), [textEditURL.path])
check("nothing in, nil out", LSWrappers.copyHandlers(from: [], asPath: true), nil)
check("a folder that is not an application is skipped", LSWrappers.copyHandlers(from: [URL(fileURLWithPath: "/tmp")], asPath: false), nil)

// MARK: - URI Scheme reads

section("URI Scheme reads")
check("mailto has a default handler", LSWrappers.Schemes.copyDefaultHandler("mailto")?.hasSuffix(".app"), true)
check("http has a default handler as a bundle identifier", LSWrappers.Schemes.copyDefaultHandler("http", asPath: false)?.contains("."), true)
check("the default handler is one of all the handlers", LSWrappers.Schemes.copyAllHandlers("http", asPath: false)?.map { $0.lowercased() }.contains(LSWrappers.Schemes.copyDefaultHandler("http", asPath: false)?.lowercased() ?? ""), true)
let httpHandlers = LSWrappers.Schemes.copyAllHandlers("http", asPath: false) ?? []
check("no application is listed twice", Set(httpHandlers.map { $0.lowercased() }).count, httpHandlers.count)
check("a scheme is not case-sensitive", LSWrappers.Schemes.copyDefaultHandler("HTTP"), LSWrappers.Schemes.copyDefaultHandler("http"))
check("file is answered, although NSWorkspace only takes file:///", LSWrappers.Schemes.copyDefaultHandler("file"), "/System/Library/CoreServices/Finder.app")
check("Finder is among the handlers of file", LSWrappers.Schemes.copyAllHandlers("file")?.contains("/System/Library/CoreServices/Finder.app"), true)
check("an unknown scheme has no default handler", LSWrappers.Schemes.copyDefaultHandler("nosuchscheme"), nil)
check("an unknown scheme has no handlers", LSWrappers.Schemes.copyAllHandlers("nosuchscheme"), nil)
check("something that is not a scheme has no handlers", LSWrappers.Schemes.copyAllHandlers("bad scheme"), nil)
check("an unknown scheme has no name", LSWrappers.Schemes.copyNameForScheme("nosuchscheme"), nil)

// MARK: - Which requests are for All roles

section("requests for All roles")
check("all roles", LSLegacyRoles.isAllRoles(.all), true)
check("viewer, editor and shell together", LSLegacyRoles.isAllRoles([.viewer, .editor, .shell]), true)
check("every role named", LSLegacyRoles.isAllRoles([.none, .viewer, .editor, .shell]), true)
check("viewer and editor are not enough", LSLegacyRoles.isAllRoles([.viewer, .editor]), false)
check("viewer", LSLegacyRoles.isAllRoles(.viewer), false)
check("editor", LSLegacyRoles.isAllRoles(.editor), false)
check("shell", LSLegacyRoles.isAllRoles(.shell), false)
check("none", LSLegacyRoles.isAllRoles(.none), false)
check("no role at all", LSLegacyRoles.isAllRoles([]), false)
let htmlType = UTType("public.html")!
check("a default for All roles is what NSWorkspace opens", LSWrappers.UTIs.copyDefaultHandler("public.html"), NSWorkspace.shared.urlForApplication(toOpen: htmlType)?.path)
check("the default argument is All roles", LSWrappers.UTIs.copyDefaultHandler("public.html"), LSWrappers.UTIs.copyDefaultHandler("public.html", inRoles: .all))
check("all roles are the handlers NSWorkspace lists", LSWrappers.UTIs.copyAllHandlers("public.html"), LSWrappers.copyHandlers(from: NSWorkspace.shared.urlsForApplications(toOpen: htmlType), asPath: true))
check("Safari can open public.html", LSWrappers.UTIs.copyAllHandlers("public.html", asPath: false)?.contains("com.apple.Safari"), true)
let htmlHandlers = LSWrappers.UTIs.copyAllHandlers("public.html", asPath: false) ?? []
check("no application is listed twice for a type", Set(htmlHandlers.map { $0.lowercased() }).count, htmlHandlers.count)
check("a default for All roles is one of the handlers for All roles", LSWrappers.UTIs.copyAllHandlers("public.html", asPath: false)?.contains(LSWrappers.UTIs.copyDefaultHandler("public.html", asPath: false) ?? ""), true)
check("an unknown UTI has no default for All roles", LSWrappers.UTIs.copyDefaultHandler("no.such.uti"), nil)
// Every role of public.html is one application on most Macs, so it cannot tell the two paths apart. Some types open with an
// application other than their Viewer (Books, not Preview, is the Viewer of a PDF): one such type, found at run time, shows that
// a narrower mask is answered by the legacy function and not by NSWorkspace.
func opensWith(_ identifier: String) -> String? {
    guard let type = UTType(identifier), let url = NSWorkspace.shared.urlForApplication(toOpen: type) else { return nil }
    return Bundle(url: url)?.bundleIdentifier?.lowercased()
}
let narrowerMasks: [(name: String, roles: LSRolesMask)] = [("viewer", .viewer), ("viewer and editor together", [.viewer, .editor])]
for (name, roles) in narrowerMasks {
    let found = (declaredUTIs ?? []).sorted().first { identifier in
        guard let legacy = LSLegacyRoles.copyDefaultHandlerID(identifier, roles)?.lowercased(), let opens = opensWith(identifier) else { return false }
        return legacy != opens
    }
    guard let identifier = found else {
        print("skip  \(name): no type has a default for it other than what opens the file, so the routing cannot be told apart here")
        continue
    }
    let answer = LSWrappers.UTIs.copyDefaultHandler(identifier, inRoles: roles, asPath: false)?.lowercased()
    check("\(name) is answered by the legacy function [\(identifier)]", answer, LSLegacyRoles.copyDefaultHandlerID(identifier, roles)?.lowercased())
    check("\(name) is not what opens the file [\(identifier)]", answer != opensWith(identifier), true)
}
check("the handlers of one role are the legacy function's", LSWrappers.UTIs.copyAllHandlers("com.adobe.pdf", inRoles: .editor, asPath: false), LSLegacyRoles.copyAllHandlerIDs("com.adobe.pdf", .editor))

// MARK: - Per-role handlers (the legacy functions, looked up with dlsym)

section("per-role handlers")
check("the three role functions are available on this system", LSLegacyRoles.isAvailable, true)
let htmlHandler = LSLegacyRoles.copyDefaultHandlerID("public.html", .all)
check("public.html has a default handler", htmlHandler?.contains("."), true)
check("Safari is among the handlers of public.html", LSLegacyRoles.copyAllHandlerIDs("public.html", .all)?.contains("com.apple.Safari"), true)
check("an unknown UTI has no default handler", LSLegacyRoles.copyDefaultHandlerID("no.such.uti", .all), nil)
check("an unknown UTI has no handlers", LSWrappers.UTIs.copyAllHandlers("no.such.uti", inRoles: .all), nil)
check("the wrapper answers with the bundle identifier on request", LSWrappers.UTIs.copyDefaultHandler("public.html", inRoles: .all, asPath: false), htmlHandler)
check("the wrapper answers with a path by default", LSWrappers.UTIs.copyDefaultHandler("public.html", inRoles: .all)?.hasSuffix(".app"), true)
// With SWDA_NO_LEGACY_ROLES set the lookups fail, as they would on a system that removed the functions.
// The write below is the one real call in this file. It names a UTI and an application that do not exist, which is no protection
// (the function records both), so it is guarded twice: by this switch, and by SWDA_READ_ONLY, which makes it refuse.
setenv("SWDA_NO_LEGACY_ROLES", "1", 1)
check("the functions are unavailable when switched off", LSLegacyRoles.isAvailable, false)
check("no default handler when switched off", LSLegacyRoles.copyDefaultHandlerID("public.html", .all), nil)
check("no handlers when switched off", LSLegacyRoles.copyAllHandlerIDs("public.html", .all), nil)
check("the wrapper finds no default handler when switched off", LSWrappers.UTIs.copyDefaultHandler("public.html", inRoles: .viewer), nil)
check("the wrapper finds no handlers when switched off", LSWrappers.UTIs.copyAllHandlers("public.html", inRoles: .viewer), nil)
check("a request for All roles does not need the functions", LSWrappers.UTIs.copyDefaultHandler("public.html"), NSWorkspace.shared.urlForApplication(toOpen: htmlType)?.path)
check("a list for All roles does not need them either", LSWrappers.UTIs.copyAllHandlers("public.html")?.isEmpty, false)
check("writing reports an incompatible system when switched off", LSLegacyRoles.setDefaultHandler("no.such.uti", .all, bundleID: "org.nonexistent.app"), E.incompatibleSys.rawValue) // real call, guarded
unsetenv("SWDA_NO_LEGACY_ROLES")
check("the functions are available again once the switch is off", LSLegacyRoles.isAvailable, true)

// MARK: - Helpers in commonFuncs.swift

section("helpers")
check("convertAppURLsToPaths", convertAppURLsToPaths([URL(fileURLWithPath: "/A.app"), URL(fileURLWithPath: "/B/C.app")]), ["/A.app", "/B/C.app"])
check("convertAppURLsToPaths(nil)", convertAppURLsToPaths(nil), nil)
check("copyStringArrayAsString", copyStringArrayAsString(["a", "b"]), "a\nb")
check("copyStringArrayAsString with a separator", copyStringArrayAsString(["a", "b"], separator: ", "), "a, b")
check("copyStringArrayAsString(nil)", copyStringArrayAsString(nil), nil)
for (scheme, valid) in [("http", true), ("x-apple.systempreferences", true), ("a", true), ("web+app", true), ("HTTP", true),
                        ("http\n", false), ("http\u{0301}", false), ("", false), ("1bad", false), ("bad scheme", false), ("-x", false), ("sch\u{00E9}me", false), ("ht:tp", false)] {
    check("isValidScheme(\(scheme.debugDescription))", isValidScheme(scheme), valid)
}
check("displayable leaves ordinary text alone", displayable("Visual Studio Code.app \u{1F469}\u{200D}\u{1F4BB} caf\u{00E9}"), "Visual Studio Code.app \u{1F469}\u{200D}\u{1F4BB} caf\u{00E9}")
check("displayable writes an escape sequence out", displayable("a\u{1B}[2Jb"), "a\\u{1B}[2Jb")
check("displayable writes a carriage return, a newline and a tab out", displayable("a\rb\nc\td"), "a\\u{D}b\\u{A}c\\u{9}d")
check("displayable writes a bidirectional override out", displayable("gnp.\u{202E}exe"), "gnp.\\u{202E}exe")
check("displayable writes a line separator and a zero-width space out", displayable("a\u{2028}b\u{200B}c"), "a\\u{2028}b\\u{200B}c")
check("the list formatters use it", copyStringArrayAsString(["a\u{1B}b", "c"]), "a\\u{1B}b\nc")
check("the dictionary formatter uses it", copyDictionaryAsString([(key: "k\u{1B}", value: "v\r")]), "k\\u{1B}\t\t\t\tv\\u{D}\n")
check("role names", ["viewer", "EDITOR", "Shell", "all", "bogus", ""].map { LSLegacyRoles.mask(named: $0)?.rawValue },
      [LSRolesMask.viewer.rawValue, LSRolesMask.editor.rawValue, LSRolesMask.shell.rawValue, LSRolesMask.all.rawValue, nil, nil])
check("a program without a bundle identifier is the CLI", areWeCLI(), true)
check("the checks run read-only", LSWrappers.isReadOnly, true)
// The checks of the read-only switch must be harmless even if the switch were broken, so they ask for what cannot be written:
// an application that is not there for the two calls of NSWorkspace, and the lookup switched off for the per-role one.
let nowhere = URL(fileURLWithPath: "/nonexistent/Foo.app")
check("the system's setter refuses to write a UTI when read-only", outcome { done in LSWrappers.HandlerSetter.system.forUTI(nowhere, UTType("public.xbitmap-image")!) { done($0.map { .failure(E($0)) } ?? .success(())) } }, [E.permissionDenied.rawValue])
check("... a scheme", outcome { done in LSWrappers.HandlerSetter.system.forScheme(nowhere, "nosuchscheme") { done($0.map { .failure(E($0)) } ?? .success(())) } }, [E.permissionDenied.rawValue])
setenv("SWDA_NO_LEGACY_ROLES", "1", 1)
check("... some roles", LSWrappers.HandlerSetter.system.forRoles("public.xbitmap-image", .viewer, "org.nonexistent.app"), E.permissionDenied.rawValue)
unsetenv("SWDA_NO_LEGACY_ROLES")

finish()
