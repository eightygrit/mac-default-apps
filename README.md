> **Status:** Apple has introduced replacements for the deprecated Launch Services APIs this app used, and the app and `swda` now use them wherever a replacement exists. The Viewer, Editor and Shell roles have none, so a request for one role alone still uses the old per-role functions, looked up at run time so that their removal cannot stop the app from launching. Reading was checked on macOS 15. **Changing a default through the new calls has not been tested yet on any version of macOS** (`Tests/write-roundtrip.sh` exists for that). See [How it works with macOS](#how-it-works-with-macos).

SwiftDefaultApps
========

SwiftDefaultApps is a macOS app for viewing and changing the default applications for URL schemes and file types. It is chiefly intended to be a modern replacement for the amazing RCDefaultApp developed way back when by Carl Lindberg, which stopped working in 10.12 due to deprecation of ObjC Garbage collection.
Additionally, I guess it was a good way to teach myself Swift.

Feel free to contribute, comment or report issues at https://github.com/Lord-Kamina/SwiftDefaultApps.

## Installing & Uninstalling

* There is no download of the standalone app yet (it is listed under [Unreleased](#unreleased) in the release notes): [build it from source](#building-from-source).
* Drag `SwiftDefaultApps.app` to Applications, then open it from Finder or Spotlight.
* To uninstall, quit SwiftDefaultApps and move the app to the Trash.

The app and the `swda` command line tool require macOS 13 or later and support both Apple Silicon and Intel Macs.

## Installing with brew

The Homebrew formula needs updating for the standalone app. Until then, install the app manually or build it from source.

## Building from source

With Xcode 15.2 or later installed:

```bash
git clone --recurse-submodules https://github.com/Lord-Kamina/SwiftDefaultApps.git
cd SwiftDefaultApps
./build.sh
```

`build.sh` builds a universal app (arm64 + x86_64), signs the embedded `ThisAppDoesNothing.app` and then the main app with hardened runtime, and verifies the signature. It uses the first `Developer ID Application` identity in your keychain, falling back to an ad-hoc signature for local use (`REQUIRE_SIGNING=1` makes that an error instead, and so does a `SIGN_ID` that is not in the keychain). A signature that does not verify stops the script before anything is installed. Before installing into `~/Applications`, it quits a running SwiftDefaultApps instance and moves any previously installed copy to `backups/`.

```
./build.sh                 build, sign, install
./build.sh --no-install    build and sign only
./build.sh --cli           also build the swda command line tool

SIGN_ID="-"                force an ad-hoc signature
REQUIRE_SIGNING=1          fail instead of falling back to an ad-hoc signature
ARCH="arm64"               narrow the build (default: universal)
DEPLOY_TARGET="13.0"       minimum macOS version
```

A build you make yourself and run on the same Mac is not quarantined, so Gatekeeper does not check it. An app you copy to another Mac by download is quarantined, and a build signed ad hoc and not notarized is refused there until you allow it in System Settings → Privacy & Security. `build.sh` signs with the hardened runtime but does not notarize, which takes an Apple Developer ID account and `xcrun notarytool`.

The app is built at `build/Release/SwiftDefaultApps.app`; with `--cli`, the command line tool is built at `build/Release/swda` and signed too. The whole output of `xcodebuild` is in `build/build.log`; the script shows the warnings and, if the build fails, the errors. You can also open `SwiftDefaultApps.xcworkspace` or `SwiftDefaultApps.xcodeproj` in Xcode and run the **Build App** scheme.

The CLI dependency is the Git submodule at `Packages/SwiftCLI-2.0.3`, at the commit this repository records (one commit after tag `2.0.3+swift5`; tag `2.0.3` itself is Swift 3 code and fails to compile). If you cloned without `--recurse-submodules`, `build.sh` runs `git submodule update --init` for you, and stops when the submodule is at some other commit.

### App UI

Use the segmented picker in the window toolbar to switch between Internet, URL Schemes, File Types and Applications. The resizable window has a searchable list on the left and the selected item's handlers on the right. Closing the window quits the app; **About SwiftDefaultApps** is in the app menu.

Search matches names, identifiers, bundle IDs and file extensions (type `.md` on the File Types tab to find Markdown), and ↑/↓ move through the results without leaving the search field. File Types can be grouped by kind or by the application that currently opens them; click a group header to collapse it, Option-click to collapse or expand every group. The sidebar is an `NSOutlineView`, so lists with thousands of types stay responsive.

The Applications tab lists every scheme and type an application declares. Launch Services cannot clear a default, only replace it, so rows the application already owns offer a menu to hand them to another application, and the other rows offer "Make Default".

macOS can ask you to confirm a change, such as the default web browser. For a URL scheme, or for the **Open With** picker, the app shows a waiting indicator until you answer. If you cancel, that is not reported as an error and the picker goes back to what it was; if nothing has happened after two minutes, the app reports that it timed out. (If a confirmation is still on screen then and you answer it later, the change happens, but the app shows it only once you select the item again.) The Viewer, Editor and Shell pickers change one role with a function that answers at once, so for those the app watches for the new handler for up to three seconds (until you have answered, if a confirmation appears). After a change that macOS reported as done, the app reads the handler back, and says so if it is not the one you chose.

### How it works with macOS

- Reading and changing the default application for a URL scheme, or for a file type when the role is All (the **Open With** picker in the app, and `swda` without `--role`), use `NSWorkspace`: `urlForApplication(toOpen:)`, `urlsForApplications(toOpen:)` and `setDefaultApplication(at:…)`. They replace the deprecated scheme getters `LSCopyDefaultHandlerForURLScheme` and `LSCopyAllHandlersForURLScheme`, the scheme setter `LSSetDefaultHandlerForURLScheme`, which Apple has marked as to be deprecated, and, for All roles, the per-role functions. They answer for whatever opens the file, so they know no roles.
- The **Viewer**, **Editor** and **Shell** pickers (and `swda --role Viewer|Editor|Shell`) have no replacement. They use `LSCopyDefaultRoleHandlerForContentType`, `LSCopyAllRoleHandlersForContentType` and `LSSetDefaultRoleHandlerForContentType`, which Apple has marked as to be deprecated. `LSLegacyRoles.swift` is the only file that names them, and it looks them up at run time. They answer at once, so a change of one role does not wait for a confirmation. If a later macOS removes them, the app offers only the **Open With** picker and `swda` refuses `--role Viewer|Editor|Shell`. Set `SWDA_NO_LEGACY_ROLES=1` to see that today.
- No public API lists every URL scheme, application or declared file type, so the lists in the app and `swda getSchemes`, `getApps` and `getUTIs` use three private functions: `_LSCopySchemesAndHandlerURLs`, `_LSCopyAllApplicationURLs` and `_UTCopyDeclaredTypeIdentifiers`. `LSPrivate.swift` is the only file that names them, and it looks them up at run time too. If one is missing, `swda` says that it could not generate the list, and the app shows an empty list and an alert.
- The reason for looking functions up at run time: a program built for macOS 12 or later binds every function it links when it starts, and is stopped there if one has been removed from the system, even if it never calls it.

Two environment variables are for tests and for checking what a program would do: `SWDA_READ_ONLY=1` makes every change of a default and every registration of an application fail as if macOS had refused it, and `SWDA_NO_LEGACY_ROLES=1` makes the program behave as if macOS no longer had the per-role functions. Both apply to the app and to `swda`.

For a URL scheme or for All roles, `swda setHandler` waits up to two minutes for you to answer a confirmation, and says so if you cancel. A single role is changed at once: `swda` reports success as soon as Launch Services accepts the request. `Tests/README.md` describes how all of this is checked, including the one script that really changes your defaults and puts back what it can.

## How to use the "Do Nothing" app

SwiftDefaultApps automatically locates the embedded **Do Nothing** app and registers it with Launch Services when it needs it. If Do Nothing is ever reported as not found, launch it once by hand. After installing with `build.sh`, run:

```bash
open "$HOME/Applications/SwiftDefaultApps.app/Contents/Resources/ThisAppDoesNothing.app"
```

If you installed into `/Applications`, use `/Applications/SwiftDefaultApps.app/Contents/Resources/ThisAppDoesNothing.app` instead.

## Usage Notes

SwiftDefaultApps lets you view and change default application associations for basically any URI Scheme and/or filetype in macOS.
The user-interface should be pretty self-explanatory; but, there are some things that might require an explanation:
	
- Selecting any URI Scheme or File type (always represented by a UTI), will give you a list of all valid applications for each LaunchServices role. This data is generated by LaunchServices itself.
  - There's two additional options: 
    - One of them is **"Do Nothing"**, what this does is register the item to be handled by an application which basically does nothing. Its only function is being able to open any URI Scheme or UTI whatsoever, printing a line to the console (specifying whatever it was that launched it) and immediately quitting. By default this application should be located in the `Resources` folder inside the app bundle; SwiftDefaultApps will, however, also look for it in the directory it is itself located in (for the CLI version) and every `Applications`folder in the computer.
    - The second is **"Other..."**, which obviously will allow you to select an application not in the list; with a caveat. In recent versions of macOS, the LaunchServices have become quite a bit smarter under the hood than they used to be. In practice, what this means is that although you can choose *any* application to handle anything, only valid associations will be preserved, as the LaunchServices is permanently looking for invalid or stale associations and removing them.
  - One final note: In the URI Schemes tab, you have the option of adding a custom URI Scheme (Removing them on demand is neither possible nor necessary, due to the same thing explained above). This options is provided for completeness' sake; you should virtually never need to use it, since Launch Services should be able to properly detect any valid URL Handlers. As a further cautionary note: If you add a custom URI Scheme when it is not needed, you may not be able to remove it except by uninstalling and reinstalling SwiftDefaultApps. Why? Because new schemes are by default associated to *"Do Nothing", which means Launch Services will always find a valid handler as long as SwiftDefaultApps is installed.

### How to Find Out File UTI

Run in your terminal the following command (replace my_song.mp3 by your file):

`mdls -name kMDItemContentType -name kMDItemContentTypeTree -name kMDItemKind my_song.mp3`

`swda` reports a failure in two ways. A usage error, or an application it cannot find, goes to standard error with exit status 1. A change that Launch Services refuses (an unknown UTI, a scheme that is not valid, a change macOS did not allow) is printed as `SwiftDefaultApps ERROR <code>: <message>` on standard output **with exit status 0**, so a script must look at the output, not only at the status.

The CLI can also resolve a filename extension to its preferred UTI:

```bash
swda getHandler --extension 3mf
swda setHandler --extension 3mf --app /Applications/YourApp.app
```

## Acknowledgments & Attributions

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for the licenses. Who wrote which file is in the Git history.

- Using jakeheis' SwiftCLI 2.0 as a base for the CLI version located inside the bundle. (https://github.com/jakeheis/SwiftCLI)
- Icon made using the following resources:
	- Brush, Ruler and Pencil designed by Freepik. (http://www.freepik.com/free-vector/background-of-back-to-school_769298.htm)
	- Magnifying glass frame designed by Balintseby / Freepik (http://www.freepik.com/free-vector/realistic-magnifying-glass_789215.htm)
	- Magnifying glass crystal designed by Freepik (http://www.freepik.com/free-vector/crystal-frames-collection_724172.htm)
	- Gears designed by Freepik (http://www.freepik.com/free-vector/gray-background-of-gear_956712.htm)

## Current Version

The app's version is `MARKETING_VERSION` in `SwiftDefaultApps.xcodeproj` (2.0.1; the release notes below start at [Unreleased](#unreleased)). `swda --version` reports its own, 1.0, which is not kept in step with it.

## Known Issues

See https://github.com/Lord-Kamina/SwiftDefaultApps/issues

## TO DO

- Localizations

# Release Notes

## [Unreleased]
  + ### Added
    + CLI: `--extension` / `--ext` for `getHandler` and `setHandler`, by huybik ([#94](https://github.com/Lord-Kamina/SwiftDefaultApps/pull/94)).
    + A `.gitignore` for Xcode user data, by barijaona ([#87](https://github.com/Lord-Kamina/SwiftDefaultApps/pull/87)).
    + `Tests/`: golden-output, logic and probe scripts, and a guarded script that really changes defaults and puts back what it can. See `Tests/README.md`.
    + `SWDA_NO_LEGACY_ROLES=1` makes the app and `swda` behave as if macOS no longer had the per-role functions.
    + `SWDA_READ_ONLY=1` makes every change of a default and every registration of an application fail as if macOS had refused it.
    + `SECURITY.md`, `CONTRIBUTING.md` and `THIRD_PARTY_NOTICES.md`; a GitHub Actions workflow that builds the three targets with warnings fatal and runs the tests.
    + An application given by name that two different applications share (Siri, or a name that only exists nested inside another application) is refused with a new error, 1001, which lists the candidates and asks for a path.
  + ### Changed
    + The preference pane is replaced by a standalone app (SwiftUI, macOS 13 or later), by ultranity ([#98](https://github.com/Lord-Kamina/SwiftDefaultApps/pull/98)).
    + Deprecated functions and methods (the Launch Services scheme functions, the `UTType…` C functions, `NSWorkspace.fullPath(forApplication:)` and others) are replaced with `NSWorkspace` and `UniformTypeIdentifiers` equivalents wherever one exists. The per-role functions and the three private ones are looked up at run time instead of being linked, so that the removal of one can no longer stop the program from launching.
    + Changing a default for a URL scheme or for All roles waits for macOS to answer, which can mean waiting for you to confirm. Canceling is reported as canceled, not as a success or a failure; `swda` waits up to two minutes. After a change the app reads the handler back, and says so if it is not the one you chose.
    + A request for All roles (the app's **Open With** picker, `swda getHandler` without `--role`, `getUTIs`) now reports what actually opens a file. On the Mac this was checked on, applications whose role for a type is "None" no longer appear in `--all` lists, and Terminal is shown for the Mach-O, X11 and shell-script types, where nothing or iTerm was shown before. `getHandler --URL file --all` lists the applications that open a file URL. `getUTIs` no longer lists `public.presentation` and `public.spreadsheet`.
    + `setHandler` refuses a UTI that macOS does not know, for every role, instead of recording a preference for it.
    + A missing Do Nothing application is now reported before anything is changed (standard error, exit status 1).
    + Do Nothing is registered with `LSRegisterURL` instead of being launched. This has not been tried on a Mac where it was not registered yet; if it is reported as not found, launch it once by hand (see [How to use the "Do Nothing" app](#how-to-use-the-do-nothing-app)).
    + An application given by display name is found by matching the registered applications' file names, because `NSWorkspace.fullPath(forApplication:)` is deprecated and has no replacement.
    + New messages for a canceled change, a change macOS did not allow and a change that timed out. An error that macOS reports and nothing here explains is logged with macOS's own description.
    + `build.sh` stops when a signature does not verify, when `SIGN_ID` is not in the keychain (or with `REQUIRE_SIGNING=1`, when there is no Developer ID), and when the build fails; it builds SwiftCLI from the Git submodule and keeps the whole log in `build/build.log`. `swda` and Do Nothing now require macOS 13, like the app.
    + `--app Safari` no longer picks whichever copy scored best: copies are ranked by whether they are outside another bundle, then by folder (the system's, then your Applications folder, then elsewhere), then by the copy Launch Services prefers, and a tie is refused. Do Nothing is accepted only from the folder it ships in or from `/Applications`, and only when its identifier, package type and executable are right.
    + `setHandler --role` with a word that is not a role is an error; it used to mean All. A scheme is checked by a fixed rule (ASCII letters, digits, `+`, `-` and `.`, starting with a letter), so `http` followed by a newline is refused and a scheme of one letter is accepted. Names and paths from the system or the command line are printed with control and bidirectional characters escaped.
    + The File Types list loads in 0.05 s instead of 3 s, and the default of every type is read only when you group by default application.
  + ### Fixed
    + `swda` crashed (exit 133) on an unrecognized option of more than 40 characters.
    + The Do Nothing helper never created its delegate, because the nib that Info.plist named had been deleted; it now installs it in code, and it logs the scheme of a URL it is asked to open and nothing more.
    + Typing `mailto` in the custom-scheme field gave `mailto` to Do Nothing; the existing scheme is selected instead. Collapsing the "No Default Application" group no longer hides the Internet, URL Schemes and Applications lists; the search field's clear button clears the list's filter; leaving a detail while macOS waits for your confirmation no longer allows a second, overlapping change; the Applications tab shows the copy Make Default acts on; types macOS does not know are not offered Make Default.
    + A crash in the error messages when no application name was available.
    + The Do Nothing application no longer treats the URL it was started for as a format string when logging it.
    + Typo "succesfully" in the success message ([#21](https://github.com/Lord-Kamina/SwiftDefaultApps/issues/21)).

## [2.0.1] - 2019-07-26
  + ### Fixed
  	+ CLI: Crash when displaying the results for setHandler with shortcuts such as internet, browser, email, etc.

## [2.0.0] - 2019-06-12
  + ### Added
    + Signed prefpane, CLI and Dummy apps.
    + Both the prefpane and the CLI version will now automatically try to locate ThisAppDoesNothing.app if it does not appear registered with launch services.
  + ### Changed
    + SwiftCLI is now built and linked as a static library instead of a framework.
    + Updated to Swift 5
    + The content array is now populated by overriding `didSelect()` instead of relying on an arbitrary sleep timer.
    + Changed the CLI app's name from lsreg to swda.
    + Messages in both the CLI and Preference Pane are now a bit more verbose.
    + Under the hood, folded most of the app's feedback to the user into a single `displayAlert()` function.
  + ### Fixed
  	+ Updated the Swift Package Manager manifest to version 5.
  	+ Updated the SynchronizedArray code and corrected the attribution; Before, I had inadvertently credited an unrelated project with the same name.
  	+ Various small optimizations, fixes and text corrections.

## [1.1.3] - 2018-11-15
  + ### Fixed
  	+ Bug causing crash on related to force-unwrapping bundleIdentifier.

## [1.1.2] - 2018-10-07
  + ### Changed
  	+ Migrated to Swift 4.2
  	+ Force Static linking of standard library, which should fix issues running on Mojave.

## [1.1.1] - 2018-04-15
  + ### Changed
  	+ Small changes for Swift 4.1.

## [1.1.0] - 2017-09-27
  + ### Changed
  	+ Migrated code to Swift 4.
  + ### Fixed
  	+ Fixed an unwrapped Optional when changing associations in the "Applications" tab.
  	+ Fixed CLI tool.
  	+ Some other cleanups.

## [1.0.0] - 2017-05-01
  + ### Added
    + Initial release!
  + ### Changed
  + ### Fixed
