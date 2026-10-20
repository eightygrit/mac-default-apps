/*
* ----------------------------------------------------------------------------
* "THE BEER-WARE LICENSE" (Revision 42):
* The people who wrote this file are named in its history in version control.
* As long as you retain this notice you can do whatever you want with this
* stuff. If we meet some day, and you think this stuff is worth it, you can
* buy one of us a beer in return.
* ----------------------------------------------------------------------------
*/

import SwiftUI
import UniformTypeIdentifiers

/** Shows the detail of the selected entry; each entry gets fresh state through `.id`. */
@MainActor
struct DetailView: View {
	@EnvironmentObject private var model: AppModel

	var body: some View {
		if let entry = model.selectedEntry {
			Group {
				if case .app(let declarations) = entry.kind {
					AppDetail(entry: entry, declarations: declarations)
				} else {
					ContentDetail(entry: entry)
				}
			}
			.id(entry.id)
		} else {
			Text(model.isLoading ? "" : "No Selection")
				.foregroundStyle(.secondary)
		}
	}
}

// MARK: - Scheme / UTI

/** Default-application pickers for a URL scheme or a UTI. */
@MainActor
private struct ContentDetail: View {
	let entry: Entry
	@EnvironmentObject private var model: AppModel

	private var isScheme: Bool { entry.kind == .scheme }
	private var content: Content { Content(isScheme: isScheme, id: entry.id) }
	/** Roles that can be told apart: only "All Roles" when the system no longer has the per-role functions. */
	private var roles: [Role] { isScheme || !LSLegacyRoles.isAvailable ? [.all] : Role.allCases }
	private var footer: String {
		if isScheme { return "Links using \(entry.id): open in this application." }
		let all = "Applies to every role, like “Change All…” in Finder’s Get Info."
		return LSLegacyRoles.isAvailable ? all : "\(all) \(LSLegacyRoles.unavailableMessage)"
	}

	var body: some View {
		Form {
			Section {
				DetailHeader(entry: entry)
			}
			Section {
				picker(for: .all, label: "Open With")
			} footer: {
				Text(footer)
			}
			if roles.count > 1 {
				Section("Per-Role Defaults") {
					ForEach([Role.viewer, .editor, .shell]) { picker(for: $0, label: $0.rawValue) }
				}
			}
		}
		.formStyle(.grouped)
		.task { await model.refresh(content, roles: roles) }
	}

	@ViewBuilder
	private func picker(for role: Role, label: String) -> some View {
		if model.isChanging(content) {
			LabeledContent(label) { WaitingLabel() }
		} else if let state = model.handlerState(for: content, role: role) {
			HandlerPicker(label: label, state: state) { choice in
				Task { await model.change(content, to: choice, role: role, rereading: roles) }
			}
		} else {
			LabeledContent(label) { ProgressView().controlSize(.small) }
		}
	}
}

/** A menu of candidate handlers plus "Do Nothing" and "Other…". */
@MainActor
private struct HandlerPicker: View {
	let label: String
	let state: HandlerState
	let onChoose: (Catalog.HandlerChoice) -> Void

	private static let otherTag = "\u{0}other"

	private var currentTag: String {
		guard let current = state.current else { return "" }
		guard !state.isCurrent(DoNothingApp.bundleID) else { return DoNothingApp.bundleID }
		return state.candidates.first { $0.id.caseInsensitiveCompare(current) == .orderedSame }?.id ?? ""
	}

	var body: some View {
		Picker(label, selection: Binding(get: { currentTag }, set: { select($0) })) {
			if currentTag.isEmpty {
				Text("None").tag("")
			}
			ForEach(state.candidates) { app in
				Label { Text(app.name) } icon: { Image(nsImage: Icons.app(app.path, size: 16)) }
					.tag(app.id)
			}
			Divider()
			Text(DoNothingApp.displayName).tag(DoNothingApp.bundleID)
			Text("Other…").tag(Self.otherTag)
		}
	}

	private func select(_ tag: String) {
		guard tag != currentTag, !tag.isEmpty else { return }
		if tag == Self.otherTag {
			let panel = NSOpenPanel()
			panel.allowedContentTypes = [.application]
			panel.directoryURL = URL(fileURLWithPath: "/Applications")
			panel.prompt = "Choose"
			guard panel.runModal() == .OK, let url = panel.url else { return }
			guard let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
			onChoose(.init(bundleID: bundleID, url: url))
		} else {
			onChoose(.init(bundleID: tag))
		}
	}
}

// MARK: - Application

/** Everything an application declares, with one-click "Make Default". */
@MainActor
private struct AppDetail: View {
	let entry: Entry
	let declarations: AppDeclarations
	@EnvironmentObject private var model: AppModel
	@State private var claims: [Claim]?

	var body: some View {
		Form {
			Section {
				DetailHeader(entry: entry)
				LabeledContent("Location") {
					HStack(spacing: 4) {
						Text(declarations.path)
							.lineLimit(1)
							.truncationMode(.middle)
							.textSelection(.enabled)
						Button {
							NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: declarations.path)])
						} label: { Image(systemName: "magnifyingglass.circle.fill") }
							.buttonStyle(.borderless)
							.help("Reveal in Finder")
					}
				}
			}
			if let claims {
				claimSection("URL Schemes", claims.filter(\.content.isScheme))
				claimSection("File Types", claims.filter { !$0.content.isScheme })
			} else {
				Section { ProgressView().frame(maxWidth: .infinity) }
			}
		}
		.formStyle(.grouped)
		.task {
			let schemes = declarations.schemes, types = Catalog.typeClaims(for: declarations.types)
			let loaded = await Task.detached(priority: .userInitiated) { Catalog.claims(schemes: schemes, types: types) }.value
			model.store(loaded.handlers)
			claims = loaded.claims
		}
	}

	private func isDefault(_ claim: Claim) -> Bool {
		model.handlerState(for: claim.content)?.isCurrent(entry.id) == true
	}

	@ViewBuilder
	private func claimSection(_ title: String, _ items: [Claim]) -> some View {
		if !items.isEmpty {
			Section("\(title) (\(items.filter(isDefault).count) of \(items.count) default)") {
				ForEach(items) { claim in
					ClaimRow(claim: claim, appID: entry.id, handlers: model.handlerState(for: claim.content),
							 isDefault: isDefault(claim), isPending: model.isChanging(claim.content)) { choice in
						Task { await model.change(claim.content, to: choice) }
					}
				}
			}
		}
	}
}

/**
A declared scheme or UTI. Launch Services cannot clear a default, only replace it, so a row this app
already owns offers a menu to hand it to another application; other rows offer "Make Default".
*/
@MainActor
private struct ClaimRow: View {
	let claim: Claim
	let appID: String
	/** What is read of the scheme or type so far; nil until it is. */
	let handlers: HandlerState?
	let isDefault: Bool
	let isPending: Bool
	let onChoose: (Catalog.HandlerChoice) -> Void

	private var currentName: String? {
		guard let handlers, let current = handlers.current else { return nil }
		if handlers.isCurrent(DoNothingApp.bundleID) { return DoNothingApp.displayName }
		return handlers.candidates.first { $0.id.caseInsensitiveCompare(current) == .orderedSame }?.name ?? current
	}

	var body: some View {
		HStack(spacing: 8) {
			Image(systemName: isDefault ? "checkmark.circle.fill" : "circle")
				.foregroundStyle(isDefault ? Color.green : Color.secondary.opacity(0.5))
				.help(isDefault ? "This application is the default" : "Another application is the default")
			VStack(alignment: .leading, spacing: 1) {
				Text(claim.title).lineLimit(1)
				Text(claim.subtitle)
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(1)
					.truncationMode(.middle)
					.textSelection(.enabled)
				if !isDefault {
					Text(currentName.map { "Opens with \($0)" } ?? "No default application")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}
			Spacer(minLength: 8)
			if isPending {
				WaitingLabel()
			} else if isDefault, let handlers {
				HandlerPicker(label: "Default Application", state: handlers, onChoose: onChoose)
					.labelsHidden()
					.fixedSize()
					.help("Choose another application")
			} else {
				Button("Make Default") { onChoose(.init(bundleID: appID)) }
					.controlSize(.small)
			}
		}
	}
}

// MARK: - Shared

/** Shown while a change waits for Launch Services, or for the user to answer its confirmation prompt. */
@MainActor
private struct WaitingLabel: View {
	var body: some View {
		HStack(spacing: 6) {
			ProgressView().controlSize(.small)
			Text("Waiting for confirmation…").foregroundStyle(.secondary)
		}
	}
}

@MainActor
private struct DetailHeader: View {
	let entry: Entry

	private var lines: [String] {
		switch entry.kind {
		case .scheme:
			return [entry.title == entry.id ? "" : entry.title, entry.subtitle].filter { !$0.isEmpty && $0 != "\(entry.id):" }
		case .type:
			return [entry.id, entry.extensions.map { ".\($0)" }.joined(separator: "  ")].filter { !$0.isEmpty }
		case .app(let declarations):
			return [entry.id, declarations.version.map { "Version \($0)" } ?? ""].filter { !$0.isEmpty }
		}
	}

	var body: some View {
		HStack(spacing: 12) {
			EntryIcon(entry: entry, size: 48)
			VStack(alignment: .leading, spacing: 2) {
				Text(entry.kind == .scheme ? "\(entry.id):" : entry.title)
					.font(.title2.weight(.semibold))
					.lineLimit(2)
				ForEach(lines, id: \.self) {
					Text($0).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
				}
			}
			.textSelection(.enabled)
		}
		.padding(.vertical, 4)
	}
}

@MainActor
struct EntryIcon: View {
	let entry: Entry
	let size: CGFloat

	var body: some View {
		switch entry.kind {
		case .scheme:
			Image(systemName: "link.circle.fill")
				.resizable()
				.foregroundStyle(.blue)
				.frame(width: size * 0.85, height: size * 0.85)
				.frame(width: size, height: size)
		case .type:
			Image(nsImage: Icons.type(entry.id, size: size))
		case .app(let declarations):
			Image(nsImage: Icons.app(declarations.path, size: size))
		}
	}
}

/** Icon lookups are not free and the lists are long, so results are cached per path/UTI and size. */
@MainActor
enum Icons {
	private static let cache = NSCache<NSString, NSImage>()

	static func app(_ path: String?, size: CGFloat) -> NSImage {
		cached("app:\(path ?? "")@\(size)", size: size) {
			path.map { NSWorkspace.shared.icon(forFile: $0) } ?? NSWorkspace.shared.icon(for: .application)
		}
	}

	static func type(_ identifier: String, size: CGFloat) -> NSImage {
		cached("uti:\(identifier)@\(size)", size: size) {
			NSWorkspace.shared.icon(for: UTType(identifier) ?? .data)
		}
	}

	private static func cached(_ key: String, size: CGFloat, make: () -> NSImage) -> NSImage {
		if let image = cache.object(forKey: key as NSString) { return image }
		let image = make().copy() as! NSImage
		image.size = NSSize(width: size, height: size)
		cache.setObject(image, forKey: key as NSString)
		return image
	}
}
