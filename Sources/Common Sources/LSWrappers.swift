/*
* ----------------------------------------------------------------------------
* "THE BEER-WARE LICENSE" (Revision 42):
* <g.litenstein@gmail.com> wrote this file. As long as you retain this notice you
* can do whatever you want with this stuff. If we meet some day, and you think
* this stuff is worth it, you can buy me a beer in return., Gregorio Litenstein.
* ----------------------------------------------------------------------------
*/

import AppKit
import UniformTypeIdentifiers

/**
Functions wrapping varied Launch Services tasks to be re-used throughout the application.
*/
class LSWrappers {
	
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
	- canceled: The user declined the confirmation macOS asks for before it changes a default handler.
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
		case canceled = -128
		case permissionDenied = -54
		case timedOut = -1712
		
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
			case -128: self = .canceled
			case -54: self = .permissionDenied
			case -1712: self = .timedOut
				
			case 0: self = .noError
			default: self = .defaultErr
			}
			
		}
		/**
		Maps an error reported by `NSWorkspace` to the closest case. A declined confirmation arrives as `NSUserCancelledError` or as an
		`NSOSStatusErrorDomain` error, and the reason for a failure can sit a level down, under `NSUnderlyingErrorKey`.
		- Parameter error: Any error. One of ours is returned as it is; one nothing here recognizes becomes `defaultErr`.
		*/
		init(_ error: Error) {
			if let known = error as? LSErrors { self = known; return }
			var next: NSError? = error as NSError
			while let current = next {
				if current.domain == NSCocoaErrorDomain && current.code == NSUserCancelledError { self = .canceled; return }
				if current.domain == NSOSStatusErrorDomain, let known = LSErrors(rawValue: OSStatus(truncatingIfNeeded: current.code)), known != .noError { self = known; return }
				next = current.userInfo[NSUnderlyingErrorKey] as? NSError
			}
			self = .defaultErr
		}
		/**
		Print a user-readable error message for each error code.
		
		- Parameter argument:
		app: The application specified by the user, which could conceivably be a URL, a file-path, a bundle identifier or even a display name.
		content: This is only used in the case the user supplies a malformed URI Scheme.
		
		- Returns: Human-readable error message specifying the problem, or unknown error if the problem is something not accounted for here.
		*/
		func print(argument: (app: String?, content: String?) = (String(),String())) -> String {
			let app = argument.app ?? String(), content = argument.content ?? String()
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
			case .canceled: retValue += "Changing the default handler for \(content) was canceled."
			case .permissionDenied: retValue += "macOS did not allow changing the default handler for \(content)."
			case .timedOut: retValue += "Timed out waiting for the change of the default handler for \(content)."
			case .noError: retValue += "Default handler has succesfully changed to \(app)"
			case .defaultErr: retValue += "An unknown error has occurred."
			}
			if ((self == .appNotFound || self == .deletedApp) && DoNothingApp.isNamed(argument.app)) { retValue += " (This error occurs when \(DoNothingApp.fileName) is not found.)" }
			return retValue
		}
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
			if LSLegacyRoles.isRoleless(inRoles) {
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
			if LSLegacyRoles.isRoleless(inRoles) {
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
		Changes the default handler for a given UTI.
		- See Also: `enum LSErrors` above.
		- Parameters:
		- inContent: A Uniform Type Identifier.
		- inApp: An application resolved by `resolveApp(_:)`. Resolving "None" selects the dummy application, which disables the default handler for that UTI.
		- inRoles: The specified Launch Services Role to modify. Can correspond to "Editor", "Viewer", "Shell" or "None".
		- Returns: A status-code. `0` on success, or a value corresponding to various possible errors.
		*/
		static func setDefaultHandler (_ inContent: String, _ inApp: ResolvedApp, _ inRoles: LSRolesMask = LSRolesMask.all) -> OSStatus {
			var retval: OSStatus = 0
			if (LSWrappers.ensureRegistered(inApp) == true) {
				retval = LSLegacyRoles.setDefaultHandler(inContent, inRoles, bundleID: inApp.bundleID)
			}
			else { retval = kLSApplicationNotFoundErr }
			return retval
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
		Changes the default handler for a given URI Scheme.
		- See Also: `enum LSErrors` above.
		- Parameters:
		- inScheme: A valid URI Scheme.
		- inApp: An application resolved by `resolveApp(_:)`. Resolving "None" selects the dummy application, which disables the default handler for that URI Scheme.
		- Returns: A status-code. `0` on success, or a value corresponding to various possible errors.
		*/
		static func setDefaultHandler (_ inScheme: String, _ inApp: ResolvedApp) -> OSStatus {
			var retval: OSStatus = kLSUnknownErr
			if ((inScheme =~ /"\\A[a-zA-Z][a-zA-Z0-9.+-]+$") == true) {
				if (LSWrappers.ensureRegistered(inApp) == true) {
					retval = LSSetDefaultHandlerForURLScheme((inScheme as CFString), (inApp.bundleID as CFString))
				}
				else { retval = kLSApplicationNotFoundErr }
			}
			else { retval = Int32(kURLUnsupportedSchemeError) }
			return retval
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
	Makes sure Launch Services knows an application before a handler is assigned to it. Only the dummy application is ever registered on demand (launching it used to do that as a side effect); any other application must already be registered.
	- Parameter app: An application resolved by `resolveApp(_:)`.
	- Returns: `true` if Launch Services knows the application, `false` if it does not and could not be made to.
	*/
	static func ensureRegistered (_ app: ResolvedApp) -> Bool {
		if isAppInstalled(withBundleID: app.bundleID) && FileManager.default.fileExists(atPath: app.url.path) { return true }
		return app.bundleID == DoNothingApp.bundleID && LSRegisterURL(app.url as CFURL, true) == noErr
	}
	/**
	Finds an application by its file name. Stands in for `NSWorkspace.fullPath(forApplication:)`, which is deprecated and has no replacement. Like it, anything that looks like a path is returned unchanged; otherwise registered applications are matched by file name (case-insensitive, ".app" optional, so "Spotlight.service" matches too).
	- Note: Several registered copies can share a name (helpers nested inside other apps, an updater's staging copy). The best one wins: a copy outside another bundle beats one inside it, one in a standard Applications folder beats one elsewhere, the copy Launch Services itself ranks first for its bundle identifier beats the others, and the shortest path decides the rest.
	- Parameter name: A path, or the name of an application, with or without ".app".
	- Returns: A POSIX path, or nil if no registered application has that name.
	*/
	static func copyAppPath (named name: String) -> String? {
		if name.hasPrefix("/") || name.hasPrefix("~") { return name }
		let wanted = name.lowercased().hasSuffix(".app") ? [name.lowercased()] : [name.lowercased(), "\(name.lowercased()).app"]
		let matches = (copyAllApps() ?? []).filter { wanted.contains(($0 as NSString).lastPathComponent.lowercased()) }
		let standardFolders = FileManager.default.urls(for: .applicationDirectory, in: .allDomainsMask).map { $0.path } + ["/System/Library/CoreServices"]
		// Lower is better.
		func rank(_ path: String) -> Int {
			let isNested = path.dropLast(4).contains(".app/")
			let isStandard = standardFolders.contains { path.hasPrefix($0 + "/") }
			let isPreferred = Bundle(path: path)?.bundleIdentifier.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)?.path } == path
			return (isNested ? 4 : 0) + (isStandard ? 0 : 2) + (isPreferred ? 0 : 1)
		}
		return matches.min { (rank($0), $0.count) < (rank($1), $1.count) }
	}
	/**
	Performs a myriad of sanity checks on user input corresponding to a possible application. The main purpose of this function is to make sure we're passing a value as sane as possible to the setHandler functions.
	- See Also: `enum LSErrors` above.
	- Parameter inParam: The application to locate. It might correspond to a file-system URL, a POSIX path, a display name, a bundle identifier, or "None".
	- Returns: The application, or the error that says why it cannot be used.
	*/
	static func resolveApp (_ inParam: String) -> Result<ResolvedApp, LSErrors> {
		var errCode = OSStatus()
		let filemanager = FileManager.default
		func app(from bundle: Bundle, allowing types: Set<String>) -> Result<ResolvedApp, LSErrors> {
			guard let type = bundle.getType(outError: &errCode) else { return .failure(LSErrors(value: errCode)) }
			guard types.contains(type), let bundleID = bundle.bundleIdentifier else { return .failure(.notAnApp) }
			return .success(ResolvedApp(url: bundle.bundleURL, bundleID: bundleID))
		}
		if DoNothingApp.isNamed(inParam) { // None is a valid value for our dummy application.
			guard let url = DoNothingApp.copyURL() else { return .failure(.appNotFound) }
			return .success(ResolvedApp(url: url, bundleID: DoNothingApp.bundleID))
		}
		if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: inParam) { // Check whether we have a valid Bundle ID for an application.
			return .success(ResolvedApp(url: url, bundleID: inParam))
		}
		else if let appPath = copyAppPath(named: inParam) { // Or an application designed by name
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
