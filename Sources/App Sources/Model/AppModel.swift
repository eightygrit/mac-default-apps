/*
* ----------------------------------------------------------------------------
* "THE BEER-WARE LICENSE" (Revision 42):
* <g.litenstein@gmail.com> wrote this file. As long as you retain this notice you
* can do whatever you want with this stuff. If we meet some day, and you think
* this stuff is worth it, you can buy me a beer in return., Gregorio Litenstein.
* ----------------------------------------------------------------------------
*/

import AppKit

/** How the File Types list is grouped. */
enum TypeGrouping: String, CaseIterable, Identifiable {
	case none = "None", kind = "Kind", app = "Default App"
	var id: Self { self }
}

/** A titled run of sidebar rows; the title is nil when the list is not grouped, and then the run cannot be collapsed. */
struct EntrySection: Identifiable {
	let id: String
	let title: String?
	/** Where the application is whose icon decorates the header, when grouping by default app. */
	let iconPath: String?
	let entries: [Entry]
}

/** How a change of a default ended. */
enum ChangeOutcome: Equatable {
	/** The handler is the one that was asked for. */
	case applied
	/** The user said no to the confirmation macOS asked for, or it was dismissed. */
	case canceled
	/** macOS or this program refused; the alert says why. */
	case failed
	/** macOS reported success and the handler is not the one that was asked for; the alert says so. */
	case notApplied
	/** A change of the same scheme or type was already waiting, so nothing was asked. */
	case ignored
}

/** UI state of the app: the loaded lists, the search query and the selection of each category. */
@MainActor
final class AppModel: ObservableObject {
	@Published var category: Category = .internet {
		didSet { load(category); refresh() }
	}
	@Published var query = "" {
		didSet { refresh() }
	}
	@Published var typeGrouping: TypeGrouping = .none {
		didSet { refresh() }
	}
	/** What the alert says could not be done, and `errorMessage` why. It goes back to `defaultErrorTitle` when the alert is dismissed. */
	@Published var errorTitle = AppModel.defaultErrorTitle
	@Published var errorMessage: String?
	static let defaultErrorTitle = "Couldn't Change the Default Application"
	/** Current list, filtered, ranked and grouped. */
	@Published private(set) var sections: [EntrySection] = []
	/** Bumped whenever `sections` or the collapsed groups change, so the list view knows to reload. */
	@Published private(set) var listVersion = 0
	/** `sections` flattened, in display order. */
	@Published private(set) var visibleEntries: [Entry] = []
	@Published private var selections: [Category: Entry.ID] = [:]

	/** Schemes and types with a change awaiting macOS, or the user's answer to its confirmation. */
	@Published private(set) var changing: Set<Content> = []
	/** The last reading of the candidates and the default of each scheme and type shown, per role. */
	@Published private(set) var handlers: [Content: [Role: HandlerState]] = [:]

	private var entries: [Category: [Entry]] = [:]
	private var loading: Set<Category> = []
	/** Default handler of every UTI, for grouping File Types by application. */
	private var typeHandlers: [String: String] = [:]
	private var apps: [String: AppRef] = [:]
	private var collapsed: Set<String> = []
	/** How often the handlers of each scheme and type were changed, so that a reading that began before a change is not kept. */
	private var generations: [Content: Int] = [:]
	private let access: Catalog.HandlerAccess

	init(access: Catalog.HandlerAccess = .system) {
		self.access = access
	}

	var isLoading: Bool { entries[category] == nil }

	/** Always a visible entry (or nil when nothing is visible); kept valid by `refresh()`. */
	var selection: Entry.ID? {
		get { selections[category] }
		set { if let newValue { selections[category] = newValue } }
	}

	var selectedEntry: Entry? {
		visibleEntries.first { $0.id == selection }
	}

	private func refresh() {
		let all = entries[category] ?? []
		let q = query.trimmingCharacters(in: .whitespaces)
		let ranked = q.isEmpty ? all : all.enumerated()
			.compactMap { item in item.element.rank(for: q).map { (rank: $0, index: item.offset, entry: item.element) } }
			.sorted { ($0.rank, $0.index) < ($1.rank, $1.index) }
			.map(\.entry)
		sections = group(ranked)
		visibleEntries = sections.filter { !isCollapsed($0) }.flatMap(\.entries)
		listVersion += 1
		if !visibleEntries.contains(where: { $0.id == selections[category] }) {
			selections[category] = visibleEntries.first?.id
		}
	}

	private func group(_ entries: [Entry]) -> [EntrySection] {
		guard category == .types, typeGrouping != .none else {
			return [EntrySection(id: "", title: nil, iconPath: nil, entries: entries)]
		}
		switch typeGrouping {
		case .none:
			return []
		case .kind:
			let groups = Dictionary(grouping: entries) { $0.kindGroup ?? "Other" }
			return Catalog.kindOrder.compactMap { kind in
				groups[kind].map { EntrySection(id: kind, title: kind, iconPath: nil, entries: $0) }
			}
		case .app:
			let groups = Dictionary(grouping: entries) { typeHandlers[$0.id]?.lowercased() ?? "" }
			let sections = groups.map { key, entries -> EntrySection in
				if key.isEmpty { return EntrySection(id: key, title: "No Default Application", iconPath: nil, entries: entries) }
				if key == DoNothingApp.bundleID.lowercased() {
					return EntrySection(id: key, title: DoNothingApp.displayName, iconPath: DoNothingApp.copyURL()?.path, entries: entries)
				}
				// The key is lowercased so that spellings of one identifier group together; the title keeps the spelling the system gave.
				let title = apps[key]?.name ?? entries.lazy.compactMap { self.typeHandlers[$0.id] }.first ?? key
				return EntrySection(id: key, title: title, iconPath: apps[key]?.path, entries: entries)
			}
			// Apps alphabetically, types without a default last.
			return sections.sorted { a, b in
				if a.id.isEmpty != b.id.isEmpty { return b.id.isEmpty }
				return a.title!.localizedStandardCompare(b.title!) == .orderedAscending
			}
		}
	}

	/** Records the confirmed default of a UTI so grouping by app stays accurate. */
	func defaultChanged(forType identifier: String, to bundleID: String?) {
		guard entries[.types] != nil, typeHandlers[identifier]?.lowercased() != bundleID?.lowercased() else { return }
		typeHandlers[identifier] = bundleID
		if let bundleID, apps[bundleID.lowercased()] == nil { apps[bundleID.lowercased()] = AppRef(bundleID: bundleID) }
		if category == .types && typeGrouping == .app { refresh() }
	}

	/** A list that is not grouped has no header to click, so it is never collapsed, whatever was collapsed in a grouped one. */
	func isCollapsed(_ section: EntrySection) -> Bool {
		section.title != nil && collapsed.contains(collapseKey(section.id))
	}

	/** Collapses or expands a group; with `all`, every group follows the one toggled. */
	func toggle(_ sectionID: String, all: Bool = false) {
		let titled = sections.filter { $0.title != nil }.map(\.id)
		guard titled.contains(sectionID) else { return }
		let collapse = !collapsed.contains(collapseKey(sectionID))
		for key in (all ? titled : [sectionID]).map(collapseKey) {
			if collapse { collapsed.insert(key) } else { collapsed.remove(key) }
		}
		refresh()
	}

	private func collapseKey(_ sectionID: String) -> String { "\(typeGrouping.rawValue):\(sectionID)" }

	func load(_ category: Category, force: Bool = false) {
		guard force || (entries[category] == nil && !loading.contains(category)) else { return }
		loading.insert(category)
		Task.detached(priority: .userInitiated) {
			let result = Catalog.load(category)
			let handlers = category == .types ? Catalog.defaultHandlers(forTypes: (result ?? []).map(\.id)) : [:]
			let apps = Dictionary(Set(handlers.values.map { $0.lowercased() }).compactMap { id in AppRef(bundleID: id).map { (id, $0) } },
								  uniquingKeysWith: { a, _ in a })
			await self.finishLoad(category, result, handlers: handlers, apps: apps)
		}
	}

	/** Takes in a finished list. Internal so that a test can supply one. */
	func finishLoad(_ category: Category, _ result: [Entry]?, handlers: [String: String], apps: [String: AppRef]) {
		if category == .types {
			typeHandlers = handlers
			self.apps = apps
		}
		entries[category] = result ?? []
		loading.remove(category)
		if result == nil {
			errorTitle = "Couldn't Load \(category.rawValue)"
			errorMessage = "The list of \(category.rawValue) is not available on this version of macOS."
		}
		if category == self.category { refresh() }
	}

	/** Moves the selection within the visible list; used by arrow keys in the search field. */
	func moveSelection(by offset: Int) {
		guard !visibleEntries.isEmpty else { return }
		let current = visibleEntries.firstIndex { $0.id == selection } ?? 0
		selection = visibleEntries[min(max(current + offset, 0), visibleEntries.count - 1)].id
	}

	// MARK: Handlers

	/** What was last read for a scheme or type in a role; nil until it has been read. */
	func handlerState(for content: Content, role: Role = .all) -> HandlerState? {
		handlers[content]?[role]
	}

	/** Whether a change of a scheme or type is waiting. Another cannot be asked for it until the first has ended. */
	func isChanging(_ content: Content) -> Bool {
		changing.contains(content)
	}

	/** Reads a scheme or type again, unless it was changed while the reading was under way. */
	func refresh(_ content: Content, roles: [Role]) async {
		let generation = generations[content, default: 0]
		let fresh = await access.read(content, roles)
		guard generations[content, default: 0] == generation else { return }
		store(fresh, for: content)
	}

	/** Takes in readings made elsewhere, such as the whole list of an application's claims. */
	func store(_ fresh: [Content: [Role: HandlerState]]) {
		for (content, states) in fresh { store(states, for: content) }
	}

	private func store(_ states: [Role: HandlerState], for content: Content) {
		handlers[content, default: [:]].merge(states) { _, new in new }
		if !content.isScheme, let all = states[.all] { defaultChanged(forType: content.id, to: all.current) }
	}

	/**
	Changes the default of a scheme or type, waits until it has taken effect, and reads it again. This is the one place a change is
	made, so the same rules hold wherever it is asked for: a scheme or type waits for one change at a time, and the answer to a
	confirmation or a failure is told the same way.
	- Parameters:
	  - roles: The roles to read again afterward: "All Roles" changes them all, and a canceled confirmation changes none.
	*/
	@discardableResult
	func change(_ content: Content, to choice: Catalog.HandlerChoice, role: Role = .all, rereading roles: [Role] = [.all]) async -> ChangeOutcome {
		guard !changing.contains(content) else { return .ignored }
		changing.insert(content)
		defer { changing.remove(content) }
		generations[content, default: 0] += 1

		var outcome = ChangeOutcome.applied
		var prompted = false
		switch await access.set(choice, content, role) {
		case .success:
			// A single role is changed by a function that does not wait for macOS, or for the user, and a read can trail even
			// a change macOS has reported: give the new handler a moment to show up before saying that it did not.
			prompted = await access.settle(content, role, choice.bundleID)
		case .failure(.canceled):
			outcome = .canceled
		case .failure(let error):
			errorMessage = error.print(argument: (app: choice.bundleID, content: content.id))
			outcome = .failed
		}
		let fresh = await access.read(content, Array(Set(roles + [role])))
		generations[content, default: 0] += 1
		store(fresh, for: content)
		if outcome == .applied, fresh[role]?.isCurrent(choice.bundleID) != true {
			// After a confirmation the handler that stayed is the answer "no"; without one, macOS said yes and did not do it.
			if prompted { outcome = .canceled } else {
				errorMessage = "Launch Services did not apply the change for \(content.id)."
				outcome = .notApplied
			}
		}
		return outcome
	}

	/**
	Registers a custom URL scheme, handled by the bundled "do nothing" app until the user picks a real one. A scheme the list already
	has is selected instead, and keeps its handler: this is not a way to change that, and "mailto" is a scheme like any other.
	*/
	func addScheme(_ text: String) async {
		let scheme = text.trimmingCharacters(in: .whitespaces).lowercased()
		guard !scheme.isEmpty, let known = entries[.schemes] else { return }
		guard isValidScheme(scheme) else {
			errorMessage = LSWrappers.LSErrors.invalidScheme.print(argument: (app: DoNothingApp.bundleID, content: scheme))
			return
		}
		if let existing = known.first(where: { $0.id.lowercased() == scheme }) {
			query = ""
			selections[.schemes] = existing.id
			refresh()
			return
		}
		guard await change(Content(isScheme: true, id: scheme), to: .init(bundleID: DoNothingApp.bundleID)) == .applied else { return }
		query = ""
		selections[.schemes] = scheme
		load(.schemes, force: true)
	}
}
