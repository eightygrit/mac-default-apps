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

/** Root view. Every region stretches with its container. */
@MainActor
struct ContentView: View {
	@EnvironmentObject private var model: AppModel

	var body: some View {
		HStack(spacing: 0) {
			SidebarView()
				.frame(width: 240)
			Divider()
			DetailView()
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.safeAreaInset(edge: .bottom, spacing: 0) {
			if let offer = model.undoOffer { UndoBar(offer: offer) }
		}
		.onChange(of: model.announcement) { announcement in
			if let announcement { Announcer.post(announcement.text) }
		}
		.toolbar {
			ToolbarItem(placement: .principal) {
				Picker("Category", selection: $model.category) {
					ForEach(Category.allCases) { Text($0.rawValue).tag($0) }
				}
				.pickerStyle(.segmented)
				.labelsHidden()
				.fixedSize()
			}
		}
		.alert(model.errorTitle, isPresented: Binding(
			get: { model.errorMessage != nil },
			set: { if !$0 { model.errorMessage = nil; model.errorTitle = AppModel.defaultErrorTitle } }
		)) {
			Button("OK", role: .cancel) {}
		} message: {
			Text(model.errorMessage ?? "")
		}
	}
}

/** What was changed, from what, and the way back. It stays until the next change or until it is dismissed. */
@MainActor
private struct UndoBar: View {
	@EnvironmentObject private var model: AppModel
	let offer: UndoOffer

	var body: some View {
		HStack(spacing: 10) {
			Image(systemName: "arrow.uturn.backward.circle")
				.foregroundStyle(.secondary)
				.accessibilityHidden(true)
			Text(offer.message).lineLimit(2)
			Spacer(minLength: 8)
			Button("Undo") { Task { await model.undo() } }
			Button { model.dismissUndo() } label: { Image(systemName: "xmark") }
				.buttonStyle(.borderless)
				.accessibilityLabel("Dismiss")
				.help("Dismiss")
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 8)
		.background(.bar)
		.overlay(alignment: .top) { Divider() }
	}
}

/** Says something to VoiceOver, which otherwise hears nothing of a change that needed no alert. */
@MainActor
enum Announcer {
	static func post(_ text: String) {
		NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
							 userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
	}
}

/** Search field, the filtered list, and the custom-scheme field on the URL Schemes tab. */
@MainActor
private struct SidebarView: View {
	@EnvironmentObject private var model: AppModel
	@State private var newScheme = ""

	var body: some View {
		VStack(spacing: 8) {
			SearchField(text: $model.query, prompt: "Name, identifier or .ext", onMove: model.moveSelection)
				.padding([.horizontal, .top], 10)

			if model.category == .types {
				Picker("Group By", selection: $model.typeGrouping) {
					ForEach(TypeGrouping.allCases) { Text($0.rawValue).tag($0) }
				}
				.pickerStyle(.segmented)
				.labelsHidden()
				.padding(.horizontal, 10)
				.help("Group file types by kind or by the application that opens them")
			}

			if model.isLoading {
				ProgressView("Loading…")
					.controlSize(.small)
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			} else if model.sections.allSatisfy({ $0.entries.isEmpty }) {
				Text(model.query.isEmpty ? "Nothing Here" : "No Results")
					.foregroundStyle(.secondary)
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			} else {
				EntryList(model: model)
			}

			if model.category == .schemes {
				HStack(spacing: 6) {
					TextField("New scheme", text: $newScheme)
						.textFieldStyle(.roundedBorder)
						.onSubmit { addScheme() }
					Button("Add") { addScheme() }
						.disabled(newScheme.trimmingCharacters(in: .whitespaces).isEmpty)
				}
				.padding([.horizontal, .bottom], 10)
			}
		}
	}

	private func addScheme() {
		let scheme = newScheme
		newScheme = ""
		Task { await model.addScheme(scheme) }
	}
}
