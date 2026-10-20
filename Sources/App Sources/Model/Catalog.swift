/*
* ----------------------------------------------------------------------------
* "THE BEER-WARE LICENSE" (Revision 42):
* The people who wrote this file are named in its history in version control.
* As long as you retain this notice you can do whatever you want with this
* stuff. If we meet some day, and you think this stuff is worth it, you can
* buy one of us a beer in return.
* ----------------------------------------------------------------------------
*/

import AppKit
import UniformTypeIdentifiers

/** The four lists the app can browse. */
enum Category: String, CaseIterable, Identifiable {
	case internet = "Internet"
	case schemes = "URL Schemes"
	case types = "File Types"
	case apps = "Applications"
	var id: Self { self }
}

/** Launch Services handler roles. `all` is what Finder's "Change All…" uses. */
enum Role: String, CaseIterable, Identifiable {
	case all = "All Roles", viewer = "Viewer", editor = "Editor", shell = "Shell"
	var id: Self { self }

	var mask: LSRolesMask {
		switch self {
		case .all: return .all
		case .viewer: return .viewer
		case .editor: return .editor
		case .shell: return .shell
		}
	}
}

/** A URI Scheme or a UTI: what a default handler is for. */
struct Content: Hashable, Sendable {
	let isScheme: Bool
	/** The scheme, or the UTI. */
	let id: String
}

/** Content and applications an application declares it can open. */
struct AppDeclarations: Hashable {
	let path: String
	let version: String?
	let schemes: [String]
	let types: [String]
}

/** One row of the sidebar: a URL scheme, a UTI or an application. */
struct Entry: Identifiable, Hashable {
	enum Kind: Hashable {
		case scheme
		case type
		case app(AppDeclarations)
	}
	/** Scheme, UTI or bundle identifier. */
	let id: String
	let kind: Kind
	let title: String
	let subtitle: String
	/** File extensions of a UTI, lowercased and without the leading dot. */
	var extensions: [String] = []
	/** Broad kind of a UTI ("Images", "Source Code"…), used for grouping. */
	var kindGroup: String? = nil

	var isApp: Bool { if case .app = kind { return true } else { return false } }

	/** Search rank, lower is better; nil when the entry does not match. */
	func rank(for query: String) -> Int? {
		let q = query.lowercased()
		let ext = q.hasPrefix(".") ? String(q.dropFirst()) : q
		let id = self.id.lowercased(), title = self.title.lowercased()
		if extensions.contains(ext) || id == q || title == q { return 0 }
		if id.hasPrefix(q) || title.hasPrefix(q) || extensions.contains(where: { $0.hasPrefix(ext) }) { return 1 }
		if id.contains(q) || title.contains(q) || subtitle.lowercased().contains(q) { return 2 }
		return nil
	}
}

/** An application that can act as a handler. */
struct AppRef: Identifiable, Hashable {
	let id: String
	let name: String
	let path: String?

	init?(bundleID: String) {
		guard bundleID.caseInsensitiveCompare(DoNothingApp.bundleID) != .orderedSame else { return nil }
		guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
		self.id = bundleID
		self.path = url.path
		self.name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
	}
}

/** Applications that can open a scheme or UTI, and the bundle ID of the current default. */
struct HandlerState {
	let candidates: [AppRef]
	let current: String?

	func isCurrent(_ bundleID: String) -> Bool { current?.caseInsensitiveCompare(bundleID) == .orderedSame }
}

/**
One scheme or UTI an application declares. What currently opens it is the model's to say (`AppModel.handlerState`).
*/
struct Claim: Identifiable, Sendable {
	let content: Content
	let title: String
	let subtitle: String

	var id: String { (content.isScheme ? "scheme:" : "type:") + content.id }
}

/**
Remembers the applications looked up during one pass over a list. The same few applications turn up in every row (26 applications for
1,045 rows of one application's claims), and each lookup asks Launch Services and the file system. It lives as long as the pass:
an application installed or removed afterwards is found by the next one.
*/
final class AppRefMemo: @unchecked Sendable {
	private let lock = NSLock()
	private var found: [String: AppRef?] = [:]

	func appRef(bundleID: String) -> AppRef? {
		let key = bundleID.lowercased()
		lock.lock()
		if let known = found[key] { lock.unlock(); return known }
		lock.unlock()
		let made = AppRef(bundleID: bundleID)
		lock.lock(); found[key] = .some(made); lock.unlock()
		return made
	}
}

/**
Builds the sidebar lists from Launch Services, and changes defaults. The reads are synchronous and meant to run off the main thread,
except those that use `UTType`: the first time one is used off the main thread it costs about a millisecond, and a few microseconds on
it, which makes the 2,685 types the system knows 3 s there and 85 ms here. Those are marked, and are called from the main thread.
`setDefault` is `async`.
*/
enum Catalog {
	private static let internetSchemes: [(String, String)] = [
		("http", "Web Browser"), ("mailto", "E-Mail"), ("news", "News"),
		("rss", "RSS"), ("ftp", "FTP"), ("im", "Instant Messaging"),
	]

	/** The entries of a category, or nil when this version of macOS does not provide the list. File Types: call it on the main thread. */
	static func load(_ category: Category) -> [Entry]? {
		switch category {
		case .internet:
			return internetSchemes.map { Entry(id: $0.0, kind: .scheme, title: $0.1, subtitle: "\($0.0):") }
		case .schemes:
			guard let schemes = LSWrappers.Schemes.copySchemesAndHandlers()?.keys else { return nil }
			return concurrentMap(schemes.filter { $0 != "*" }) { scheme in
				Entry(id: scheme, kind: .scheme, title: scheme, subtitle: LSWrappers.Schemes.copyNameForScheme(scheme) ?? "")
			}.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
		case .types:
			return declaredTypes().map(entries(for:))
		case .apps:
			guard let paths = LSWrappers.copyAllApps() else { return nil }
			let apps = concurrentMap(paths) { path -> Entry? in
				guard let bundle = Bundle(path: path), let bundleID = bundle.bundleIdentifier,
					  bundleID.caseInsensitiveCompare(DoNothingApp.bundleID) != .orderedSame,
					  let declared = LSWrappers.copySchemesAndUTIsForApp(path) else { return nil }
				let schemes = declared["URIs"]?.values.reduce(into: Set<String>()) { $0.formUnion($1) } ?? []
				let types = declared["UTIs"]?.values.reduce(into: Set<String>()) { $0.formUnion($1) } ?? []
				guard !schemes.isEmpty || !types.isEmpty else { return nil }
				let info = bundle.infoDictionary ?? [:]
				let name = [info["CFBundleDisplayName"], info["CFBundleName"]].compactMap { $0 as? String }.first { !$0.isEmpty }
					?? FileManager.default.displayName(atPath: path)
				let version = (info["CFBundleShortVersionString"] ?? info["CFBundleVersion"]) as? String
				let declarations = AppDeclarations(path: path, version: version, schemes: schemes.sorted(), types: types.sorted())
				return Entry(id: bundleID, kind: .app(declarations), title: name, subtitle: bundleID)
			}.compactMap { $0 }
			return preferredCopies(of: apps).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
		}
	}

	/** A type as an application declares it: the identifier it wrote, which the lists show and the defaults are keyed by, and what the system makes of it. */
	struct DeclaredType: Sendable {
		let identifier: String
		let type: UTType
	}

	/** The types any application declares, that the system knows. Call it on the main thread. */
	static func declaredTypes() -> [DeclaredType]? {
		LSPrivate.copyDeclaredTypeIdentifiers().map { identifiers in
			identifiers.compactMap { identifier in UTType(identifier).map { DeclaredType(identifier: identifier, type: $0) } }
		}
	}

	/** The File Types entries for the types that are files or content, sorted by description. Call it on the main thread. */
	static func entries(for declared: [DeclaredType]) -> [Entry] {
		declared.compactMap { item -> Entry? in
			let type = item.type, identifier = item.identifier
			guard type.conforms(to: .item) || type.conforms(to: .content) else { return nil }
			let extensions = (type.tags[.filenameExtension] ?? []).map { $0.lowercased() }
			let description = type.localizedDescription ?? identifier
			let subtitle = extensions.isEmpty ? identifier : "\(identifier) · " + extensions.map { ".\($0)" }.joined(separator: " ")
			return Entry(id: identifier, kind: .type, title: description, subtitle: subtitle, extensions: extensions, kindGroup: kindGroup(of: type))
		}.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
	}

	/**
	Keeps one entry per application: the copy Launch Services resolves its bundle identifier to, which is the copy that "Make Default"
	assigns, and not whichever copy it happens to list first (an updater's staging copy, say). Where it resolves to none of the
	listed copies, the first one stays.
	*/
	static func preferredCopies(of apps: [Entry], resolve: (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }) -> [Entry] {
		func path(_ entry: Entry) -> String? { if case .app(let declarations) = entry.kind { return declarations.path } else { return nil } }
		func same(_ a: String, _ b: String) -> Bool { URL(fileURLWithPath: a).resolvingSymlinksInPath().path == URL(fileURLWithPath: b).resolvingSymlinksInPath().path }
		var order: [String] = []
		var copies: [String: [Entry]] = [:]
		for app in apps {
			let key = app.id.lowercased()
			if copies[key] == nil { order.append(key) }
			copies[key, default: []].append(app)
		}
		return order.compactMap { key in
			let listed = copies[key]!
			guard listed.count > 1, let resolved = resolve(listed[0].id)?.path else { return listed[0] }
			return listed.first { path($0).map { same($0, resolved) } ?? false } ?? listed[0]
		}
	}

	/** Candidate handlers and the current default for a scheme or UTI in a given role. */
	static func handlers(for content: Content, role: Role = .all, memo: AppRefMemo = AppRefMemo()) -> HandlerState {
		let ids: [String]
		let current: String?
		if content.isScheme {
			ids = LSWrappers.Schemes.copyAllHandlers(content.id, asPath: false) ?? []
			current = LSWrappers.Schemes.copyDefaultHandler(content.id, asPath: false)
		} else {
			ids = LSWrappers.UTIs.copyAllHandlers(content.id, inRoles: role.mask, asPath: false) ?? []
			current = defaultHandler(forType: content.id, role: role)
		}
		var seen = Set<String>()
		let candidates = (ids + [current].compactMap { $0 })
			.filter { seen.insert($0.lowercased()).inserted }
			.compactMap(memo.appRef(bundleID:))
			.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
		return HandlerState(candidates: candidates, current: current)
	}

	static func defaultHandler(forType identifier: String, role: Role = .all) -> String? {
		LSWrappers.UTIs.copyDefaultHandler(identifier, inRoles: role.mask, asPath: false)
	}

	/** Default handler of each UTI, keyed by UTI; UTIs without one are omitted. */
	static func defaultHandlers(forTypes identifiers: [String]) -> [String: String] {
		Dictionary(identifiers.compactMap { id in defaultHandler(forType: id).map { (id, $0) } }, uniquingKeysWith: { a, _ in a })
	}

	/** The applications that are the given bundle identifiers, keyed by the identifier in lowercase. */
	static func appRefs(for bundleIDs: some Sequence<String>) -> [String: AppRef] {
		let memo = AppRefMemo()
		return Dictionary(bundleIDs.compactMap { id in memo.appRef(bundleID: id).map { (id.lowercased(), $0) } }, uniquingKeysWith: { a, _ in a })
	}

	/**
	The File Types rows of the identifiers an application declares, sorted by description. A type the system does not know cannot be
	made anyone's default, so it is not offered. Call it on the main thread.
	*/
	static func typeClaims(for identifiers: [String]) -> [Claim] {
		identifiers.compactMap { identifier -> Claim? in
			guard let type = UTType(identifier) else { return nil }
			let extensions = (type.tags[.filenameExtension] ?? []).map { ".\($0)" }.joined(separator: " ")
			return Claim(content: Content(isScheme: false, id: identifier), title: type.localizedDescription ?? identifier,
						 subtitle: extensions.isEmpty ? identifier : "\(identifier) · \(extensions)")
		}.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
	}

	/** What an application declares it can open, as rows with the current handlers: its schemes, then the `typeClaims` it was given. */
	static func claims(schemes: [String], types: [Claim]) -> (claims: [Claim], handlers: [Content: [Role: HandlerState]]) {
		let memo = AppRefMemo()
		var handlers: [Content: [Role: HandlerState]] = [:]
		let schemeClaims = schemes.map { scheme in
			Claim(content: Content(isScheme: true, id: scheme), title: "\(scheme):", subtitle: LSWrappers.Schemes.copyNameForScheme(scheme) ?? "")
		}
		for claim in schemeClaims + types { handlers[claim.content] = [.all: self.handlers(for: claim.content, memo: memo)] }
		return (schemeClaims + types, handlers)
	}

	/** Broad kinds, most specific first: a UTI lands in the first kind it conforms to. */
	private static let kinds: [(String, [UTType])] = [
		("Source Code", [.sourceCode, .script, .shellScript]),
		("Images", [.image]),
		("Audio", [.audio]),
		("Video", [.movie, .audiovisualContent]),
		("Spreadsheets", [.spreadsheet]),
		("Presentations", [.presentation]),
		("Documents", [.pdf, .rtf, .rtfd, .compositeContent]),
		("Data", [.json, .xml, .yaml, .propertyList, .database, .commaSeparatedText, .tabSeparatedText]),
		("Text", [.text]),
		("Archives", [.archive]),
		("Fonts", [.font]),
		("3D & Models", [.threeDContent]),
		("Disk Images", [.diskImage]),
		("Apps & Bundles", [.application, .executable, .bundle, .package]),
	]

	static func kindGroup(of type: UTType) -> String {
		kinds.first { $0.1.contains { type.conforms(to: $0) } }?.0 ?? "Other"
	}

	/** Order of kind groups in the sidebar. */
	static let kindOrder: [String] = kinds.map(\.0) + ["Other"]

	/** An application the user picked as a handler: one the menu names by bundle identifier, or one chosen from disk with "Other…". */
	struct HandlerChoice: Sendable {
		let bundleID: String
		/** Where the application is, when the user chose a file. Nil when only the bundle identifier is known. */
		var url: URL? = nil
	}

	/**
	Sets the default handler and waits for macOS to say it is done, which can mean waiting for the user to answer a
	confirmation. Canceling it arrives as `.canceled`. A change of one role alone is made by a function that answers at once,
	so `settledDefault` is what waits for that.
	*/
	static func setDefault(_ choice: HandlerChoice, for content: Content, role: Role = .all) async -> Result<Void, LSWrappers.LSErrors> {
		let app: LSWrappers.ResolvedApp
		// A file the user picked is that file, not whichever copy Launch Services ranks first for its bundle identifier.
		switch LSWrappers.resolveApp(choice.url?.path ?? choice.bundleID) {
		case .failure(let error): return .failure(error)
		case .success(let resolved): app = resolved
		}
		// `awaitCompletion` blocks its thread, so it gets one of its own rather than one of the cooperative pool's.
		return await withCheckedContinuation { continuation in
			DispatchQueue.global(qos: .userInitiated).async {
				continuation.resume(returning: LSWrappers.awaitCompletion { completion in
					// The system can ask the user to confirm, so the request is made from the main thread, where the app's windows are.
					DispatchQueue.main.async {
						if content.isScheme { LSWrappers.Schemes.setDefaultHandler(content.id, app, completion: completion) }
						else { LSWrappers.UTIs.setDefaultHandler(content.id, app, role.mask, completion: completion) }
					}
				})
			}
		}
	}

	/**
	Waits until a default change has really taken effect. The per-role functions return before macOS has applied the change,
	and give no way to find out when it has, or whether the user canceled a confirmation. `setDefault` does wait for a change
	of all roles, but a read can still trail it by a moment. Either way this returns at once when the handler is already the target.
	- Returns: Whether macOS asked the user to confirm. If it did, a handler that is not the target means the user said no.
	*/
	static func settledDefault(for content: Content, role: Role = .all, target: String) async -> Bool {
		func current() -> String? {
			content.isScheme ? LSWrappers.Schemes.copyDefaultHandler(content.id, asPath: false) : defaultHandler(forType: content.id, role: role)
		}
		let start = Date()
		var sawPrompt = false
		while true {
			let value = current()
			if value?.caseInsensitiveCompare(target) == .orderedSame { return sawPrompt }
			let prompting = isConfirmationPromptVisible()
			if prompting { sawPrompt = true }
			let elapsed = Date().timeIntervalSince(start)
			if sawPrompt && !prompting {
				// The prompt was answered; give Launch Services a moment to apply an approval.
				try? await Task.sleep(nanoseconds: 500_000_000)
				return true
			}
			if (!sawPrompt && elapsed > 3) || elapsed > 300 { return sawPrompt }
			try? await Task.sleep(nanoseconds: 200_000_000)
		}
	}

	/**
	What the model asks of the system to change a default and to see the result, and to read the defaults of the types. The system's own is the only one the app uses;
	a test passes one of its own, so that the model's rules (what is refused, what is shown while a change waits, what is said
	when it did not take effect) can be checked without writing a default.
	*/
	struct HandlerAccess: Sendable {
		/// Changes the default and waits for macOS; see `setDefault`.
		var set: @Sendable (HandlerChoice, Content, Role) async -> Result<Void, LSWrappers.LSErrors>
		/// Waits until the target shows as the handler; says whether macOS asked the user to confirm; see `settledDefault`.
		var settle: @Sendable (Content, Role, _ target: String) async -> Bool
		/// Reads the candidates and the current default of a scheme or UTI in each of the roles.
		var read: @Sendable (Content, [Role]) async -> [Role: HandlerState]
		/// Reads the default of each of the given types, keyed by type, and the applications they name, keyed by lowercased bundle identifier.
		var readAll: @Sendable ([String]) async -> (defaults: [String: String], apps: [String: AppRef])

		static var system: HandlerAccess {
			HandlerAccess(
				set: { await Catalog.setDefault($0, for: $1, role: $2) },
				settle: { await Catalog.settledDefault(for: $0, role: $1, target: $2) },
				read: { content, roles in
					await Task.detached(priority: .userInitiated) {
						Dictionary(roles.map { ($0, Catalog.handlers(for: content, role: $0)) }, uniquingKeysWith: { first, _ in first })
					}.value
				},
				readAll: { identifiers in
					await Task.detached(priority: .userInitiated) {
						let defaults = Catalog.defaultHandlers(forTypes: identifiers)
						return (defaults: defaults, apps: Catalog.appRefs(for: Set(defaults.values.map { $0.lowercased() })))
					}.value
				})
		}
	}

	/** Whether CoreServicesUIAgent is showing a "change default application" confirmation. */
	private static func isConfirmationPromptVisible() -> Bool {
		let agents = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.coreservices.uiagent").map(\.processIdentifier))
		guard !agents.isEmpty,
			  let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
		else { return false }
		return windows.contains { ($0[kCGWindowOwnerPID as String] as? pid_t).map(agents.contains) ?? false }
	}

	static func concurrentMap<T, U>(_ input: [T], _ transform: (T) -> U) -> [U] {
		guard !input.isEmpty else { return [] }
		var output = [U?](repeating: nil, count: input.count)
		output.withUnsafeMutableBufferPointer { buffer in
			let base = buffer.baseAddress!
			DispatchQueue.concurrentPerform(iterations: input.count) { base[$0] = transform(input[$0]) }
		}
		return output.map { $0! }
	}
}
