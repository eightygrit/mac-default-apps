/*
* ----------------------------------------------------------------------------
* "THE BEER-WARE LICENSE" (Revision 42):
* <g.litenstein@gmail.com> wrote this file. As long as you retain this notice you
* can do whatever you want with this stuff. If we meet some day, and you think
* this stuff is worth it, you can buy me a beer in return., Gregorio Litenstein.
* ----------------------------------------------------------------------------
*/

import Foundation
import SwiftCLI

class SetCommand: OptionCommand {
	var failOnUnrecognizedOptions = true
	let name = "setHandler"
	let signature = ""
	let shortDescription = "Sets <application> as the default handler for a given <type>/<subtype> combination."
	private var kind: String = ""
	private var contentType: String? = nil
	private var inApplication: String = DoNothingApp.cliName
	private var app: LSWrappers.ResolvedApp? = nil
	private var unknownRole: String? = nil
	private var role: LSRolesMask = LSRolesMask.all
	
	func setupOptions(options: OptionRegistry) {
		options.addGroup(name:"type", required:true, conflicting:true)
		options.addGroup(name:"application", required:true, conflicting:true)
		options.add(keys: ["--UTI"], usage: "Change the default application for <subtype>", valueSignature: "subtype", group:"type") { [unowned self] (value) in
			self.contentType = value
			self.kind = "UTI"
		}
		options.add(keys: ["--extension", "--ext"], usage: "Change the default application for files with <extension>", valueSignature: "extension", group:"type") { [unowned self] (value) in
			self.contentType = value
			self.kind = "Extension"
		}
		options.add(keys: ["--URL"], usage: "Change the default application for <subtype>", valueSignature: "subtype", group:"type") { [unowned self] (value) in
			self.contentType = value
			self.kind = "URL"
		}
		
		options.add(flags: ["--internet", "--browser", "--web"], usage: "Changes the default web browser.", group:"type") {
			self.contentType = nil
			self.kind = "http"
		}
		options.add(flags: ["--mail", "--email", "--e-mail"], usage: "Changes the default e-mail client.", group:"type") {
			self.contentType = nil
			self.kind = "mailto"
		}
		options.add(flags: ["--ftp"], usage: "Changes the default FTP client.", group:"type") {
			self.contentType = nil
			self.kind = "ftp"
		}
		options.add(flags: ["--rss"], usage: "Changes the default RSS client.", group:"type") {
			self.contentType = nil
			self.kind = "RSS"
		}
		options.add(flags: ["--news"], usage: "Changes the default news client.", group:"type") {
			self.contentType = nil
			self.kind = "news"
		}
		options.add(keys: ["--app", "--application"], usage: "The <application> to register as default handler. Specifying \"\(DoNothingApp.cliName)\" assigns Do Nothing, an application that ignores whatever it is asked to open.", valueSignature: "application", group:"application") { [unowned self] (value) in
			self.inApplication = value
		}
		options.add(keys: ["--role"], usage: "--role <Viewer|Editor|Shell|All>, specifies the role with which to register the handler. Default is All.", valueSignature: "role") { [unowned self] (value) in
			// A word that is not a role is refused in execute(): widening a write to every role because of a typo would be wrong.
			if let temp = LSLegacyRoles.mask(named: value) { self.role = temp; self.unknownRole = nil }
			else { self.unknownRole = value }
		}
	}
	
	func execute(arguments: CommandArguments) throws  {
		if let unknownRole = unknownRole {
			throw CLIError.error("SwiftDefaultApps ERROR: \(displayable(unknownRole)) is not a role. Use Viewer, Editor, Shell or All.")
		}
		if (kind == "UTI" || kind == "Extension") && !LSLegacyRoles.isAllRoles(role) && !LSLegacyRoles.isAvailable {
			throw CLIError.error("SwiftDefaultApps ERROR: \(LSLegacyRoles.unavailableMessage)")
		}
		switch LSWrappers.resolveApp(self.inApplication) {
		case .failure(let error): throw CLIError.error(error.print(argument: (app: inApplication, content: self.contentType ?? self.kind)))
		case .success(let resolved): app = resolved
		}
		var result: Result<Void, LSWrappers.LSErrors> = .failure(.defaultErr)
		switch(kind) {
		case "UTI","Extension","URL":
			if let contentString = self.contentType {
				let content = (kind == "Extension") ? LSWrappers.UTIs.copyUTIForExtension(contentString) : contentString
				guard let contentUTI = content else { throw CLIError.error("SwiftDefaultApps ERROR: Could not resolve \(contentString) to a UTI.") }
				result = LSWrappers.awaitCompletion { completion in
					if (kind == "URL") { LSWrappers.Schemes.setDefaultHandler(contentUTI, app!, completion: completion) }
					else { LSWrappers.UTIs.setDefaultHandler(contentUTI, app!, self.role, completion: completion) }
				}
				self.contentType = contentUTI
			}
			break
		case "http","mailto","ftp","rss","news":
			result = LSWrappers.awaitCompletion { LSWrappers.Schemes.setDefaultHandler(kind, app!, completion: $0) }
			break
			
		default:
			break
		}
		report(result, app: app?.bundleID ?? inApplication, content: self.contentType ?? self.kind)
	}
}
