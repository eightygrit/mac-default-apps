// Checks of the app's model that need no window and write nothing: grouping and collapsing, the custom-scheme field, and the one
// place a default is changed. Build and run with Tests/model/run.sh.
import AppKit

// MARK: - A stand-in for what the system is asked

/// Records what the model asks for and answers as told. `heldSet` makes the first `set` wait until its gate is opened, and
/// `heldRead` the first read.
final class Spy: @unchecked Sendable {
    var sets: [String] = []
    var settles: [String] = []
    var reads: [String] = []
    var setResult: Result<Void, LSWrappers.LSErrors> = .success(())
    var prompted = false
    /// What a read answers, per read; the last one stays.
    var current: [String?] = []
    var heldSet: Gate?
    var heldRead: Gate?
    private var readCount = 0

    func access() -> Catalog.HandlerAccess {
        Catalog.HandlerAccess(
            set: { [self] choice, content, role in
                let index = sets.count
                sets.append("\(content.isScheme ? "scheme" : "type") \(content.id) \(role.rawValue) \(choice.bundleID) \(choice.url?.path ?? "-")")
                if index == 0, let gate = heldSet { await gate.wait() }
                return setResult
            },
            settle: { [self] content, role, target in
                settles.append("\(content.id) \(role.rawValue) \(target)")
                return prompted
            },
            read: { [self] content, roles in
                let index = readCount
                readCount += 1
                reads.append("\(content.id) \(roles.map(\.rawValue).sorted().joined(separator: ","))")
                if index == 0, let gate = heldRead { await gate.wait() }
                let value = current.isEmpty ? nil : current[min(index, current.count - 1)]
                return Dictionary(roles.map { ($0, HandlerState(candidates: [], current: value)) }, uniquingKeysWith: { a, _ in a })
            })
    }
}

actor Gate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func open() { isOpen = true; continuation?.resume(); continuation = nil }
}

func entry(_ id: String, kind: Entry.Kind = .type, group: String? = nil) -> Entry {
    Entry(id: id, kind: kind, title: id, subtitle: id, extensions: [], kindGroup: group)
}

let textEdit = "com.apple.TextEdit"
let mailto = Content(isScheme: true, id: "mailto")
let html = Content(isScheme: false, id: "public.html")

// MARK: - Grouping and collapsing

section("collapsing")
let grouped = AppModel(access: Spy().access())
let types = [entry("public.a"), entry("public.b"), entry("public.c")]
grouped.finishLoad(.types, types, handlers: ["public.a": textEdit], apps: [textEdit.lowercased(): AppRef(bundleID: textEdit)!])
grouped.finishLoad(.internet, [entry("http", kind: .scheme), entry("mailto", kind: .scheme)], handlers: [:], apps: [:])
grouped.category = .types
grouped.typeGrouping = .app
check("grouped by default app: two groups", grouped.sections.map(\.title), ["TextEdit", "No Default Application"].map { Optional($0) })
grouped.toggle("")
check("the group without a default is collapsed", grouped.visibleEntries.map(\.id), ["public.a"])
check("... and says so", grouped.sections.map { grouped.isCollapsed($0) }, [false, true])
grouped.category = .internet
check("the other tabs are not hidden by it", grouped.visibleEntries.map(\.id), ["http", "mailto"])
check("... and keep a selection", grouped.selection, "http")
grouped.toggle("", all: true)
check("an ungrouped list cannot be collapsed", grouped.visibleEntries.map(\.id), ["http", "mailto"])
grouped.category = .types
check("what was collapsed stays collapsed where it was", grouped.visibleEntries.map(\.id), ["public.a"])
grouped.toggle("", all: true)
check("Option-click on a collapsed group expands every group", grouped.visibleEntries.map(\.id), ["public.a", "public.b", "public.c"])
grouped.toggle("", all: true)
check("... and on an expanded one collapses every group", grouped.visibleEntries.map(\.id), [])

section("group titles")
let titled = AppModel(access: Spy().access())
titled.finishLoad(.types, [entry("public.a"), entry("public.b"), entry("public.c")], handlers: [
    "public.a": DoNothingApp.bundleID, "public.b": "Org.Example.Not-Installed", "public.c": "org.example.not-installed",
], apps: [:])
titled.category = .types
titled.typeGrouping = .app
check("Do Nothing is titled by its name, not its identifier", titled.sections.contains { $0.title == DoNothingApp.displayName }, true)
check("an application that is not installed keeps the spelling the system gave", titled.sections.map(\.title).contains("Org.Example.Not-Installed"), true)
check("... and spellings of one identifier are one group", titled.sections.count, 2)
check("no title is a lowercased identifier", titled.sections.compactMap(\.title).contains(DoNothingApp.bundleID.lowercased()), false)

// MARK: - Search

section("selection after a search")
let searching = AppModel(access: Spy().access())
searching.finishLoad(.internet, [entry("http", kind: .scheme), entry("mailto", kind: .scheme)], handlers: [:], apps: [:])
searching.query = "mail"
check("a query filters the list", searching.visibleEntries.map(\.id), ["mailto"])
searching.query = ""
check("an empty query shows everything again", searching.visibleEntries.map(\.id), ["http", "mailto"])

// MARK: - The custom-scheme field

section("addScheme")
let spy = Spy()
let schemes = AppModel(access: spy.access())
schemes.finishLoad(.schemes, [entry("http", kind: .scheme), entry("mailto", kind: .scheme)], handlers: [:], apps: [:])
schemes.category = .schemes
schemes.query = "zzz"
await schemes.addScheme(" MAILTO ")
check("a scheme that exists is not given to Do Nothing", spy.sets, [])
check("... it is selected instead", schemes.selection, "mailto")
check("... and made visible", schemes.query, "")
await schemes.addScheme("bad scheme")
check("a malformed scheme is refused", spy.sets, [])
check("... with a message", schemes.errorMessage?.contains("is not a valid URI Scheme") ?? false, true)
schemes.errorMessage = nil
let unloaded = AppModel(access: spy.access())
await unloaded.addScheme("web+test")
check("nothing is added before the list is loaded", spy.sets, [])
spy.current = [DoNothingApp.bundleID]
await schemes.addScheme("  Web+Test ")
check("a new scheme goes to Do Nothing, in lowercase", spy.sets, ["scheme web+test All Roles \(DoNothingApp.bundleID) -"])
check("... is selected", schemes.selection, "web+test")
check("... without a message", schemes.errorMessage, nil)

// MARK: - Changing a default

section("change")
@MainActor func fresh(_ spy: Spy) -> AppModel { AppModel(access: spy.access()) }

let applied = Spy(); applied.current = [textEdit]
let a = fresh(applied)
check("a change that takes effect", await a.change(html, to: .init(bundleID: textEdit)), .applied)
check("... asked for once, with the application and the role", applied.sets, ["type public.html All Roles \(textEdit) -"])
check("... and waited for", applied.settles, ["public.html All Roles \(textEdit)"])
check("... then read again", applied.reads, ["public.html All Roles"])
check("... the reading is kept", a.handlerState(for: html)?.current, textEdit)
check("... nothing is waiting afterwards", a.isChanging(html), false)
check("... and nothing is said", a.errorMessage, nil)

let chosen = Spy(); chosen.current = [textEdit]
let c = fresh(chosen)
let file = URL(fileURLWithPath: "/Applications/Chosen.app")
_ = await c.change(mailto, to: .init(bundleID: textEdit, url: file))
check("a file the user chose is passed on as that file", chosen.sets, ["scheme mailto All Roles \(textEdit) /Applications/Chosen.app"])

let oneRole = Spy(); oneRole.current = [textEdit]
let r = fresh(oneRole)
_ = await r.change(html, to: .init(bundleID: textEdit), role: .viewer, rereading: Role.allCases)
check("one role is changed as that role", oneRole.sets, ["type public.html Viewer \(textEdit) -"])
check("... every role asked for is read again", oneRole.reads, ["public.html All Roles,Editor,Shell,Viewer"])
let narrow = Spy(); narrow.current = [textEdit]
_ = await fresh(narrow).change(html, to: .init(bundleID: textEdit), role: .viewer, rereading: [.all])
check("... and the role changed is read even if it was not asked for", narrow.reads, ["public.html All Roles,Viewer"])

let canceled = Spy(); canceled.setResult = .failure(.canceled); canceled.current = ["org.other"]
let k = fresh(canceled)
check("a canceled change", await k.change(html, to: .init(bundleID: textEdit)), .canceled)
check("... is not worth a message", k.errorMessage, nil)
check("... is not waited for", canceled.settles, [])
check("... but is read again", canceled.reads.count, 1)

let denied = Spy(); denied.setResult = .failure(.permissionDenied); denied.current = ["org.other"]
let d = fresh(denied)
check("a change macOS refuses", await d.change(html, to: .init(bundleID: textEdit)), .failed)
check("... is explained", d.errorMessage, "SwiftDefaultApps ERROR -54: macOS did not allow changing the default handler for public.html.")

let missing = Spy(); missing.current = ["org.other"]
let m = fresh(missing)
check("a change macOS reported and did not make", await m.change(html, to: .init(bundleID: textEdit)), .notApplied)
check("... is said so", m.errorMessage, "Launch Services did not apply the change for public.html.")

let declined = Spy(); declined.prompted = true; declined.current = ["org.other"]
let n = fresh(declined)
check("a confirmation the user declined", await n.change(html, to: .init(bundleID: textEdit)), .canceled)
check("... is not worth a message", n.errorMessage, nil)

let unknown = Spy(); unknown.setResult = .failure(.unknownUTI)
let u = fresh(unknown)
check("a type nobody declared", await u.change(Content(isScheme: false, id: "no.such.uti"), to: .init(bundleID: textEdit)), .failed)
check("... is explained", u.errorMessage, "SwiftDefaultApps ERROR -10815: no.such.uti is not a known UTI.")

section("one change at a time")
let slow = Spy(); slow.current = [textEdit]
let gate = Gate()
slow.heldSet = gate
let s = fresh(slow)
let first = Task { await s.change(html, to: .init(bundleID: textEdit)) }
while !s.isChanging(html) { await Task.yield() }
check("while a change waits the scheme or type is shown as changing", s.isChanging(html), true)
check("... and another one is not", s.isChanging(mailto), false)
check("a second change of it is refused", await s.change(html, to: .init(bundleID: "org.other")), .ignored)
check("... without asking the system", slow.sets.count, 1)
check("another scheme or type can change meanwhile", await s.change(mailto, to: .init(bundleID: textEdit)) == .ignored, false)
await gate.open()
check("the first change ends as it would have", await first.value, .applied)
check("... nothing is waiting afterwards", s.changing.isEmpty, true)
check("... and the next change is allowed", await s.change(html, to: .init(bundleID: textEdit)), .applied)

section("a reading that began before a change")
let race = Spy(); race.current = ["org.old", textEdit]
let readGate = Gate()
race.heldRead = readGate
let rm = fresh(race)
let early = Task { await rm.refresh(html, roles: [.all]) }
while race.reads.isEmpty { await Task.yield() }
check("the change ends while the first reading is out", await rm.change(html, to: .init(bundleID: textEdit)), .applied)
await readGate.open()
await early.value
check("a reading that began before it is not kept", rm.handlerState(for: html)?.current, textEdit)

section("a file chosen with Other…")
// The one real call in this file: the application it names is not there, so correct code ends at "not found" before it comes
// near a write; code that looked the identifier up instead would reach the system's setter, which SWDA_READ_ONLY makes refuse.
let viaFile = await Catalog.setDefault(.init(bundleID: textEdit, url: URL(fileURLWithPath: "/nonexistent/Foo.app")), for: Content(isScheme: false, id: "public.xbitmap-image")) // real call, guarded
check("is looked up as that file, not by its identifier", { () -> OSStatus in if case .failure(let error) = viaFile { return error.rawValue } else { return 0 } }(), LSWrappers.LSErrors.appNotFound.rawValue)

// MARK: - The Applications tab

section("preferred copies")
func app(_ id: String, _ path: String) -> Entry {
    Entry(id: id, kind: .app(AppDeclarations(path: path, version: nil, schemes: [], types: [])), title: id, subtitle: id)
}
let staging = app("com.vivaldi.Vivaldi", "/Users/someone/Library/Caches/com.vivaldi.Vivaldi/Installation/Vivaldi.app")
let installed = app("com.vivaldi.Vivaldi", "/Applications/Vivaldi.app")
let other = app("com.example.Other", "/Applications/Other.app")
func paths(_ entries: [Entry]) -> [String] { entries.compactMap { if case .app(let d) = $0.kind { return d.path } else { return nil } } }
check("the copy that is resolved is kept, not the first listed", paths(Catalog.preferredCopies(of: [staging, other, installed], resolve: { $0 == "com.vivaldi.Vivaldi" ? URL(fileURLWithPath: "/Applications/Vivaldi.app") : nil })),
      ["/Applications/Vivaldi.app", "/Applications/Other.app"])
check("... where it resolves to none of them the first is kept", paths(Catalog.preferredCopies(of: [staging, installed], resolve: { _ in URL(fileURLWithPath: "/elsewhere/Vivaldi.app") })), [staging].compactMap { paths([$0]).first })
check("... and where it resolves to nothing too", paths(Catalog.preferredCopies(of: [staging, installed], resolve: { _ in nil })), paths([staging]))
check("spellings of one identifier are one application", Catalog.preferredCopies(of: [app("Com.Example.A", "/a/A.app"), app("com.example.a", "/b/A.app")], resolve: { _ in nil }).count, 1)
check("an application with one copy is not looked up", Catalog.preferredCopies(of: [other], resolve: { _ in fatalError("looked up") }).count, 1)

check("the model runs read-only", LSWrappers.isReadOnly, true)
finish()
