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

@main
@MainActor
struct SwiftDefaultAppsApp: App {
	@NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
	@StateObject private var model = AppModel()

	var body: some Scene {
		Window("SwiftDefaultApps", id: "main") {
			ContentView()
				.environmentObject(model)
				.frame(minWidth: 760, minHeight: 400)
				.task { model.load(model.category) }
		}
		.defaultSize(width: 900, height: 600)
		.windowResizability(.contentMinSize)
		.commands {
			CommandGroup(replacing: .newItem) {}
		}
	}
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
