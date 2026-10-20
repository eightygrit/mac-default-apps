/*
* ----------------------------------------------------------------------------
* "THE BEER-WARE LICENSE" (Revision 42):
* <g.litenstein@gmail.com> wrote this file. As long as you retain this notice you
* can do whatever you want with this stuff. If we meet some day, and you think
* this stuff is worth it, you can buy me a beer in return., Gregorio Litenstein.
* ----------------------------------------------------------------------------
*/

import AppKit
import os
import UniformTypeIdentifiers

/**
Functions wrapping varied Launch Services tasks to be re-used throughout the application.
*/
class LSWrappers {
	/** The subsystem the unified log files this program's messages under: filter by it in Console. */
	static let logSubsystem = "cl.fail.lordkamina.SwiftDefaultApps"
	
	/**
	Wrapper for commonly-used errors associated to Launch Services.
	- invalidBundle: The specified bundle does not have a valid CFBundlePackageType entry.
	- invalidScheme: Supplied URI Scheme is malformed or contains invalid characters.
	- incompatibleSys: A valid application bundle was found, but it is not compatible with the current version of macOS.
	- serverErr: Can't communicate with the Launch Services server.
	- appNotFound: Application not found at given path/URL.
	- notAnApp: Found item at given path/URL but it is not an application bundle.
	- deletedApp: An application bundle was found, but it is currently in the Trash.
	- defaultErr: Unknown error, for cases not covered above. 
	- invalidFileURL: Trying to locate a file with a scheme different from file://
	- unknownUTI: The system does not know the Uniform Type Identifier.
	- ambiguousApp: A name matches more than one application and nothing says which was meant; the path of one does.
	- canceled: The user canceled the confirmation macOS asks for before it changes a default handler.
	- permissionDenied: The system, or the sandbox the program runs in, did not allow the change.
	- timedOut: The change was not confirmed in time.
	- noError: No error occured. 
	*/
	internal enum LSErrors:OSStatus, Error {
		case invalidBundle = -67857
		case invalidScheme = -30774
		case incompatibleSys = -10825
		case serverErr = -10822
		case appNotFound = -10814
		case notAnApp = -10811
		case defaultErr = -10810
		case deletedApp = -10660
		case invalidFileURL = 262
		case unknownUTI = -10815
		case canceled = -128
		case permissionDenied = -54
		case timedOut = -1712
		/// Ours, not the system's: it has no code of its own, so this one stays clear of every range the system uses.
		case ambiguousApp = 1001
		
		case noError = 0
		
		init(value: OSStatus) {
			switch value {
			case -67857: self = .invalidBundle
			case -30774: self = .invalidScheme
			case -10825: self = .incompatibleSys
			case -10822: self = .serverErr
			case -10814: self = .appNotFound
			case -10811: self = .notAnApp
			case -10660: self = .deletedApp
			case -10810: self = .defaultErr
			case 262: self = .invalidFileURL
			case -10815: self = .unknownUTI
			case -128: self = .canceled
			case -54: self = .permissionDenied
			case -1712: self = .timedOut
			case 1001: self = .ambiguousApp
				
			case 0: self = .noError
			default: self = .defaultErr
			}
			
		}
		/**
		Maps an error reported by `NSWorkspace` to the closest case. A canceled confirmation arrives as `NSUserCancelledError` or as an
		`NSOSStatusErrorDomain` error, and the reason for a failure can sit a level down, under `NSUnderlyingErrorKey`.
		- Parameter error: Any error. One of ours is returned as it is; one nothing here recognizes becomes `defaultErr`.
		*/
		init(_ error: Error) {
			if let known = error as? LSErrors { self = known; return }
			var next: NSError? = error as NSError
			while let current = next {
				if current.domain == NSCocoaErrorDomain && current.code == NSUserCancelledError { self = .canceled; return }
				if current.domain == NSCocoaErrorDomain && current.code == NSFileWriteNoPermissionError { self = .permissionDenied; return }
				if current.domain == NSPOSIXErrorDomain && (current.code == Int(EPERM) || current.code == Int(EACCES)) { self = .permissionDenied; return }
				if current.domain == NSOSStatusErrorDomain, let known = LSErrors(rawValue: OSStatus(truncatingIfNeeded: current.code)), known != .noError, known != .ambiguousApp { self = known; return }
				next = current.userInfo[NSUnderlyingErrorKey] as? NSError
			}
			self = .defaultErr
		}
		/**
		Print a user-readable error message for each error code.
		
		- Parameter argument:
		app: The application specified by the user, which could conceivably be a URL, a file-path, a bundle identifier or even a display name.
		content: The URI Scheme or UTI the request was about. It is named by the messages for a malformed scheme, an unknown UTI, a canceled change, one macOS did not allow and one that timed out.
		
		- Returns: Human-readable error message specifying the problem, or unknown error if the problem is something not accounted for here.
		*/
		func print(argument: (app: String?, content: String?) = (String(),String())) -> String {
			// What was typed goes back to a terminal: control characters in it are shown as escapes, not sent.
			let raw = argument.app ?? String()
			let app = displayable(raw), content = displayable(argument.content ?? String())
			var retValue = (self == .noError ? "SwiftDefaultApps SUCCESS: " : "SwiftDefaultApps ERROR \(self.rawValue): ")
			switch self {
			case .notAnApp: retValue += "\(app) is not a valid application."
			case .appNotFound: retValue += "No application found for \(app)"
			case .invalidScheme: retValue += "\(content) is not a valid URI Scheme."
			case .invalidFileURL: retValue += "\(app) is not a valid filesystem URL."
			case .deletedApp: retValue += "\(app) cannot be accessed because it is in the Trash."
			case .serverErr: retValue += "There was an error trying to communicate with the Launch Services Server."
			case .incompatibleSys: retValue += "\(app) is not compatible with the currently installed version of macOS."
			case .invalidBundle: retValue += "\(app) is not a valid Package."
			case .unknownUTI: retValue += "\(content) is not a known UTI."
			case .canceled: retValue += "Changing the default handler for \(content) was canceled."
			case .permissionDenied: retValue += "macOS did not allow changing the default handler for \(content)."
			case .timedOut: retValue += "Timed out waiting for the change of the default handler for \(content)."
			case .ambiguousApp:
				let paths = LSWrappers.copyAppPaths(named: raw).map(displayable)
				retValue += "\(app) matches more than one application" + (paths.isEmpty ? "." : ": \(paths.joined(separator: ", ")).") + " Give the path of the one you mean."
			case .noError: retValue += "Default handler has successfully changed to \(app)"
			case .defaultErr: retValue += "An unknown error has occurred."
			}
			if ((self == .appNotFound || self == .deletedApp) && DoNothingApp.isNamed(raw)) { retValue += " (This error occurs when \(DoNothingApp.fileName) is not found.)" }
			return retValue
		}
	}
	/**
	The three calls that change a default handler, gathered in one place so that a test can stand in for them and see which one a
	request reaches, and with what, without writing a default. The setters below take one as a parameter and use the system's
	unless they are given another; nothing else in the program ever changes a default.
	*/
	struct HandlerSetter {
		/// Assigns an application to a UTI for every role, through `NSWorkspace`. Answers when macOS has, which can be when the user has.
		var forUTI: (_ app: URL, _ type: UTType, _ completion: @escaping @Sendable (Error?) -> Void) -> Void
		/// Assigns an application to a URI Scheme, through `NSWorkspace`. Answers when macOS has, which can be when the user has.
		var forScheme: (_ app: URL, _ scheme: String, _ completion: @escaping @Sendable (Error?) -> Void) -> Void
		/// Assigns an application to a UTI for some roles only, through `LSLegacyRoles`. Answers at once, with a status.
		var forRoles: (_ uti: String, _ roles: LSRolesMask, _ bundleID: String) -> OSStatus

		/// The real calls, or `refusing` when `LSWrappers.isReadOnly`.
		static var system: HandlerSetter {
			if LSWrappers.isReadOnly { return .refusing }
			return HandlerSetter(
				forUTI: { NSWorkspace.shared.setDefaultApplication(at: $0, toOpen: $1, completion: $2) },
				forScheme: { NSWorkspace.shared.setDefaultApplication(at: $0, toOpenURLsWithScheme: $1, completion: $2) },
				forRoles: { LSLegacyRoles.setDefaultHandler($0, $1, bundleID: $2) })
		}

		/// Calls that change nothing and fail the way macOS fails when it does not allow a change.
		static var refusing: HandlerSetter {
			let denied = NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))
			return HandlerSetter(
				forUTI: { _, _, done in done(denied) },
				forScheme: { _, _, done in done(denied) },
				forRoles: { _, _, _ in LSErrors.permissionDenied.rawValue })
		}
	}
	/**
	Whether the environment variable `SWDA_READ_ONLY=1` is set. It makes every change of a default handler, and every registration
	of an application, fail as if macOS had not allowed it, whoever asks. The test scripts set it, so that a test, or a program that
	is being broken on purpose, cannot write a default even by accident; a check that must see what a request would do passes a
	`HandlerSetter` of its own instead.
	*/
	static var isReadOnly: Bool {
		guard let value = getenv("SWDA_READ_ONLY") else { return false }
		return String(cString: value) == "1"
	}
	/**
	An application that passed the sanity checks in `resolveApp(_:)`: where it lives and what Launch Services calls it.
	*/
	struct ResolvedApp {
		let url: URL
		let bundleID: String
	}
	/**
	Groups functions dealing with UTIs.
	*/
	class UTIs {
		/**
		Copies a list of file-extensions for a given UTI.
		- Parameter inUTI: A Uniform Type Identifier.
		- Returns: An array of strings corresponding to file-extensions for that UTI, or nil.
		*/
		static func copyExtensionsFor(_ inUTI: String) -> [String]? {
			guard let extensions = UTType(inUTI)?.tags[.filenameExtension], (extensions.isEmpty == false) else { return nil }
			return extensions
		}
		/**
		Copies the preferred UTI for a file extension.
		- Parameter inExtension: A filename extension, with or without a leading dot.
		- Returns: The preferred Uniform Type Identifier for the extension, or nil.
		*/
		static func copyUTIForExtension(_ inExtension: String) -> String? {
			let fileExtension = inExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
			guard (fileExtension.isEmpty == false) else { return nil }
			// Not `UTType(filenameExtension:)`: that conforms to `public.data` by default, which changes the answer for every
			// bundle type (`app`, `action`, ...) and for unknown extensions. Passing no supertype matches the call it replaces.
			return UTType(tag: fileExtension, tagClass: .filenameExtension, conformingTo: nil)?.identifier
		}
		/**
		Copies the bundle identifier of the application currently registered as the default handler for a given UTI.
		- Parameter inUTI: A Uniform Type Identifier.
		- Parameter inRoles: The specified Launch Services Role to query. Can correspond to "Editor", "Viewer", "Shell" or "None". By default, and for any mask that covers viewer, editor and shell, we ask what opens the file whatever the role, which `NSWorkspace` answers. A narrower mask is answered by `LSLegacyRoles`.
		- Returns: The Bundle identifier or POSIX path of an application, or nil if no valid handler was found.
		*/
		static func copyDefaultHandler (_ inUTI:String, inRoles: LSRolesMask = .all, asPath: Bool = true) -> String? {
			if LSLegacyRoles.isAllRoles(inRoles) {
				guard let type = UTType(inUTI), let url = NSWorkspace.shared.urlForApplication(toOpen: type) else { return nil }
				return LSWrappers.copyHandlers(from: [url], asPath: asPath)?.first
			}
			if let handlerID = LSLegacyRoles.copyDefaultHandlerID(inUTI, inRoles) {
				if (asPath == true) {
					if let handlerURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: handlerID) {
						return handlerURL.path
					}
					else { return nil }
				}
				else { return handlerID }
			}
			else { return nil }
		}
		/**
		Creates a list of all currently registered handlers for a given UTI.
		- Parameter inUTI: A Uniform Type Identifier.
		- Parameter inRoles: The specified Launch Services Role to query. Can correspond to "Editor", "Viewer", "Shell" or "None". By default, and for any mask that covers viewer, editor and shell, we ask which applications can open the file whatever the role, which `NSWorkspace` answers, so an application whose role for the type is "None" is not listed. A narrower mask is answered by `LSLegacyRoles`.
		- Returns: An array of strings corresponding to the Bundle identifiers or POSIX paths of all currently registered handlers, or nil of none were found.
		*/
		static func copyAllHandlers (_ inUTI:String, inRoles: LSRolesMask = .all, asPath: Bool = true) -> Array<String>? {
			if LSLegacyRoles.isAllRoles(inRoles) {
				guard let type = UTType(inUTI) else { return nil }
				return LSWrappers.copyHandlers(from: NSWorkspace.shared.urlsForApplications(toOpen: type), asPath: asPath)
			}
			var handlers: Array<String> = []
			if let handlerIDs = LSLegacyRoles.copyAllHandlerIDs(inUTI, inRoles) {
				if (asPath == true) {
					for handlerID in handlerIDs {
						if let handlerURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: handlerID) {
							handlers.append(handlerURL.path)
						}
					}
				}
				else { return handlerIDs }
			}
			else { return nil }
			return (handlers.isEmpty ? nil : handlers)
		}
		/**
		Creates a keyed dictionary of all currently-registered UTIs and their default handler. Excludes abstract entries like references to physical devices and such things we have no use for.
		- Returns: A dictionary with UTIs as keys and bundle identifiers as values, or nil if the system does not provide the list of declared UTIs.
		*/
		static func copyAllUTIs () -> [String:String]? {
			guard let declared = LSPrivate.copyDeclaredTypeIdentifiers() else { return nil }
			let identifiers = declared.filter() { identifier in
				guard let type = UTType(identifier) else { return false }
				return type.conforms(to: .item) || type.conforms(to: .content)
			} // Ignore UTIs belonging to devices and such.
			var handlers:Array<String> = []
			for UTI in identifiers {
				if let handler = UTIs.copyDefaultHandler(UTI) {
					handlers.append(handler)
				}
				else {
					handlers.append("No application set.")
				}
			}
			
			return Dictionary.init (keys: identifiers, values: handlers)
		}
		/**
		Changes the default handler for a given UTI. Asynchronous. For All roles macOS can ask the user to confirm first, and then answers only when the user has; a single role is changed at once.
		- See Also: `enum LSErrors` above.
		- Parameters:
		- inContent: A Uniform Type Identifier.
		- inApp: An application resolved by `resolveApp(_:)`. Resolving "None" selects Do Nothing, which disables the default handler for that UTI.
		- inRoles: The specified Launch Services Role to modify. Can correspond to "Editor", "Viewer", "Shell" or "None". A request for All roles (see `LSLegacyRoles.isAllRoles(_:)`) is handed to `NSWorkspace`; a narrower one to `LSLegacyRoles`, which answers at once.
		- setter: The calls that change the handler; the system's unless a test says otherwise.
		- completion: Called exactly once, on any queue, and before this function returns if the request is refused up front (unknown UTI, application not found) or answered by `LSLegacyRoles`.
		*/
		static func setDefaultHandler (_ inContent: String, _ inApp: ResolvedApp, _ inRoles: LSRolesMask = .all, setter: HandlerSetter = .system, completion: @escaping @Sendable (Result<Void, LSErrors>) -> Void) {
			// Both paths refuse a UTI the system does not know: recording a preference for it would help nobody.
			guard let type = UTType(inContent) else { completion(.failure(.unknownUTI)); return }
			guard LSWrappers.ensureRegistered(inApp) else { completion(.failure(.appNotFound)); return }
			if LSLegacyRoles.isAllRoles(inRoles) {
				setter.forUTI(inApp.url, type) { completion(Result(error: $0)) }
			}
			else {
				let status = setter.forRoles(inContent, inRoles, inApp.bundleID)
				completion(status == 0 ? .success(()) : .failure(LSErrors(value: status)))
			}
		}
	}
	/**
	Groups functions dealing with URI Schemes.
	*/
	class Schemes {
		/**
		The URLs that stand for a scheme when `NSWorkspace` is asked about it: "mailto:" first and then "file:///", the only shape it accepts for "file".
		*/
		private static func copyURLs (forScheme inScheme: String) -> [URL] {
			return ["\(inScheme):", "\(inScheme):///"].compactMap { URL(string: $0) }
		}
		/**
		Traverses Info dictionaries of possible handlers for an URI Scheme and copies a display name, if available.
		- Parameter inScheme: An URI Scheme.
		- Returns: A display name, or `nil` if none was found.
		*/
		static func copyNameForScheme (_ inScheme: String) -> String? {
			var schemeName: String? = nil
			if let handlers = Schemes.copyAllHandlers(inScheme) {
				
				for handler in handlers {
					
					if let schemeDicts = (Bundle(path:handler)?.infoDictionary?["CFBundleURLTypes"] as? [[String:AnyObject]]) {
						
						for schemeDict in (schemeDicts.filter() { (($0["CFBundleURLSchemes"] as? [String])?.contains() {$0.caseInsensitiveCompare(inScheme) == .orderedSame}) == true } ) {
							if let name = (schemeDict["CFBundleURLName"] as? String) {
								
								schemeName = name
								return schemeName
								
							}
							else { schemeName = nil }
							
						}
					}
				}
				
			}
			return schemeName
		}
		/**
		Creates a list of all currently registered URI Schemes and their default handler.
		- Returns: A dictionary with URI Schemes as keys and bundle identifiers as values, or nil if the system does not provide the list of schemes.
		*/
		static func copySchemesAndHandlers() -> [String:String]? {
			guard let result = LSPrivate.copySchemesAndHandlerURLs(), let pathsArray = convertAppURLsToPaths(result.handlers) else { return nil }
			return Dictionary.init (keys: result.schemes, values: pathsArray)
		}
		/**
		Copies the bundle identifier of the application currently registered as the default handler for a given URI Scheme.
		- Parameter inScheme: A valid URI Scheme.
		- Returns: The Bundle identifier or POSIX path of an application, or nil if no valid handler was found.
		*/
		static func copyDefaultHandler (_ inScheme:String, asPath: Bool = true) -> String? {
			for url in copyURLs(forScheme: inScheme) {
				if let app = NSWorkspace.shared.urlForApplication(toOpen: url) { return copyHandlers(from: [app], asPath: asPath)?.first }
			}
			return nil
		}
		/**
		Creates a list of all currently registered handlers for a given URI Scheme.
		- Parameter inScheme: A valid URI Scheme.
		- Returns: An array of strings corresponding to the Bundle identifiers or POSIX paths of all currently registered handlers, or nil of none were found.
		*/
		static func copyAllHandlers (_ inScheme:String, asPath: Bool = true) -> Array<String>? {
			for url in copyURLs(forScheme: inScheme) {
				let apps = NSWorkspace.shared.urlsForApplications(toOpen: url)
				if !apps.isEmpty { return copyHandlers(from: apps, asPath: asPath) }
			}
			return nil
		}
		/**
		Changes the default handler for a given URI Scheme. Asynchronous: macOS can ask the user to confirm first, and then answers only when the user has.
		- See Also: `enum LSErrors` above.
		- Parameters:
		- inScheme: A valid URI Scheme.
		- inApp: An application resolved by `resolveApp(_:)`. Resolving "None" selects Do Nothing, which disables the default handler for that URI Scheme.
		- setter: The calls that change the handler; the system's unless a test says otherwise.
		- completion: Called exactly once, on any queue, and before this function returns if the request is refused up front (malformed scheme, application not found).
		*/
		static func setDefaultHandler (_ inScheme: String, _ inApp: ResolvedApp, setter: HandlerSetter = .system, completion: @escaping @Sendable (Result<Void, LSErrors>) -> Void) {
			guard isValidScheme(inScheme) else { completion(.failure(.invalidScheme)); return }
			guard LSWrappers.ensureRegistered(inApp) else { completion(.failure(.appNotFound)); return }
			setter.forScheme(inApp.url, inScheme) { completion(Result(error: $0)) }
		}
	}
	
	/**
	Waits for an operation that reports through a completion. It blocks the calling thread: the command line calls it on its only
	thread, which has nothing else to do meanwhile, and the app on a background queue of its own.
	The first report wins: a second one, or one that comes after the time is up, is ignored. The wait pumps the run loop of the
	calling thread, so a completion that is dispatched to the main queue still runs when this is called from the main thread.
	- Parameter timeout: How many seconds to wait. macOS can wait for the user to answer a confirmation, so this is long.
	- Parameter operation: Starts the operation, given the completion it must call. It may call it before it returns.
	- Returns: What the operation reported, or `timedOut`.
	*/
	static func awaitCompletion (timeout: TimeInterval = 120, _ operation: (@escaping @Sendable (Result<Void, LSErrors>) -> Void) -> Void) -> Result<Void, LSErrors> {
		let first = FirstReport()
		operation { first.report($0) }
		let deadline = Date(timeIntervalSinceNow: timeout)
		while first.reported.wait(timeout: .now() + .milliseconds(50)) == .timedOut && Date() < deadline {
			RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001))
		}
		return first.outcome()
	}
	/** What `awaitCompletion` waits for: the first report, kept under a lock because it comes from any thread. */
	private final class FirstReport: @unchecked Sendable {
		private let lock = NSLock()
		private var result: Result<Void, LSErrors>?
		let reported = DispatchSemaphore(value: 0)
		func report(_ new: Result<Void, LSErrors>) {
			lock.lock(); defer { lock.unlock() }
			guard result == nil else { return }
			result = new
			reported.signal()
		}
		/// The first report, or `timedOut` (which then also wins over a report that comes later).
		func outcome() -> Result<Void, LSErrors> {
			lock.lock(); defer { lock.unlock() }
			if result == nil { result = .failure(.timedOut) }
			return result!
		}
	}
	/**
	Turns the applications Launch Services answered with into the strings callers ask for.
	- Parameter urls: File-system URLs of applications, best match first.
	- Parameter asPath: `true` for POSIX paths, `false` for bundle identifiers.
	- Returns: One string per bundle identifier, in the order given, or nil if there is none. Several copies of one application (the same bundle identifier in more than one place) count once, and the copy Launch Services ranks first for that identifier stands for them all.
	*/
	static func copyHandlers (from urls: [URL], asPath: Bool) -> [String]? {
		var seen = Set<String>()
		var handlers: [String] = []
		for url in urls {
			guard let bundleID = Bundle(url: url)?.bundleIdentifier, seen.insert(bundleID.lowercased()).inserted else { continue }
			handlers.append(asPath ? (NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) ?? url).path : bundleID)
		}
		return handlers.isEmpty ? nil : handlers
	}
	/**
	Creates a list of all currently registered applications.
	- Returns: An array of strings corresponding to the paths of all applications currently registered with Launch Services, or nil if the system does not provide the list of applications.
	*/
	static func copyAllApps () -> Array<String>? {
		return convertAppURLsToPaths(LSPrivate.copyAllApplicationURLs())
	}
	/**
	Checks whether a given application is registered with Launch Services. Has no side effects.
	- Parameter withBundleID: A bundle identifier.
	- Returns: `true` if the bundle identifier is registered with Launch Services as an application, `false` otherwise.
	*/
	static func isAppInstalled (withBundleID: String) -> Bool {
		return !NSWorkspace.shared.urlsForApplications(withBundleIdentifier: withBundleID).isEmpty
	}
	/**
	Makes sure Launch Services knows an application before a handler is assigned to it. Only Do Nothing is ever registered on demand (launching it used to do that as a side effect); any other application must already be registered.
	- Parameter app: An application resolved by `resolveApp(_:)`.
	- Parameter register: Registers an application with Launch Services; a test passes its own.
	- Returns: `true` if Launch Services knows the application, `false` if it does not and could not be made to.
	*/
	static func ensureRegistered (_ app: ResolvedApp, register: (URL) -> Bool = { !LSWrappers.isReadOnly && LSRegisterURL($0 as CFURL, true) == noErr }) -> Bool {
		guard FileManager.default.fileExists(atPath: app.url.path) else { return false }
		guard app.bundleID == DoNothingApp.bundleID else { return isAppInstalled(withBundleID: app.bundleID) }
		// Another copy of Do Nothing can be the registered one (a stale build, say); what is handed out is the copy that was chosen.
		guard DoNothingApp.isGenuine(app.url) else { return false }
		let known = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: app.bundleID).map { $0.resolvingSymlinksInPath().path }
		return known.contains(app.url.resolvingSymlinksInPath().path) || register(app.url)
	}
	/**
	Where a copy of an application lives, from the place a copy can be trusted most to the place it can be trusted least. Only an administrator can write to the first, so a program running as the user cannot put a look-alike there.
	*/
	enum AppLocation: Int, Comparable {
		/// `/Applications`, `/System` (the Safari Cryptex is under it too) and `/Library`.
		case system
		/// The user's own Applications folder.
		case user
		/// Anywhere else: a download, a disk image, a build folder.
		case elsewhere

		/**
		- Parameters:
		  - path: A POSIX path to an application.
		  - userApplications: The user's Applications folder; the default is the real one.
		*/
		init(path: String, userApplications: String = FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask).first?.path ?? "") {
			var real = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
			// The data volume is where the user's files live; it shows through under /System/Volumes/Data, which is not the system.
			if real.hasPrefix("/System/Volumes/Data/") { real = String(real.dropFirst("/System/Volumes/Data".count)) }
			let mine = URL(fileURLWithPath: userApplications).resolvingSymlinksInPath().path
			if ["/Applications/", "/System/", "/Library/"].contains(where: { real.hasPrefix($0) }) { self = .system }
			else if !mine.isEmpty && real.hasPrefix(mine + "/") { self = .user }
			else { self = .elsewhere }
		}
		static func < (lhs: AppLocation, rhs: AppLocation) -> Bool { lhs.rawValue < rhs.rawValue }
	}
	/**
	Chooses among copies of an application that share a file name. The best copy is one outside another bundle, in the most trusted location, that Launch Services itself prefers for its bundle identifier; each of the three outranks the ones after it.
	- Parameters:
	  - paths: POSIX paths of applications. Two paths to one file count once.
	  - userApplications: The user's Applications folder; the default is the real one.
	- Returns: The best copies, one path per file, sorted: one path if one copy is best, several if nothing tells them apart, none if `paths` is empty.
	*/
	static func copyBestApps (among paths: [String], userApplications: String? = nil) -> [String] {
		func rank(_ path: String) -> (Int, AppLocation, Int) {
			let isNested = path.dropLast(4).contains(".app/")
			let location = userApplications.map { AppLocation(path: path, userApplications: $0) } ?? AppLocation(path: path)
			let preferred = Bundle(path: path)?.bundleIdentifier.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
			let isPreferred = preferred?.resolvingSymlinksInPath().path == URL(fileURLWithPath: path).resolvingSymlinksInPath().path
			return (isNested ? 1 : 0, location, isPreferred ? 0 : 1)
		}
		var seen = Set<String>()
		let distinct = paths.sorted().filter { seen.insert(URL(fileURLWithPath: $0).resolvingSymlinksInPath().path).inserted }
		let ranked = distinct.map { (path: $0, rank: rank($0)) }
		guard let best = ranked.map(\.rank).min(by: { $0 < $1 }) else { return [] }
		return ranked.filter { $0.rank == best }.map(\.path)
	}
	/**
	Finds applications by their file name. Stands in for `NSWorkspace.fullPath(forApplication:)`, which is deprecated and has no replacement. Like it, anything that looks like a path is returned unchanged; otherwise registered applications are matched by file name (case-insensitive, ".app" optional, so "Spotlight.service" matches too).
	- Note: Several registered copies can share a name (helpers nested inside other apps, an updater's staging copy, a look-alike somebody planted). `copyBestApps(among:userApplications:)` picks the best; where nothing tells the best apart, all of them are returned and `resolveApp(_:)` refuses to guess.
	- Parameter name: A path, or the name of an application, with or without ".app".
	- Returns: The path itself, or the POSIX paths of the best registered copies: none if no registered application has that name, several if the name is ambiguous.
	*/
	static func copyAppPaths (named name: String) -> [String] {
		if name.hasPrefix("/") || name.hasPrefix("~") { return [name] }
		let wanted = name.lowercased().hasSuffix(".app") ? [name.lowercased()] : [name.lowercased(), "\(name.lowercased()).app"]
		return copyBestApps(among: (copyAllApps() ?? []).filter { wanted.contains(($0 as NSString).lastPathComponent.lowercased()) })
	}
	/**
	Whether text has the shape of a bundle identifier: dot-separated, non-empty words of ASCII letters, digits, hyphens and underscores. A file name such as "Safari" does not; an identifier is the only thing that is looked up by identifier.
	*/
	static func isBundleID (_ text: String) -> Bool {
		guard text.contains("."), !text.lowercased().hasSuffix(".app"), !text.split(separator: ".", omittingEmptySubsequences: false).contains(where: \.isEmpty) else { return false }
		return text.unicodeScalars.allSatisfy { ($0.isASCII && ($0.properties.isAlphabetic || $0.properties.numericType != nil)) || $0 == "." || $0 == "-" || $0 == "_" }
	}
	/**
	Performs a myriad of sanity checks on user input corresponding to a possible application. The main purpose of this function is to make sure we're passing a value as sane as possible to the setHandler functions.
	- See Also: `enum LSErrors` above.
	- Parameter inParam: The application to locate. It might correspond to a file-system URL, a POSIX path, a display name, a bundle identifier, or "None".
	- Parameter copyPaths: Finds the registered copies of an application by name; a test passes its own.
	- Returns: The application, or the error that says why it cannot be used. The bundle identifier of the result is the one in the application's own Info.plist, whatever spelling was typed.
	*/
	static func resolveApp (_ inParam: String, copyPaths: (String) -> [String] = { copyAppPaths(named: $0) }) -> Result<ResolvedApp, LSErrors> {
		var errCode = OSStatus()
		let filemanager = FileManager.default
		func app(from bundle: Bundle, allowing types: Set<String>) -> Result<ResolvedApp, LSErrors> {
			guard let type = bundle.copyType(outError: &errCode) else { return .failure(LSErrors(value: errCode)) }
			guard types.contains(type), let bundleID = bundle.bundleIdentifier else { return .failure(.notAnApp) }
			return .success(ResolvedApp(url: bundle.bundleURL, bundleID: bundleID))
		}
		if DoNothingApp.isNamed(inParam) { // None is a valid value for Do Nothing.
			guard let url = DoNothingApp.copyURL() else { return .failure(.appNotFound) }
			return .success(ResolvedApp(url: url, bundleID: DoNothingApp.bundleID))
		}
		if isBundleID(inParam), let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: inParam) { // Check whether we have a valid Bundle ID for an application.
			return .success(ResolvedApp(url: url, bundleID: Bundle(url: url)?.bundleIdentifier ?? inParam))
		}
		let appPaths = copyPaths(inParam) // Or an application designed by name
		if appPaths.count > 1 { return .failure(.ambiguousApp) }
		if let appPath = appPaths.first {
			if let bundle = Bundle(path: appPath) { return app(from: bundle, allowing: ["APPL", "FNDR"]) }
			return filemanager.fileExists(atPath: inParam) ? .failure(.notAnApp) : .failure(.appNotFound)
		}
		else {
			if let bundle = Bundle(path: inParam) { return app(from: bundle, allowing: ["APPL"]) } // Is it a valid bundle path?
			if (filemanager.fileExists(atPath: inParam) == true) { return .failure(.notAnApp) } // Maybe it's a valid file path, but not an app bundle?
			guard let url = URL(string: inParam) else { return .failure(.notAnApp) } // Let's fallback to an URL.
			if (url.path != "") {
				guard url.isFileURL else { return .failure(.notAnApp) }
				guard filemanager.fileExists(atPath: url.path) else { return .failure(.appNotFound) } // No application found at this location.
				guard let bundle = Bundle(url: url) else { return .failure(.notAnApp) } // Maybe it's a valid file URL, but not an app bundle?
				return app(from: bundle, allowing: ["APPL"])
			}
			else if (url.isFileURL == false) { return .failure(.invalidFileURL) }
		}
		return .failure(.defaultErr)
	}
	/**
	Creates a list of UTIs and URI Schemes an application claims to be able to handle.
	- Note: We perform little if any sanity checks in this function because it is not intended to be exposed to user input.
	- Parameter inApp: A POSIX path corresponding to a valid application bundle.
	- Returns: A dictionary of sets containing a list of strings corresponding to URI Schemes and Uniform Type Identifiers listed in CFBundleURLTypes and CFBundleDocumentTypes respectively.
	*/
	static func copySchemesAndUTIsForApp (_ inApp: String) -> [String:[String:Set<String>]]? {
		var handledUriSchemes: [String:Set<String>] = ["Viewer":[]]
		var handledUTIs: [String:Set<String>] = ["Editor":[],"Viewer":[],"Shell":[]]
		var handledTypes: [String:[String:Set<String>]] = [:]
		if let infoDict = Bundle(path: inApp)?.infoDictionary {
			guard ((infoDict["CFBundlePackageType"] as? String) == "APPL") else { return nil }
			if let schemeDicts = (infoDict["CFBundleURLTypes"] as? [[String:AnyObject]]) {
				for schemeDict in schemeDicts {
					if let schemesArray = (schemeDict["CFBundleURLSchemes"] as? [String]) {
						handledUriSchemes["Viewer"]!.formUnion(schemesArray)
					}
				}
			}
			if let utiDicts = (infoDict["CFBundleDocumentTypes"] as? [[String:AnyObject]]) {
				var utiArray: [String] = []
				for utiDict in utiDicts.filter({ ($0["CFBundleTypeRole"] as? String == "Editor" || $0["CFBundleTypeRole"] as? String == "Viewer" || $0["CFBundleTypeRole"] as? String == "Shell" || $0["CFBundleTypeRole"] == nil) }) {
					let typeRole = utiDict["CFBundleTypeRole"] as? String ?? "Viewer"
					if let utiArray = (utiDict["LSItemContentTypes"] as? [String]) {
						handledUTIs[typeRole]!.formUnion(utiArray)
					}
					else if let fileExtArray = (utiDict["CFBundleTypeExtensions"] as? [String]) {
						for fileExt in fileExtArray {
							if let newType = UTType(tag: fileExt, tagClass: .filenameExtension, conformingTo: .content) {

								if ((!newType.isDynamic) && (handledUTIs[typeRole]!.firstIndex(of:newType.identifier) == nil)) {
									utiArray.append(newType.identifier)
								}
							}
						}
					}
					handledUTIs[typeRole]!.formUnion(utiArray)
				}
			}
		}
		handledTypes["URIs"] = !handledUriSchemes.isEmpty ? handledUriSchemes : [:]
		handledTypes["UTIs"] = !handledUTIs.isEmpty ? handledUTIs : [:]
		return handledTypes
	}
}

extension Result where Success == Void, Failure == LSWrappers.LSErrors {
	/**
	The outcome `NSWorkspace` reports through the optional error of a completion.
	An error that nothing in `LSErrors` explains becomes `defaultErr`, which has no room for the system's own words, so they are logged.
	*/
	init(error: Error?) {
		guard let error else { self = .success(()); return }
		let mapped = LSWrappers.LSErrors(error)
		if mapped == .defaultErr, !(error is LSWrappers.LSErrors) {
			let described = error as NSError
			// The unified log keeps NSLog arguments in the clear; the system's own words can contain paths, so they stay private.
				Logger(subsystem: LSWrappers.logSubsystem, category: "errors").error("macOS reported an error it has no message for: \(described.localizedDescription, privacy: .private) (\(described.domain, privacy: .public) \(described.code, privacy: .public))")
		}
		self = .failure(mapped)
	}
}
