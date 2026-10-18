# Tests

How the SwiftDefaultApps sources are checked. Nothing here is an Xcode target: every check is a shell script,
and the ones that compile Swift call `swiftc` directly (a test target would mean hand-editing two project files).

| Script | What it checks | Can it change your default handlers? |
|---|---|---|
| [`golden.sh`](golden.sh) | the CLI's output, error text and exit status in 365 cases | no |
| [`logic/run.sh`](logic/run.sh) | the shared sources: error codes and messages, which application an input means, refusals, helpers | no (reads Launch Services only) |
| [`probe/run.sh`](probe/run.sh) `<name>` | facts about macOS the design rests on, mostly old calls against new ones | no |
| [`probe/fixups.sh`](probe/fixups.sh) | why private and legacy symbols are looked up with `dlsym` | no |
| [`build-scratch.sh`](build-scratch.sh) | builds one target outside the repository and counts compiler warnings | no |
| [`legacy-roles-off.sh`](legacy-roles-off.sh) `<swda>` | the CLI with the per-role functions switched off (`SWDA_NO_LEGACY_ROLES=1`): `--role Viewer\|Editor\|Shell` is refused, everything else answers as before | no |
| [`write-roundtrip.sh`](write-roundtrip.sh) | real writes: set, read back, restore | **yes**, guarded |

## Golden output

`golden.sh` runs the CLI over a fixed matrix and writes one file per case holding the command line, stdout, stderr
and exit status. The matrix: the `get*` commands; `getHandler` for 18 UTIs, each with 7 `--role` variants (one is
no `--role`) and with `--all`; 15 URL schemes; every shortcut flag; the option-parser contract; `--extension`; and `setHandler`
invocations that fail before they reach Launch Services (unresolvable application, malformed scheme, missing
option). Lists whose order is not part of the contract are sorted.

Compare a change with the build before it. Record **both** back to back, because Launch Services drifts: building or
installing an application registers it, and registering `ThisAppDoesNothing.app` adds it as a handler for
`public.item` and for the `*` scheme, which changes several cases.

```bash
git switch <reference commit>; Tests/build-scratch.sh cli /tmp/swda-ref
git switch <candidate>;        Tests/build-scratch.sh cli /tmp/swda-new
Tests/golden.sh /tmp/swda-ref/products/Release/swda /tmp/golden-ref
Tests/golden.sh /tmp/swda-new/products/Release/swda /tmp/golden-new
diff -ru /tmp/golden-ref /tmp/golden-new
```

Two runs of one build, back to back, must produce no differences at all. The recordings contain your installed
applications, so they are never committed.

## Logic tests

```bash
Tests/logic/run.sh               # failures and a summary
VERBOSE=1 Tests/logic/run.sh     # every check
```

`logic/main.swift` is compiled together with `Sources/Common Sources`, the code the app and the CLI share. It only
reads Launch Services; the setter checks use applications that do not exist, so nothing is ever written. When
behavior changes on purpose, change the expected value in the same commit as the code.

## Without the per-role functions

The three functions that read and write the handler of one role (`LSLegacyRoles.swift`) are the part of the design
Apple is most likely to remove. `SWDA_NO_LEGACY_ROLES=1` makes the program behave as if it had: the lookups fail, the
app shows "All Roles" only, and the CLI refuses `--role Viewer|Editor|Shell` with
"Per-role defaults are not available on this version of macOS." `legacy-roles-off.sh <swda>` runs the CLI both ways
and checks that nothing which names no role changes. It writes nothing: the refused `setHandler` calls stop in the CLI,
and with the switch set the role-setting function cannot be found anyway.

## Probes

`probe/run.sh <name>` compiles `probe/<name>.swift` and runs it. Probes read only. The old calls are used on purpose,
so compiling them prints deprecation warnings (hidden unless the compile fails). `probe/run.sh --list` lists them.

| Probe | Question | Answer, macOS 15.8.1 (October 2026), 1,319 listed UTIs |
|---|---|---|
| `roles` | Which legacy role mask do the new `NSWorkspace` getters answer? | The mask viewer+editor+shell, exactly: defaults agree on 1,006 of 1,006 UTIs that have one, handler lists are equal on 1,319 of 1,319. Against the all-roles mask 998 agree, 8 differ and 7 come back empty (applications whose role is "None"); against Viewer alone only 497 agree. About a minute. |
| `declared` | Can per-role lists be rebuilt from `urlsForApplications(toOpen:)` and each app's `CFBundleTypeRole`? | No: they match the legacy lists for 751 (Viewer), 961 (Editor) and 1,303 (Shell) UTIs. Explicit roles therefore stay on the legacy calls. |
| `dups` | Which bundle IDs does the new list repeat? | 334 lists repeat one (Sublime Text three times, Vivaldi twice with a Sparkle staging copy in `~/Library/Caches`). Readers dedupe by bundle ID and resolve through `urlForApplication(withBundleIdentifier:)`. |
| `utt` | Do the deprecated `UTType` C functions and `UniformTypeIdentifiers.UTType` agree? | Descriptions, extension lists and `isDynamic` agree everywhere. The `public.item`/`public.content` filter differs for 2 of 2,685 declared types (`public.presentation`, `public.spreadsheet`). |
| `extension` | What does `--extension` (PR #94) resolve to, and what does a real file get? | `UTType(tag:tagClass:conformingTo: nil)` equals the old call for 1,252 of 1,254 extensions; `UTType(filenameExtension:)` differs for 173 (it conforms to `.data`). For an unknown extension the old call gives `dyn.age8…` but a real file is typed `dyn.ah62d4rv4ge8…`. |
| `spi-fallback` | How much of the private enumerations can public API recover? | 416 of 525 applications, 253 of 278 URL schemes, 1,098 of 1,319 UTIs. The private calls stay, behind `dlsym`. |
| `dlsym` | Are the private and legacy symbols reachable through `dlsym`? | All six (the three private functions and the three per-role ones), under their exact C names; the made-up one is not. |
| `openswith` | Which application opens this file, and what type is it? | Prints a line per file; used by `write-roundtrip.sh`. |

The digits move with the installed applications (registering one more application can shift a count by several);
the shape of each answer does not.

`probe/fixups.sh` reproduces the failure the `dlsym` lookups guard against. At a deployment target of macOS 12 or
later the linker binds every symbol when the program launches. A symbol that a later macOS removes from a system
library then kills a program that merely links it ("Symbol not found", exit 134) even if it never calls it. The script
builds a tiny dylib in two versions and shows a directly linked program aborting while a `dlsym` one carries on.

## Building without touching anything else

```bash
Tests/build-scratch.sh cli   /tmp/swda-cli     # → /tmp/swda-cli/products/Release/swda
Tests/build-scratch.sh app   /tmp/swda-app     # deployment target 13.0
Tests/build-scratch.sh dummy /tmp/swda-dummy   # ThisAppDoesNothing.app
```

It prints the result and the number of distinct compiler warnings, and keeps them in `diagnostics.txt` so two
builds can be compared with `diff`. Unlike `build.sh` it does not sign, install or back anything up.

## Writes (guarded)

`write-roundtrip.sh` changes real default handlers and puts them back. Without `--i-understand` it only chooses
its subjects and prints the plan. Run it while you are at the machine: macOS may ask you to confirm in a prompt, and the
`decline` case needs you to answer "no". Every case sets a handler, reads it back, checks that the change stays
for five seconds, restores the original and reads that back; a trap restores whatever is still changed if you
interrupt it. It never touches `http`, `https`, `ftp`, `file`, `mailto` or `public.html`.

```bash
Tests/write-roundtrip.sh /tmp/swda-cli/products/Release/swda                    # plan only
Tests/write-roundtrip.sh --i-understand /tmp/swda-cli/products/Release/swda     # run everything
Tests/write-roundtrip.sh --i-understand /tmp/swda-cli/products/Release/swda scheme uti
```

The cases and the environment variables that override its choices are described at the top of the script.
