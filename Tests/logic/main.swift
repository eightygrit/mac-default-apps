// Checks of the shared sources that need no GUI and change nothing in Launch Services.
// Build and run with Tests/logic/run.sh. Add a check next to the behavior it pins, and change an expected
// value only together with the code change that makes it change on purpose.
import AppKit

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
    (262, .invalidFileURL), (0, .noError),
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
check("message: noError", E.noError.print(argument: (app: "Foo", content: nil)),
      "SwiftDefaultApps SUCCESS: Default handler has succesfully changed to Foo")

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
// "None" selects the dummy application, which has to exist somewhere for the answer to be a success.
if DoNothingApp.copyURL() != nil {
    check("resolve [None] finds the dummy application", resolve("None").bundleID, DoNothingApp.bundleID)
} else {
    check("resolve [None] without a copy of the dummy application", resolve("None").status, E.appNotFound.rawValue)
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
// Every request below names an application that does not exist, so nothing can be written even if a check is skipped.
let missingApp = LSWrappers.ResolvedApp(url: URL(fileURLWithPath: "/nonexistent/Foo.app"), bundleID: "org.nonexistent.app")
check("scheme with a space", LSWrappers.Schemes.setDefaultHandler("bad scheme", missingApp), E.invalidScheme.rawValue)
check("scheme starting with a digit", LSWrappers.Schemes.setDefaultHandler("1bad", missingApp), E.invalidScheme.rawValue)
check("scheme handler that is not installed", LSWrappers.Schemes.setDefaultHandler("nosuchscheme", missingApp), kLSApplicationNotFoundErr)
check("UTI handler that is not installed", LSWrappers.UTIs.setDefaultHandler("public.html", missingApp, .all), kLSApplicationNotFoundErr)
check("an application that is not installed is not registered on demand", LSWrappers.ensureRegistered(missingApp), false)

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

// MARK: - Helpers in commonFuncs.swift

section("helpers")
check("convertAppURLsToPaths", convertAppURLsToPaths([URL(fileURLWithPath: "/A.app"), URL(fileURLWithPath: "/B/C.app")]), ["/A.app", "/B/C.app"])
check("convertAppURLsToPaths(nil)", convertAppURLsToPaths(nil), nil)
check("copyStringArrayAsString", copyStringArrayAsString(["a", "b"]), "a\nb")
check("copyStringArrayAsString with a separator", copyStringArrayAsString(["a", "b"], separator: ", "), "a, b")
check("copyStringArrayAsString(nil)", copyStringArrayAsString(nil), nil)
check("regex operator matches", "http" =~ /"\\Ahttp$", true)
check("regex operator does not match", "ftp" =~ /"\\Ahttp$", false)
check("a program without a bundle identifier is the CLI", areWeCLI(), true)

print("\(checks - failures) of \(checks) checks passed" + (failures == 0 ? "" : ", \(failures) FAILED"))
exit(failures == 0 ? 0 : 1)
