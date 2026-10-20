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
/// SwiftCLI pads each unrecognized option to a fixed width and traps ("Negative count not allowed") on one longer than 40
/// characters, such as --URL=<long url>. Such an option gets a plain message; anything shorter keeps SwiftCLI's own.
struct MisusedOptionsMessageGenerator: SwiftCLI.MisusedOptionsMessageGenerator {
	private let standard = CLI.misusedOptionsMessageGenerator // SwiftCLI's own, read before this one replaces it
	func generateMisusedOptionsStatement(for command: Command, incorrectOptionUsage: IncorrectOptionUsage) -> String? {
		guard incorrectOptionUsage.unrecognizedOptions.contains(where: { $0.count > 40 }) else {
			return standard.generateMisusedOptionsStatement(for: command, incorrectOptionUsage: incorrectOptionUsage)
		}
		guard command is OptionCommand else { return nil }
		let options = incorrectOptionUsage.unrecognizedOptions.map { "\t" + displayable($0.count > 80 ? String($0.prefix(77)) + "..." : $0) }
		return CLI.usageStatementGenerator.generateUsageStatement(for: command, optionRegistry: incorrectOptionUsage.optionRegistry) + "\nUnrecognized options:\n" + options.joined(separator: "\n") + "\n"
	}
}

CLI.misusedOptionsMessageGenerator = MisusedOptionsMessageGenerator()
CLI.setup(name:"swda", version:"1.0", description:"Utility to retrieve and manipulate default applications in macOS.")
CLI.register(commands: [ ReadCommand(), GetApps(), GetSchemes(), GetUTIs(), SetCommand() ])

exit(CLI.go())
