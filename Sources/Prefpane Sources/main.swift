/*
 * ----------------------------------------------------------------------------
 * "THE BEER-WARE LICENSE" (Revision 42):
 * <g.litenstein@gmail.com> wrote this file. As long as you retain this notice you
 * can do whatever you want with this stuff. If we meet some day, and you think
 * this stuff is worth it, you can buy me a beer in return., Gregorio Litenstein.
 * ----------------------------------------------------------------------------
 */

import PreferencePanes
import SwiftUI

/**
Main PreferencePane class. The UI is SwiftUI, hosted without a nib.

System Settings runs third-party panes in legacyLoader, which puts `mainView` into its own window sized
exactly to `mainView` and mirrors that window into System Settings. The host never tells the pane how
much room it has, nor that its window was resized, so the pane tracks the System Settings window itself
while it is visible and resizes its window to match. The SwiftUI layout has no fixed heights and simply
fills whatever size it gets.
*/
@MainActor
final class SWDAMainPrefPane: NSPreferencePane {
	private let model = PaneModel()
	private var tracker: Timer?

	/** Width System Settings reserves for legacy panes. */
	private static let paneWidth: CGFloat = 668
	private static let minimumHeight: CGFloat = 400
	/** System Settings title bar/toolbar above the pane area. */
	private static let hostChromeHeight: CGFloat = 52

	override func loadMainView() -> NSView {
		let host = NSHostingView(rootView: PaneView().environmentObject(model))
		host.sizingOptions = []
		host.autoresizingMask = [.width, .height]
		host.frame = NSRect(x: 0, y: 0, width: Self.paneWidth, height: Self.availableHeight() ?? Self.minimumHeight)
		mainView = host
		mainViewDidLoad()
		return host
	}

	override func didSelect() {
		model.load(model.category)
		// No resize notification crosses the process boundary, so poll; a window-list query is cheap.
		tracker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
			MainActor.assumeIsolated { self?.followHostHeight() }
		}
	}

	override func didUnselect() {
		tracker?.invalidate()
		tracker = nil
	}

	/** Resizes the pane window to the System Settings pane area, keeping its top edge in place. */
	private func followHostHeight() {
		guard let window = mainView.window, let height = Self.availableHeight(),
			  abs(window.frame.height - height) >= 1 else { return }
		let frame = window.frame
		window.setFrame(NSRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height), display: true)
	}

	/** Height of the pane area in the frontmost System Settings window, if there is one. */
	private static func availableHeight() -> CGFloat? {
		guard let host = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first,
			  let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
		else { return nil }
		// The list is ordered front to back, so the first regular window of System Settings is the one in use.
		let frame = windows.lazy.compactMap { info -> CGRect? in
			guard info[kCGWindowOwnerPID as String] as? pid_t == host.processIdentifier,
				  info[kCGWindowLayer as String] as? Int == 0,
				  let bounds = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
			return CGRect(dictionaryRepresentation: bounds)
		}.first
		return frame.map { max(minimumHeight, $0.height - hostChromeHeight) }
	}
}
