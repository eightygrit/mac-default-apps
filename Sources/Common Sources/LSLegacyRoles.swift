import CoreServices

/**
The only file that names the three functions which read and write the handler of a single role.

A role (Viewer, Editor or Shell) says how an application deals with a type. Apple's replacements for the deprecated
Launch Services calls, `NSWorkspace.urlForApplication(toOpen:)` and its relatives, know no role: they answer for
whatever opens the file. These three functions are the only way left to ask for, or to change, one role alone.
`LSInfo.h` marks them `API_TO_BE_DEPRECATED`, which the compiler does not report yet.

They are looked up at run time, for the reason given in `LSPrivate`: a function that a later macOS removed would stop the
process before `main` if it were linked, and a failed lookup is only `nil`. Check `isAvailable` before offering a role.
Setting the environment variable `SWDA_NO_LEGACY_ROLES=1` makes every lookup fail, which shows today what happens then.

The day Apple removes these functions, delete this file and the per-role choices in the app and on the command line.
*/
enum LSLegacyRoles {
	// The roles travel as the raw value of `LSRolesMask`, an `OptionBits`, which is 32 bits wide.
	private typealias CopyDefaultHandler = @convention(c) (CFString, UInt32) -> Unmanaged<CFString>?
	private typealias CopyAllHandlers = @convention(c) (CFString, UInt32) -> Unmanaged<CFArray>?
	private typealias SetDefaultHandler = @convention(c) (CFString, UInt32, CFString) -> OSStatus

	private static var isDisabled: Bool {
		guard let value = getenv("SWDA_NO_LEGACY_ROLES") else { return false }
		return String(cString: value) == "1"
	}

	private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
		return isDisabled ? nil : LSPrivate.symbol(name, as: type)
	}

	/**
	The roles a name on the command line stands for.
	- Parameter name: "Viewer", "Editor", "Shell" or "All", in any case.
	- Returns: The matching mask, or nil for any other word.
	*/
	static func mask(named name: String) -> LSRolesMask? {
		switch name.lowercased() {
		case "viewer": return .viewer
		case "editor": return .editor
		case "shell": return .shell
		case "all": return .all
		default: return nil
		}
	}

	/**
	Whether a request is for All roles (`Role.all` in the app, `--role All` on the command line), which asks what opens the file
	whatever the role. `NSWorkspace` answers that. Only a mask narrower than that, such as Viewer alone, needs the three functions below.
	- Parameter roles: The roles a request is about.
	- Returns: `true` for `.all` and for any mask that covers Viewer, Editor and Shell.
	*/
	static func isAllRoles(_ roles: LSRolesMask) -> Bool {
		return roles == .all || roles.isSuperset(of: [.viewer, .editor, .shell])
	}

	/// What to say when a role is asked for and `isAvailable` is false.
	static let unavailableMessage = "Per-role defaults are not available on this version of macOS."

	/**
	Whether the system still has all three functions. When it does not, only the handler for all roles can be read or changed.
	*/
	static var isAvailable: Bool {
		return symbol("LSCopyDefaultRoleHandlerForContentType", as: CopyDefaultHandler.self) != nil
			&& symbol("LSCopyAllRoleHandlersForContentType", as: CopyAllHandlers.self) != nil
			&& symbol("LSSetDefaultRoleHandlerForContentType", as: SetDefaultHandler.self) != nil
	}

	/**
	Copies the bundle identifier of the application that is the default handler of a UTI in the given roles.
	- Parameter uti: A Uniform Type Identifier.
	- Parameter roles: The roles to ask about.
	- Returns: A bundle identifier, or nil if there is no handler or the system no longer has the function.
	*/
	static func copyDefaultHandlerID(_ uti: String, _ roles: LSRolesMask) -> String? {
		guard let function = symbol("LSCopyDefaultRoleHandlerForContentType", as: CopyDefaultHandler.self) else { return nil }
		return function(uti as CFString, roles.rawValue)?.takeRetainedValue() as String?
	}

	/**
	Copies the bundle identifiers of every application that handles a UTI in the given roles.
	- Parameter uti: A Uniform Type Identifier.
	- Parameter roles: The roles to ask about.
	- Returns: Bundle identifiers, which can repeat; nil if there are none or the system no longer has the function.
	*/
	static func copyAllHandlerIDs(_ uti: String, _ roles: LSRolesMask) -> [String]? {
		guard let function = symbol("LSCopyAllRoleHandlersForContentType", as: CopyAllHandlers.self) else { return nil }
		return function(uti as CFString, roles.rawValue)?.takeRetainedValue() as? [String]
	}

	/**
	Makes an application the default handler of a UTI in the given roles.
	- Parameter uti: A Uniform Type Identifier.
	- Parameter roles: The roles to change.
	- Parameter bundleID: The bundle identifier of an application Launch Services knows.
	- Returns: `0` on success, a Launch Services error otherwise; `LSErrors.incompatibleSys` if the system no longer has the function.
	*/
	static func setDefaultHandler(_ uti: String, _ roles: LSRolesMask, bundleID: String) -> OSStatus {
		guard let function = symbol("LSSetDefaultRoleHandlerForContentType", as: SetDefaultHandler.self) else { return LSWrappers.LSErrors.incompatibleSys.rawValue }
		// The function accepts a UTI nobody declared and an application nobody installed, and records them: only this switch stops it.
		guard !LSWrappers.isReadOnly else { return LSWrappers.LSErrors.permissionDenied.rawValue }
		return function(uti as CFString, roles.rawValue, bundleID as CFString)
	}
}
