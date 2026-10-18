import Foundation

/**
The only file that names Apple's private functions.

Nothing public lists the URL schemes, the applications or the declared types that Launch Services knows about,
so the app and the CLI call three private functions. They are looked up with `dlsym` instead of being linked.
At a deployment target of macOS 12 or later every linked symbol is bound when the program launches, so a
function that a later macOS removed would stop the process before `main` ("Symbol not found") even if nothing
ever called it. A failed lookup is only `nil`, and the callers say that the list is not available.
*/
enum LSPrivate {
	/// Looks a function up at run time. `name` is the C name as declared, leading underscore included.
	static func symbol<T>(_ name: String, as type: T.Type) -> T? {
		guard let address = dlsym(UnsafeMutableRawPointer(bitPattern: -2) /* RTLD_DEFAULT */, name) else { return nil }
		return unsafeBitCast(address, to: type)
	}

	// All three are "Copy" functions: the caller owns what they return, hence `Unmanaged` and `takeRetainedValue()`.
	private typealias CopySchemesAndHandlerURLs = @convention(c) (UnsafeMutablePointer<Unmanaged<NSArray>?>, UnsafeMutablePointer<Unmanaged<NSMutableArray>?>) -> OSStatus
	private typealias CopyAllApplicationURLs = @convention(c) (UnsafeMutablePointer<Unmanaged<NSMutableArray>?>) -> OSStatus
	private typealias CopyDeclaredTypeIdentifiers = @convention(c) () -> Unmanaged<NSArray>?

	/**
	Copies every URI Scheme Launch Services knows, each paired with the application that handles it by default.
	- Returns: The schemes and, index for index, the file-system URLs of their default handlers; or nil if the system does not provide the list.
	*/
	static func copySchemesAndHandlerURLs() -> (schemes: [String], handlers: [URL])? {
		guard let function = symbol("_LSCopySchemesAndHandlerURLs", as: CopySchemesAndHandlerURLs.self) else { return nil }
		var schemes: Unmanaged<NSArray>?
		var handlers: Unmanaged<NSMutableArray>?
		guard function(&schemes, &handlers) == 0,
			  let schemeNames = schemes?.takeRetainedValue() as? [String],
			  let handlerURLs = handlers?.takeRetainedValue() as? [URL],
			  schemeNames.count == handlerURLs.count else { return nil }
		return (schemeNames, handlerURLs)
	}

	/**
	Copies the file-system URL of every application registered with Launch Services.
	- Returns: The URLs, or nil if the system does not provide the list.
	*/
	static func copyAllApplicationURLs() -> [URL]? {
		guard let function = symbol("_LSCopyAllApplicationURLs", as: CopyAllApplicationURLs.self) else { return nil }
		var applications: Unmanaged<NSMutableArray>?
		guard function(&applications) == 0, let urls = applications?.takeRetainedValue() as? [URL] else { return nil }
		return urls
	}

	/**
	Copies every Uniform Type Identifier declared by any registered bundle, abstract ones included.
	- Returns: The identifiers, or nil if the system does not provide the list.
	*/
	static func copyDeclaredTypeIdentifiers() -> [String]? {
		guard let function = symbol("_UTCopyDeclaredTypeIdentifiers", as: CopyDeclaredTypeIdentifiers.self) else { return nil }
		return function()?.takeRetainedValue() as? [String]
	}
}
