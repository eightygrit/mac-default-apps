/*
 * ----------------------------------------------------------------------------
 * "THE BEER-WARE LICENSE" (Revision 42):
 * <g.litenstein@gmail.com> wrote this file. As long as you retain this notice you
 * can do whatever you want with this stuff. If we meet some day, and you think
 * this stuff is worth it, you can buy me a beer in return., Gregorio Litenstein.
 * ----------------------------------------------------------------------------
 */

import Cocoa
import UniformTypeIdentifiers

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    /// Installs the delegate by hand: the main nib that used to do it was deleted long ago, which left every handler below unreachable.
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    /// The first item of the direct object: an Open Documents event carries a list, a Get URL event a single string.
    private func copyDirectObjectString(of event: NSAppleEventDescriptor) -> String? {
        guard let direct = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)) else { return nil }
        return (direct.atIndex(1) ?? direct).stringValue
    }

    @objc func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent: NSAppleEventDescriptor) {
        // Only the scheme is logged: NSLog arguments are public in the unified log, and a URL can carry tokens in its query.
        let scheme = copyDirectObjectString(of: event).flatMap { URLComponents(string: $0)?.scheme } ?? "unknown"
        NSLog("Dummy application launched in response to a URL with scheme: %@, will now exit.", scheme)
    }
    
    @objc func handleOpenEvent(_ event: NSAppleEventDescriptor, withReplyEvent: NSAppleEventDescriptor) {
        guard let documentPassed = copyDirectObjectString(of: event), let documentURL = URL(string: documentPassed), documentURL.isFileURL,
              let documentType = (try? documentURL.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.identifier else {
            NSLog("Dummy application launched in response to file with unknown type, will now exit.")
            return
        }
        NSLog("Dummy application launched in response to file of type: %@, will now exit.", documentType)
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(AppDelegate.handleGetURLEvent(_:withReplyEvent:)), forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(AppDelegate.handleOpenEvent(_:withReplyEvent:)), forEventClass: AEEventClass(kCoreEventClass), andEventID: AEEventID(kAEOpenDocuments))
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApplication.shared.terminate(self)
    }

}
