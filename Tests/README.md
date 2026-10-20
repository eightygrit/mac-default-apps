# Tests

How the SwiftDefaultApps sources are checked. Nothing here is an Xcode target: every check is a shell script,
and the ones that compile Swift call `swiftc` directly (a test target would mean hand-editing two project files).

| Script | What it checks | Can it change your default handlers? |
|---|---|---|
| [`golden.sh`](golden.sh) | the CLI's output, error text and exit status in 368 cases, compared build against build | no |
| [`contract.sh`](contract.sh) `<swda>` | the 25 of those cases that read the same on every Mac, compared with the recordings in [`contract/`](contract) | no |
| [`logic/run.sh`](logic/run.sh) | the shared sources: error codes and messages, which application an input means, planted look-alikes, what each setter asks the system for, refusals, helpers | no (reads Launch Services only; a stand-in replaces the calls that write) |
| [`model/run.sh`](model/run.sh) | the app's model, without a window: grouping and collapsing, the custom-scheme field, and the one place a default is changed (what is refused, shown while it waits, said when it did not take effect) | no (every change goes through a stand-in) |
| [`mutations.sh`](mutations.sh) | that the logic and model tests notice 47 deliberate breaks (a role widened, a guard dropped, a look-alike ranked first, a collapsed group hiding another list); `mutations.sh 37` runs one row | no (works in a scratch copy) |
| [`perf/run.sh`](perf/run.sh) `[rounds]` | how long each list of the app takes to load (File Types: 3 s before the types were made on the main thread, 0.05 s after); numbers depend on the Mac | no |
| [`check-artifacts.sh`](check-artifacts.sh) `<program>...` | what the built programs link to: no deprecated or private Launch Services function, no networking | no |
| [`probe/run.sh`](probe/run.sh) `<name>` | facts about macOS the design rests on, mostly old calls against new ones | no |
| [`probe/fixups.sh`](probe/fixups.sh) | why private and legacy symbols are looked up with `dlsym` | no |
| [`build-scratch.sh`](build-scratch.sh) | builds one target outside the repository and counts compiler warnings | no |
| [`legacy-roles-off.sh`](legacy-roles-off.sh) `<swda>` | the CLI with the per-role functions switched off (`SWDA_NO_LEGACY_ROLES=1`): `--role Viewer\|Editor\|Shell` is refused, everything else answers as before | no; it stops at once if the binary ignores the switch |
| [`write-roundtrip.sh`](write-roundtrip.sh) | real writes: set, read back, restore | **yes**, guarded |

## Golden output

`golden.sh` runs the CLI over a fixed matrix and writes one file per case holding the command line, stdout, stderr
and exit status. The matrix: the `get*` commands; `getHandler` for 18 UTIs, each with 7 `--role` variants (one is
no `--role`) and with `--all`; 15 URL schemes; every shortcut flag; the option-parser contract; `--extension`; and `setHandler`
invocations that fail before they reach Launch Services (unresolvable application, malformed scheme, missing
option). Lists whose order is not part of the contract are sorted.

Compare a change with the build before it. Record **both** back to back, because Launch Services drifts: building or
installing an application registers it, and registering `ThisAppDoesNothing.app` adds it as a handler for
`public.item` and for the `*` scheme, which changes several cases. Build the reference in a worktree of its own, so that
your checkout and its uncommitted work stay as they are (the reference needs `build-scratch.sh`, so it cannot be older
than that script):

```bash
git worktree add --detach /tmp/swda-ref-src <reference commit>
git -C /tmp/swda-ref-src submodule update --init
/tmp/swda-ref-src/Tests/build-scratch.sh cli /tmp/swda-ref
Tests/build-scratch.sh cli /tmp/swda-new
Tests/golden.sh /tmp/swda-ref/products/Release/swda /tmp/golden-ref
Tests/golden.sh /tmp/swda-new/products/Release/swda /tmp/golden-new
diff -ru /tmp/golden-ref /tmp/golden-new
git worktree remove --force /tmp/swda-ref-src
```

Two runs of one build, back to back, must produce no differences at all. The recordings contain your installed
applications, so they are never committed, with one exception: the 25 cases that name nothing installed here (help
and usage text, refusals of a missing application or a malformed scheme or role) are the same on every Mac. They are
kept in `contract/`, and `contract.sh <swda>` fails when the output of a build differs from them. A change of output
made on purpose is recorded with `contract.sh <swda> --record`, in the same commit as the change.

## Logic tests

```bash
Tests/logic/run.sh               # failures and a summary
VERBOSE=1 Tests/logic/run.sh     # every check
```

`logic/main.swift` is compiled together with `Sources/Common Sources`, the code the app and the CLI share. It only
reads Launch Services. The checks of the setters ask for an application that does not exist, or a type that does not
exist (or, where a real type is needed so that the application is what gets refused, one nobody depends on), so the
code under test has to refuse them; the comment above those checks says what could change were a refusal ever skipped.
When behavior changes on purpose, change the expected value in the same commit as the code.

`SWDA_READ_ONLY=1` makes every change of a default handler, and every registration of an application, fail as if macOS
had not allowed it (`LSWrappers.isReadOnly`). `logic/run.sh`, `mutations.sh` and `golden.sh` set it, and `logic/run.sh`
refuses to run if a check calls a setter without a stand-in of its own. This is not a precaution on paper: a mutation
run once wrote three real entries (`public.data` for all roles, and two for types and an application that do not exist)
because the older checks trusted a guard to refuse first. `LSSetDefaultRoleHandlerForContentType` records a UTI nobody
declared and an application nobody installed without complaint, so "it names something that does not exist" protects
nothing.

Three things keep the checks of the writing code honest. The setters take the three calls that change a default
(`LSWrappers.HandlerSetter`), so a check passes a stand-in that records what it is asked, and nothing it does can write a
default. The checks of look-alikes plant application bundles in a temporary directory and rank them with the same
function the program uses. And `mutations.sh` breaks the sources on purpose, one way at a time, in a scratch copy: every
break has to make the logic tests fail, so a check that stops guarding anything shows up as a survivor. Add a row to its
table when a new rule is worth protecting.

## Model tests

```bash
Tests/model/run.sh               # failures and a summary
VERBOSE=1 Tests/model/run.sh     # every check
```

`model/main.swift` compiles the app's `AppModel` and `Catalog` with the shared sources, without the views or a window. The
model takes the four things it asks of the system (`Catalog.HandlerAccess`: change a default, wait until it took effect, read it
again, read the defaults of all the types) as a parameter, so the checks pass a stand-in that answers as told and can hold a change open: that is
how "a second change is refused while the first waits" and "a reading that began before a change is dropped" are checked. The
views are not compiled; what they show is a function of the model, and what they do with a click is one call of it.

## Without the per-role functions

The three functions that read and write the handler of one role (`LSLegacyRoles.swift`) are the part of the design
Apple is most likely to remove. `SWDA_NO_LEGACY_ROLES=1` makes the program behave as if it had: the lookups fail, the
app shows "All Roles" only, and the CLI refuses `--role Viewer|Editor|Shell` with
"Per-role defaults are not available on this version of macOS." `legacy-roles-off.sh <swda>` runs the CLI both ways
and checks that nothing which asks for All roles changes. It writes nothing. A binary that ignores the switch (one
built before it existed) would carry out the `setHandler` calls, so the script first proves with reads that the binary
honors it and stops otherwise; the calls name an application that does not exist, so even then they would fail; and
with the switch set the role-setting function cannot be found anyway.

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
builds can be compared with `diff`; `FAIL_ON_WARNINGS=1` turns any warning into a failure, as the CI does. Unlike
`build.sh` it does not sign, install or back anything up.

## CI

[`.github/workflows/ci.yml`](../.github/workflows/ci.yml) runs, on every push and pull request, the logic tests, the
mutation check, the model tests, the three scratch builds with warnings fatal, `check-artifacts.sh` on what they built, `contract.sh`
and `legacy-roles-off.sh`. It never writes a default handler. Everything in it can be run locally with the commands above.

## Writes (guarded)

`write-roundtrip.sh` changes real default handlers and puts back what it can. Without `--i-understand` it only
chooses its subjects and prints the plan. Run it while you are at the machine: macOS may ask you to confirm in a prompt,
and the `cancel` case needs you to answer "no". Every case but two sets a handler, reads it back, checks that the change
stays for five seconds, restores the original and reads that back; a trap restores whatever is still changed if you
interrupt it. The two exceptions: `cancel` is meant to change nothing, and `unknown-extension` cannot be undone (the
handler it sets applies only to files named `*.swdatestext`). A change for All roles cannot restore each role
separately, and the script says so when they differ afterwards. It never uses `http`, `https`, `ftp`, `file`, `mailto`,
a few other schemes or `public.html`.

```bash
Tests/write-roundtrip.sh /tmp/swda-cli/products/Release/swda                    # plan only
Tests/write-roundtrip.sh --i-understand /tmp/swda-cli/products/Release/swda     # run everything
Tests/write-roundtrip.sh --i-understand /tmp/swda-cli/products/Release/swda scheme uti
```

The cases and the environment variables that override its choices are described at the top of the script.
