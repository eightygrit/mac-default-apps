# Security

## Reporting a problem

Please report a vulnerability privately, not in a public issue: on GitHub, use **Security → Report a vulnerability** on this
repository. If that button is not there, open an issue that says only that you have a security report and how you would like
to send it, and leave the details out.

Say which program is affected (the app, `swda`, or the Do Nothing helper), the macOS version, and the steps to reproduce.

## What these programs do

- What they are for is reading and changing the default applications that Launch Services records for URL schemes and file
  types, and registering the Do Nothing helper with Launch Services. They change nothing else of your system.
- They do not use the network. `Tests/check-artifacts.sh` checks that a built program links no networking framework.
- The app and `swda` ask Launch Services to make a change; macOS can ask you to confirm it. They do not bypass that
  confirmation.
- Do Nothing is only ever taken from the folder the program ships it in or from `/Applications`, and only when its bundle
  identifier, package type and executable are the ones it should have. An application named on the command line is chosen
  among the registered applications by a fixed order (system folders, then your Applications folder, then elsewhere), and a name
  that two different applications share is refused instead of guessed at.
- Names and paths that come from the system or from the command line are printed with control and bidirectional characters
  escaped, so that an application name cannot write to your terminal.
- `SWDA_READ_ONLY=1` makes every change and every registration fail as if macOS had refused it. The test scripts set it.

## What to expect

The latest commit of the default branch is the only supported version. Builds you make yourself are signed ad hoc unless you
give `build.sh` a Developer ID; they are not notarized (see the README).
