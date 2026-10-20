/*
* ----------------------------------------------------------------------------
* "THE BEER-WARE LICENSE" (Revision 42):
* <g.litenstein@gmail.com> wrote this file. As long as you retain this notice you
* can do whatever you want with this stuff. If we meet some day, and you think
* this stuff is worth it, you can buy me a beer in return., Gregorio Litenstein.
* ----------------------------------------------------------------------------
*/

import AppKit

/**
Converts an array of Application URLs to an array of Application Paths.
- Parameter inArray: An array of file-system URLs corresponding to applications.
- Returns: An array of strings corresponding to the POSIX paths of the supplied applications.
*/
func convertAppURLsToPaths (_ inArray:Array<URL>?) -> Array<String>? {
	if let URLArray = inArray {
		var outputArray: Array<String> = []
		for (i, app) in URLArray.enumerated() {
			let temp = app.path
			outputArray.insert(temp, at:i)
		}
		return outputArray
	}
	else { return nil }
}

/**
Creates a String representation of a Dictionary of Strings.
- Parameter inDict: A dictionary of Strings.
- Returns: A string corresponding to the contents of the supplied dictionary.
*/
func copyDictionaryAsString (_ inDict: [(key:String, value:String)]?) -> String? {
	var output = ""
	if let temp = inDict {
		
		for (key, value) in temp {
			output+=("\(displayable(key))\t\t\t\t\(displayable(value))\n")
		}
	}
	else { return nil }
	return output
}

/**
Creates a String representation of an Array of Strings.
- Parameter inArray: An array of strings.
- Parameter separator: The separator to be used.
- Returns: A string corresponding to the contents of the supplied array.
*/
func copyStringArrayAsString (_ inArray: Array<String>?, separator: String = "\n") -> String? {
	if let temp = inArray {
		return temp.map(displayable).joined(separator:separator)
	}
	else { return nil }
}

/**
Whether a string is a well-formed URI Scheme: a letter, then letters, digits, "+", "-" or ".", all ASCII (RFC 3986).
A scheme of one letter is valid. Nothing else is: not a trailing line break, not a combining mark, not an empty string.
*/
func isValidScheme (_ inScheme: String) -> Bool {
	guard let first = inScheme.unicodeScalars.first, first.isASCII, first.properties.isAlphabetic else { return false }
	return inScheme.unicodeScalars.allSatisfy { scalar in
		scalar.isASCII && (scalar.properties.isAlphabetic || ("0"..."9").contains(Character(scalar)) || "+-.".unicodeScalars.contains(scalar))
	}
}

/**
Makes a string safe to print where a person or a script reads it. Launch Services hands us names, paths and identifiers that other applications wrote, and a terminal obeys the escape sequences, carriage returns and bidirectional controls among them.
- Parameter inString: Any string.
- Returns: The string with every control character, line or paragraph separator and invisible or bidirectional format character written as `\u{XXXX}`. Ordinary text, including emoji joiners, is unchanged.
*/
func displayable (_ inString: String) -> String {
	let hidden: Set<UInt32> = [0x061C, 0x200B, 0x200E, 0x200F, 0x2060, 0xFEFF] // Arabic letter mark, zero-width space, left/right marks, word joiner, byte order mark.
	var output = String.UnicodeScalarView()
	for scalar in inString.unicodeScalars {
		let category = scalar.properties.generalCategory
		let isBidi = (0x202A...0x202E).contains(scalar.value) || (0x2066...0x2069).contains(scalar.value)
		if category == .control || category == .lineSeparator || category == .paragraphSeparator || isBidi || hidden.contains(scalar.value) {
			output.append(contentsOf: "\\u{\(String(scalar.value, radix: 16, uppercase: true))}".unicodeScalars)
		}
		else { output.append(scalar) }
	}
	return String(output)
}


//// EXTENSIONS

extension Bundle {
	/**
	Copies a bundle's package type, as specified in its Info.plist.
	- Parameter outError: Populated with an error-code if the bundle does not correspond to a valid package.
	- Returns: The four-letter code specifying the bundle's package type, or `nil` if an error is encountered.
	*/
	func copyType (outError: inout OSStatus) -> String? {
		if let info = self.infoDictionary {
			if let type = info["CFBundlePackageType"] {
				return String(describing: type)
			}
			else { outError = errSecInvalidBundleInfo; return nil }
		}
		else { outError = kLSUnknownErr; return nil }
	}
}

extension Dictionary
{
	/**
	Create a Dictionary by Merging two Arrays.
	- Parameter keys: An Array to be used as dictionary keys.
	- Parameter values: An Array to be used as values.
	*/
	public init(keys: [Key], values: [Value])
	{
		precondition(keys.count == values.count)
		
		self.init()
		
		for (index, key) in keys.enumerated()
		{
			self[key] = values[index]
		}
	}
}


/** Determines whether the app is running in app or CLI form by checking the Main Bundle Identifier. */
func areWeCLI() -> Bool {
	return (Bundle.main.bundleIdentifier == nil)
}

/**
Reports the outcome of a change of default handler on the command line, where every other answer goes: standard output.
- Parameter result: What the change returned.
- Parameter app: The application the user asked for, as a bundle identifier or as typed.
- Parameter content: The URI Scheme or UTI the change was for.
*/
func report(_ result: Result<Void, LSWrappers.LSErrors>, app: String?, content: String?) {
	switch result {
	case .success: print(LSWrappers.LSErrors.noError.print(argument: (app: app, content: content)))
	case .failure(let error): print(error.print(argument: (app: app, content: content)))
	}
}
