#!/usr/bin/env bash
# Checks that the tests notice the mistakes that matter: it breaks the shared sources and the app's model on purpose, one way at a
# time, in a scratch copy, and every break must make the suite that guards it (Tests/logic or Tests/model) fail. A mutation the
# tests survive means a check is missing.
#
# usage: Tests/mutations.sh      exit status 1 if any mutation survives, or if the unchanged sources do not pass
#
# The repository is never touched. Add a row to the table when a new rule is worth protecting; a row says which suite, which file,
# the exact text to replace (it must occur), what to put there, and what the break stands for.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# A mutation removes a guard on purpose, and the tests that follow it must not be able to write a default handler for real
# when it does: every check gives the setters a stand-in (the same grep as Tests/logic/run.sh refuses a call that does not),
# and SWDA_READ_ONLY makes the code itself refuse to write. Once, a mutation run without these changed three real defaults.
export SWDA_READ_ONLY=1
if grep -nE 'setDefaultHandler\(|ensureRegistered\(' "$here/logic/main.swift" | grep -vE 'setter:|register:|real call, guarded'; then
	echo "Tests/logic/main.swift: a call above has no stand-in; no mutation was run." >&2
	exit 2
fi
if grep -nE 'AppModel\(' "$here/model/main.swift" | grep -v 'access:'; then
	echo "Tests/model/main.swift: a model above has no stand-in for the system; no mutation was run." >&2
	exit 2
fi
if grep -nE 'Catalog\.setDefault\(|Catalog\.settledDefault\(' "$here/model/main.swift" | grep -v 'real call, guarded'; then
	echo "Tests/model/main.swift: a call above reaches the system and is not marked as guarded; no mutation was run." >&2
	exit 2
fi

exec python3 -I - "$repo" "$work" <<'PYTHON'
import os, shutil, subprocess, sys

repo, work = sys.argv[1], sys.argv[2]
common = os.path.join(repo, "Sources", "Common Sources")
model = os.path.join(repo, "Sources", "App Sources", "Model")
support = os.path.join(repo, "Tests", "support", "checks.swift")
SUITES = {
    "logic": {"main": os.path.join(repo, "Tests", "logic", "main.swift"), "copy": {"common": common}},
    "model": {"main": os.path.join(repo, "Tests", "model", "main.swift"), "copy": {"common": common, "model": model}},
}

# (suite, file, text to replace, replacement, what the break stands for); the file is "common/..." or "model/..."
MUTATIONS = [
    ("logic", "common/LSWrappers.swift", "if LSLegacyRoles.isAllRoles(inRoles) {", "if true {",
     "a request for one role is widened to every role"),
    ("logic", "common/LSWrappers.swift", "let status = setter.forRoles(inContent, inRoles, inApp.bundleID)", "let status = setter.forRoles(inContent, .all, inApp.bundleID)",
     "the per-role call is made for every role"),
    ("logic", "common/LSWrappers.swift", "setter.forUTI(inApp.url, type) {", "setter.forRoles(inContent, .viewer, inApp.bundleID); setter.forUTI(inApp.url, type) {",
     "a request for all roles also writes one role"),
    ("logic", "common/LSWrappers.swift", "guard isValidScheme(inScheme) else { completion(.failure(.invalidScheme)); return }", "",
     "a malformed scheme is written"),
    ("logic", "common/LSWrappers.swift", "guard let type = UTType(inContent) else { completion(.failure(.unknownUTI)); return }", "let type = UTType(inContent) ?? .data",
     "a UTI nobody declared is written"),
    ("logic", "common/LSWrappers.swift", "guard LSWrappers.ensureRegistered(inApp) else { completion(.failure(.appNotFound)); return }\n\t\t\tif LSLegacyRoles", "if LSLegacyRoles",
     "an application that is not installed is assigned to a UTI"),
    ("logic", "common/LSWrappers.swift", "guard LSWrappers.ensureRegistered(inApp) else { completion(.failure(.appNotFound)); return }\n\t\t\tsetter.forScheme", "setter.forScheme",
     "an application that is not installed is assigned to a scheme"),
    ("logic", "common/LSWrappers.swift", "guard DoNothingApp.isGenuine(app.url) else { return false }", "",
     "any bundle with Do Nothing's identifier is registered on demand"),
    ("logic", "common/LSWrappers.swift", "{ self = .system }", "{ self = .user }",
     "a copy in the user's Applications folder ties with the system's"),
    ("logic", "common/LSWrappers.swift", "else if !mine.isEmpty && real.hasPrefix(mine + \"/\") { self = .user }", "else if !mine.isEmpty && real.hasPrefix(mine + \"/\") { self = .system }",
     "a copy in the user's Applications folder counts as the system's"),
    ("logic", "common/LSWrappers.swift", "if real.hasPrefix(\"/System/Volumes/Data/\") {", "if false {",
     "the data volume's mount point counts as the system"),
    ("logic", "common/LSWrappers.swift", "return (isNested ? 1 : 0, location, isPreferred ? 0 : 1)", "return (0, location, isPreferred ? 0 : 1)",
     "a copy nested inside another application ranks like one outside"),
    ("logic", "common/LSWrappers.swift", "guard let best = ranked.map(\\.rank).min(by: { $0 < $1 }) else { return [] }\n\t\treturn ranked.filter { $0.rank == best }.map(\\.path)", "return ranked.sorted { $0.path.count < $1.path.count }.prefix(1).map(\\.path)",
     "the shortest path decides a tie between different applications"),
    ("logic", "common/LSWrappers.swift", "guard text.contains(\".\"), ", "guard ",
     "a plain name is looked up as a bundle identifier"),
    ("logic", "common/LSWrappers.swift", "return .success(ResolvedApp(url: url, bundleID: Bundle(url: url)?.bundleIdentifier ?? inParam))", "return .success(ResolvedApp(url: url, bundleID: inParam))",
     "the resolved application carries the spelling that was typed"),
    ("logic", "common/LSWrappers.swift", "if appPaths.count > 1 { return .failure(.ambiguousApp) }", "",
     "an ambiguous name is resolved by guessing"),
    ("logic", "common/LSWrappers.swift", "let app = displayable(raw), content = displayable(argument.content ?? String())", "let app = raw, content = argument.content ?? String()",
     "what was typed is printed with its control characters"),
    ("logic", "common/LSWrappers.swift", "known != .noError, known != .ambiguousApp {", "known != .noError {",
     "a status of the system's can be mistaken for an ambiguous name"),
    ("logic", "common/DoNothingApp.swift", "return (allowed ?? homes).contains { $0.resolvingSymlinksInPath().path == folder }", "return true",
     "a copy of Do Nothing is accepted from any folder"),
    ("logic", "common/DoNothingApp.swift", "bundle.bundleIdentifier == bundleID,", "",
     "any application is accepted as Do Nothing"),
    ("logic", "common/commonFuncs.swift", "first.isASCII, first.properties.isAlphabetic", "first.isASCII",
     "a scheme can start with a digit"),
    ("logic", "common/commonFuncs.swift", "scalar.isASCII && (", "(",
     "a scheme can hold letters outside ASCII"),
    ("logic", "common/LSWrappers.swift", "if LSWrappers.isReadOnly { return .refusing }", "",
     "the system's setter ignores the read-only switch"),
    ("logic", "common/LSLegacyRoles.swift", "return roles == .all || roles.isSuperset(of: [.viewer, .editor, .shell])", "return roles == .all",
     "all three roles together are treated as a per-role request"),
    ("logic", "common/LSLegacyRoles.swift", 'case "viewer": return .viewer', 'case "viewer": return .all',
     "the word Viewer means every role"),
    ("model", "model/AppModel.swift", "section.title != nil && collapsed.contains(collapseKey(section.id))", "collapsed.contains(collapseKey(section.id))",
     "a group collapsed in one list hides the whole of an ungrouped one"),
    ("model", "model/AppModel.swift", "guard !changing.contains(content) else { return .ignored }", "",
     "a second change of a scheme or type is asked for while the first waits"),
    ("model", "model/AppModel.swift", "if let existing = known.first(where: { $0.id.lowercased() == scheme }) {", "if false, let existing = known.first(where: { $0.id.lowercased() == scheme }) {",
     "typing a scheme that exists gives it to Do Nothing"),
    ("model", "model/AppModel.swift", "text.trimmingCharacters(in: .whitespaces).lowercased()", "text.trimmingCharacters(in: .whitespaces)",
     "a scheme is not folded to lowercase"),
    ("model", "model/AppModel.swift", "guard generations[content, default: 0] == generation else { return }", "",
     "a reading that began before a change replaces what the change read"),
    ("model", "model/AppModel.swift", "if key == DoNothingApp.bundleID.lowercased() {", "if false {",
     "Do Nothing's group is titled with a lowercased identifier"),
    ("model", "model/AppModel.swift", "if prompted { outcome = .canceled } else {", "if false {",
     "a declined confirmation is reported as a failure"),
    ("model", "model/AppModel.swift", "defer { changing.remove(content) }", "",
     "a scheme or type stays waiting after its change ended"),
    ("model", "model/Catalog.swift", "return listed.first { path($0).map { same($0, resolved) } ?? false } ?? listed[0]", "return listed[0]",
     "the Applications tab shows the first copy listed, not the one that is resolved"),
    ("model", "model/Catalog.swift", "choice.url?.path ?? choice.bundleID", "choice.bundleID",
     "a file chosen with Other... is looked up again by its identifier"),
]

def build_and_run(directory, suite):
    binary = os.path.join(directory, "suite")
    files = sorted(os.path.join(directory, folder, name) for folder in SUITES[suite]["copy"]
                   for name in os.listdir(os.path.join(directory, folder)) if name.endswith(".swift"))
    compiled = subprocess.run(["swiftc", "-swift-version", "5", "-module-name", "SwdaMutationTests", "-o", binary,
                               os.path.join(directory, "main.swift"), os.path.join(directory, "checks.swift")] + files,
                              capture_output=True, text=True)
    if compiled.returncode != 0:
        return "did not compile"
    ran = subprocess.run([binary], capture_output=True, text=True)
    return "failed" if ran.returncode != 0 else "passed"

def fresh(directory, suite):
    shutil.rmtree(directory, ignore_errors=True)
    os.makedirs(directory)
    for folder, source in SUITES[suite]["copy"].items():
        shutil.copytree(source, os.path.join(directory, folder))
    shutil.copy(SUITES[suite]["main"], os.path.join(directory, "main.swift"))
    shutil.copy(support, os.path.join(directory, "checks.swift"))

for suite in SUITES:
    baseline = os.path.join(work, "baseline-" + suite)
    fresh(baseline, suite)
    state = build_and_run(baseline, suite)
    if state != "passed":
        print(f"The unchanged sources {state} in the {suite} tests; run Tests/{suite}/run.sh first.")
        sys.exit(1)

survivors = 0
for number, (suite, name, old, new, meaning) in enumerate(MUTATIONS, 1):
    directory = os.path.join(work, f"m{number}")
    fresh(directory, suite)
    path = os.path.join(directory, name)
    text = open(path).read()
    if old not in text:
        print(f"ERROR     {number:2}  {name}: the text to break is gone, update the table: {old[:70]!r}")
        survivors += 1
        continue
    open(path, "w").write(text.replace(old, new, 1))
    state = build_and_run(directory, suite)
    if state == "failed":
        print(f"caught    {number:2}  [{suite}] {meaning}")
    else:
        survivors += 1
        print(f"SURVIVED  {number:2}  [{suite}] {meaning} ({state})")
    shutil.rmtree(directory, ignore_errors=True)

print(f"{len(MUTATIONS) - survivors} of {len(MUTATIONS)} mutations caught" + ("" if survivors == 0 else f", {survivors} NOT"))
sys.exit(1 if survivors else 0)
PYTHON
