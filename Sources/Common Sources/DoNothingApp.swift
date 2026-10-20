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
	The folders a copy may be handed out from: the one the program ships it in (inside the app, or next to the command-line tool) and
	`/Applications`. A copy anywhere else, such as one registered by an old build, or one that somebody planted, is not used.
	*/
	private static var homes: [URL] {
		let own: URL? = areWeCLI() ? Bundle.main.bundleURL : Bundle.main.resourceURL
		return [own].compactMap { $0 } + FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask)
	}

	/**
	Whether an application is Do Nothing: the right bundle identifier and package type, a program to run, and a place it may be handed out from.
	- Parameter url: An application bundle.
	*/
	static func isGenuine(_ url: URL) -> Bool {
		guard let bundle = Bundle(url: url), bundle.bundleIdentifier == bundleID,
			  bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL",
			  let executable = bundle.executableURL, FileManager.default.isExecutableFile(atPath: executable.path) else { return false }
		let folder = url.resolvingSymlinksInPath().deletingLastPathComponent().path
		return homes.contains { $0.resolvingSymlinksInPath().path == folder }
	}

	/**
	Finds a copy to hand out. This is a query: it registers and launches nothing.
	- Returns: The genuine copy Launch Services already knows, if it is still on disk; otherwise the one next to the CLI, inside the app or in `/Applications`; nil if there is none.
	*/
	static func copyURL() -> URL? {
		let registered = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID)
		let shipped = homes.map { $0.appendingPathComponent(fileName) }
		return (registered + shipped).first(where: isGenuine)
	}
}
