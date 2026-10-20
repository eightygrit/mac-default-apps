# Contributing

## Build and test

Build with `./build.sh --no-install` (see the README), or one target at a time outside the repository with
`Tests/build-scratch.sh`. Before you send a change, run what `Tests/README.md` lists; the quick ones are:

```bash
Tests/logic/run.sh        # the shared sources
Tests/model/run.sh        # the app's model, without a window
Tests/mutations.sh        # breaks the sources on purpose; every break must make a test fail
```

and, with a built `swda`, `Tests/contract.sh`, `Tests/legacy-roles-off.sh` and `Tests/check-artifacts.sh`. A change to what
`swda` prints is a change to the golden recordings: say so in the commit, and re-record them on purpose.

## Tests must not change your defaults

Nothing in `Tests/` may reach a function that really writes a default handler or registers an application, except
`Tests/write-roundtrip.sh --i-understand`, which says so and asks. A new check of a setter passes it a stand-in
(`LSWrappers.HandlerSetter`, `Catalog.HandlerAccess`); the scripts export `SWDA_READ_ONLY=1`, and refuse a check that calls a
setter without a stand-in. Launch Services records a type nobody declared and an application nobody installed without
complaint, so "it names something that does not exist" is no protection.

## Names and spelling

- One concept, one word, in code, in the UI, in the documentation and in commit messages. Before you name a state, an action
  or a thing, search for what the code already calls it and use that exact word. The words in use include *handler* (the
  application that opens a scheme or a type), *role* (All, Viewer, Editor, Shell), *scheme*, *UTI* (the app's window calls the
  list File Types), and *Do Nothing*.
- A word that is taken may not be borrowed for a second meaning, not even with a qualifier. Rename the newcomer.
- Where a value has an enum, the enum owns its label, its color and its order; a view or a service does not spell them again.
- One method name for one job across sibling types, and no `get` prefix on a computed answer. (`getHandler` and the other
  command names of `swda` are its interface and stay.)
- Retiring a word means removing it in the same change, not leaving both.
- Write U.S. English: canceled, color, behavior, analyze, catalog, license. An identifier or stored value that already exists
  keeps the spelling it has (Apple's `NSUserCancelledError` stays as Apple wrote it), and is not renamed just to fix the spelling.

## Commits

One change per commit, with a message that says why. Output that changes on purpose (what `swda` prints, what the app shows)
is named in the message. Keep a pull request to what it says it does.
