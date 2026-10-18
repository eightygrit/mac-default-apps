// Probe: the deprecated UTType C functions against UniformTypeIdentifiers.UTType.
// READ-ONLY (changes nothing).   Run: Tests/probe/run.sh utt
//
// Sections: [conformance] the public.item / public.content filter, [description], [extensions] (tag lists),
// [preferred-id for extension] and [isDynamic]. Section 4 uses conformingTo: .content for the new side,
// the way copySchemesAndUTIsForApp asks; Tests/probe/extension.swift covers the CLI's --extension (conformingTo: nil).
// The legacy functions are called on purpose, so compiling this file prints deprecation warnings.
// READ-ONLY. Compares the deprecated UTType C functions with UniformTypeIdentifiers.UTType.
import AppKit
import UniformTypeIdentifiers

@_silgen_name("_UTCopyDeclaredTypeIdentifiers") func UTCopyDeclaredTypeIdentifiers() -> NSArray

let declared = UTCopyDeclaredTypeIdentifiers() as! [String]
let kept = declared.filter { UTTypeConformsTo($0 as CFString, "public.item" as CFString) || UTTypeConformsTo($0 as CFString, "public.content" as CFString) }
print("declared=\(declared.count) kept(legacy filter)=\(kept.count)")

// 1. conformance filter
var nilUT = 0, keptNew = 0, filterDiff: [String] = []
for u in declared {
    let old = UTTypeConformsTo(u as CFString, "public.item" as CFString) || UTTypeConformsTo(u as CFString, "public.content" as CFString)
    guard let t = UTType(u) else { nilUT += 1; if old { filterDiff.append("\(u): UTType(nil) but legacy kept") }; continue }
    let new = t.conforms(to: .item) || t.conforms(to: .content)
    if new { keptNew += 1 }
    if new != old { filterDiff.append("\(u): legacy=\(old) new=\(new)") }
}
print("[conformance] UTType(id)==nil for \(nilUT) of \(declared.count); kept(new)=\(keptNew); filter disagreements=\(filterDiff.count)")
filterDiff.prefix(6).forEach { print("   e.g. \($0)") }

// 2. description
var descSame = 0, descDiff: [String] = [], oldNilNewSome = 0, oldSomeNewNil = 0, bothNil = 0
for u in kept {
    let old = UTTypeCopyDescription(u as CFString)?.takeRetainedValue() as String?
    let t = UTType(u)
    let new = t?.localizedDescription
    switch (old, new) {
    case (nil, nil): bothNil += 1
    case (nil, .some): oldNilNewSome += 1; if descDiff.count < 6 { descDiff.append("\(u): legacy=nil new=\(new!)") }
    case (.some, nil): oldSomeNewNil += 1; if descDiff.count < 6 { descDiff.append("\(u): legacy=\(old!) new=nil") }
    case let (.some(a), .some(b)): if a == b { descSame += 1 } else if descDiff.count < 6 { descDiff.append("\(u): legacy=[\(a)] new=[\(b)]") }
    }
}
print("[description] same=\(descSame) bothNil=\(bothNil) legacyNil/newSome=\(oldNilNewSome) legacySome/newNil=\(oldSomeNewNil) other-diff=\(kept.count - descSame - bothNil - oldNilNewSome - oldSomeNewNil)")
descDiff.forEach { print("   e.g. \($0)") }

// 3. extensions
var extSameOrdered = 0, extSameSet = 0, extDiff: [String] = [], extLegacyNilNewEmpty = 0, extLegacyNilNewSome = 0, extBothEmpty = 0
for u in kept {
    let old = (UTTypeCopyAllTagsWithClass(u as CFString, kUTTagClassFilenameExtension)?.takeRetainedValue() as? [String])
    let new = UTType(u)?.tags[.filenameExtension]
    if old == nil && (new == nil || new!.isEmpty) { extBothEmpty += 1; continue }
    if old == nil { extLegacyNilNewSome += 1; if extDiff.count < 6 { extDiff.append("\(u): legacy=nil new=\(new!)") }; continue }
    if old! == (new ?? []) { extSameOrdered += 1 }
    else if Set(old!) == Set(new ?? []) { extSameSet += 1; if extDiff.count < 6 { extDiff.append("\(u): ORDER legacy=\(old!) new=\(new ?? [])") } }
    else { if extDiff.count < 12 { extDiff.append("\(u): legacy=\(old!) new=\(new ?? [])") } }
}
print("[extensions] sameOrdered=\(extSameOrdered) sameSetOnlyOrderDiffers=\(extSameSet) bothNone=\(extBothEmpty) legacyNil/newSome=\(extLegacyNilNewSome) other=\(kept.count - extSameOrdered - extSameSet - extBothEmpty - extLegacyNilNewSome)")
extDiff.forEach { print("   e.g. \($0)") }

// 4. extension -> preferred UTI (what copySchemesAndUTIsForApp does) + dynamic
var exts = Set<String>()
for u in kept { for e in (UTType(u)?.tags[.filenameExtension] ?? []) { exts.insert(e) } }
exts.formUnion(["", "zzzunknownext", "ZIP", "Html", "tar.gz", "py", "md", "swift"])
var prefSame = 0, prefDiff: [String] = [], dynSame = 0, dynDiff: [String] = []
for e in exts.sorted() {
    let old = (UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, e as CFString, "public.content" as CFString)?.takeRetainedValue() as String?)
    let new = UTType(filenameExtension: e, conformingTo: .content)?.identifier
    if old == new { prefSame += 1 } else if prefDiff.count < 8 { prefDiff.append("ext=[\(e)] legacy=\(old ?? "nil") new=\(new ?? "nil")") }
    if let o = old {
        let oDyn = UTTypeIsDynamic(o as CFString)
        let nDyn = UTType(o)?.isDynamic
        if nDyn == oDyn { dynSame += 1 } else if dynDiff.count < 6 { dynDiff.append("\(o): legacy=\(oDyn) new=\(String(describing: nDyn))") }
    }
}
print("[preferred-id for extension] tested=\(exts.count) same=\(prefSame) different=\(exts.count - prefSame)")
prefDiff.forEach { print("   e.g. \($0)") }
print("[isDynamic] same=\(dynSame) different=\(dynDiff.count)")
dynDiff.forEach { print("   e.g. \($0)") }
