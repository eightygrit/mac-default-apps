// Checks of the shared sources that need no GUI and change nothing in Launch Services.
// Build and run with Tests/logic/run.sh. Add a check next to the behavior it pins, and change an expected
// value only together with the code change that makes it change on purpose.
import AppKit
import UniformTypeIdentifiers

var checks = 0
var failures = 0
let verbose = ProcessInfo.processInfo.environment["VERBOSE"] == "1"

func check<T: Equatable>(_ name: String, _ actual: T, _ expected: T) {
    checks += 1
    if actual == expected {
        if verbose { print("ok    \(name)") }
    } else {
        failures += 1
        print("FAIL  \(name)\n        expected: \(expected)\n        actual:   \(actual)")
    }
}
func section(_ title: String) { if verbose { print("\n-- \(title)") } }

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
check("resolve [com.apple.textedit] keeps the spelling it was given", resolve("com.apple.textedit").bundleID, "com.apple.textedit")
check("Do Nothing is selected by None", DoNothingApp.isNamed("None"), true)
check("Do Nothing is selected by its bundle identifier", DoNothingApp.isNamed(DoNothingApp.bundleID), true)
check("Do Nothing is not selected by another spelling", DoNothingApp.isNamed("none"), false)
check("Do Nothing is not selected by nothing", DoNothingApp.isNamed(nil), false)

section("finding applications by name")
check("a name finds the application", LSWrappers.copyAppPath(named: "TextEdit")?.hasSuffix("/TextEdit.app"), true)
check("the name is case-insensitive and .app is optional", LSWrappers.copyAppPath(named: "textedit.APP"), LSWrappers.copyAppPath(named: "TextEdit"))
check("a path is returned unchanged", LSWrappers.copyAppPath(named: "/some/where/Foo.app"), "/some/where/Foo.app")
check("a home-relative path is returned unchanged", LSWrappers.copyAppPath(named: "~/Applications/Foo"), "~/Applications/Foo")
check("an unknown name finds nothing", LSWrappers.copyAppPath(named: "NoSuchAppAnywhere"), nil)
check("a registered bundle identifier is installed", LSWrappers.isAppInstalled(withBundleID: "com.apple.TextEdit"), true)
check("an unknown bundle identifier is not installed", LSWrappers.isAppInstalled(withBundleID: "org.nonexistent.app"), false)

// MARK: - Setters: requests that must be refused before anything is written

section("setters refuse before writing")
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
check("scheme with a space", refusal { LSWrappers.Schemes.setDefaultHandler("bad scheme", missingApp, completion: $0) }, .invalidScheme)
check("scheme starting with a digit", refusal { LSWrappers.Schemes.setDefaultHandler("1bad", missingApp, completion: $0) }, .invalidScheme)
check("scheme handler that is not installed", refusal { LSWrappers.Schemes.setDefaultHandler("nosuchscheme", missingApp, completion: $0) }, .appNotFound)
check("UTI handler that is not installed", refusal { LSWrappers.UTIs.setDefaultHandler(harmlessUTI, missingApp, .all, completion: $0) }, .appNotFound)
check("UTI handler that is not installed, for one role", refusal { LSWrappers.UTIs.setDefaultHandler(harmlessUTI, missingApp, .viewer, completion: $0) }, .appNotFound)
check("an application that is not installed is not registered on demand", LSWrappers.ensureRegistered(missingApp), false)
if case .success(let textEdit) = LSWrappers.resolveApp("com.apple.TextEdit") {
    check("a UTI nobody declared, for an installed application", refusal { LSWrappers.UTIs.setDefaultHandler("no.such.uti", textEdit, completion: $0) }, .unknownUTI)
} else {
    check("TextEdit resolves", false, true)
}
check("a UTI nobody declared, for a missing application", refusal { LSWrappers.UTIs.setDefaultHandler("no.such.uti", missingApp, completion: $0) }, .unknownUTI)
check("a UTI nobody declared, for one role and a missing application", refusal { LSWrappers.UTIs.setDefaultHandler("no.such.uti", missingApp, .viewer, completion: $0) }, .unknownUTI)
if case .success(let textEdit) = LSWrappers.resolveApp("com.apple.TextEdit") {
    check("a UTI nobody declared, for one role and an installed application", refusal { LSWrappers.UTIs.setDefaultHandler("no.such.uti", textEdit, .viewer, completion: $0) }, .unknownUTI)
    check("a UTI nobody declared, for viewer and editor", refusal { LSWrappers.UTIs.setDefaultHandler("no.such.uti", textEdit, [.viewer, .editor], completion: $0) }, .unknownUTI)
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
// The write below names a UTI and an application that do not exist, so nothing could change even if the switch failed.
setenv("SWDA_NO_LEGACY_ROLES", "1", 1)
check("the functions are unavailable when switched off", LSLegacyRoles.isAvailable, false)
check("no default handler when switched off", LSLegacyRoles.copyDefaultHandlerID("public.html", .all), nil)
check("no handlers when switched off", LSLegacyRoles.copyAllHandlerIDs("public.html", .all), nil)
check("the wrapper finds no default handler when switched off", LSWrappers.UTIs.copyDefaultHandler("public.html", inRoles: .viewer), nil)
check("the wrapper finds no handlers when switched off", LSWrappers.UTIs.copyAllHandlers("public.html", inRoles: .viewer), nil)
check("a request for All roles does not need the functions", LSWrappers.UTIs.copyDefaultHandler("public.html"), NSWorkspace.shared.urlForApplication(toOpen: htmlType)?.path)
check("a list for All roles does not need them either", LSWrappers.UTIs.copyAllHandlers("public.html")?.isEmpty, false)
check("writing reports an incompatible system when switched off", LSLegacyRoles.setDefaultHandler("no.such.uti", .all, bundleID: "org.nonexistent.app"), E.incompatibleSys.rawValue)
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

print("\(checks - failures) of \(checks) checks passed" + (failures == 0 ? "" : ", \(failures) FAILED"))
exit(failures == 0 ? 0 : 1)
