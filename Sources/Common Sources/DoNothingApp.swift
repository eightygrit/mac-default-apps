import AppKit

/**
The bundled application that does nothing. Assigning it as the handler of a URI Scheme or a UTI makes that
scheme or type open nowhere. This is the one place that spells its names: the bundle identifier, the file name,
"Do Nothing" in the app and "None" on the command line.
*/
enum DoNothingApp {
	static let bundleID = "cl.fail.lordkamina.ThisAppDoesNothing"
	static let fileName = "ThisAppDoesNothing.app"
	/** What the app calls it. */
	static let displayName = "Do Nothing"
	/** What the command line calls it: `--app None`. */
	static let cliName = "None"

	/**
	Whether a name, as typed on the command line or passed along by the app, selects this application.
	- Parameter name: A bundle identifier, a display name, a path or "None".
	*/
	static func isNamed(_ name: String?) -> Bool {
		return name == cliName || name == bundleID
	}

	/**
	Finds a copy to hand out. This is a query: it registers and launches nothing.
	- Returns: The copy Launch Services already knows, if it is still on disk; otherwise the copy next to the CLI, inside the app or in an Applications folder; nil if there is none.
	*/
	static func copyURL() -> URL? {
		if let registered = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID), FileManager.default.fileExists(atPath: registered.path) {
			return registered
		}
		let home: URL? = areWeCLI() ? Bundle.main.bundleURL : Bundle.main.resourceURL
		let searchPaths = [home].compactMap { $0 } + FileManager.default.urls(for: .applicationDirectory, in: .allDomainsMask)
		return searchPaths.map { $0.appendingPathComponent(fileName).absoluteURL }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
	}
}
