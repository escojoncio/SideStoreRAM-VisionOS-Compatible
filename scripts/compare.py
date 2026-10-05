#!/usr/bin/env python3
"""Checks that LiveMoreRAM.ipa is the original IPA 1:1 except for SideStoreSupport.

Fails (exit 1) if:
  - any file was added or removed,
  - any file other than SideStoreSupport.framework's binary / code seal changed,
  - any bundle identifier, version or entitlement plist differs,
  - the new SideStoreSupport binary lacks the LiveMoreRAM code,
  - the new binary dropped an Objective-C class the original had.
"""
import hashlib
import plistlib
import re
import sys
import zipfile

ALLOWED_CHANGES = {
    "Payload/LiveContainer.app/Frameworks/SideStoreSupport.framework/SideStoreSupport",
    "Payload/LiveContainer.app/Frameworks/SideStoreSupport.framework/_CodeSignature/CodeResources",
}
BINARY = "Payload/LiveContainer.app/Frameworks/SideStoreSupport.framework/SideStoreSupport"


def entries(path):
    with zipfile.ZipFile(path) as z:
        return {i.filename: z.read(i.filename) for i in z.infolist() if not i.is_dir()}


def objc_classes(data):
    return set(re.findall(rb"_OBJC_CLASS_\$_([A-Za-z0-9_]+)", data))


def main(original_path, new_path):
    original = entries(original_path)
    new = entries(new_path)
    ok = True

    added = sorted(set(new) - set(original))
    removed = sorted(set(original) - set(new))
    if added:
        ok = False
        print("ADDED files:", *added, sep="\n  ")
    if removed:
        ok = False
        print("REMOVED files:", *removed, sep="\n  ")

    changed = sorted(
        name for name in set(original) & set(new)
        if hashlib.sha256(original[name]).digest() != hashlib.sha256(new[name]).digest()
    )
    unexpected = [c for c in changed if c not in ALLOWED_CHANGES]
    print(f"Files in IPA: {len(new)} | changed: {len(changed)}")
    for c in changed:
        print(("  ok   " if c in ALLOWED_CHANGES else "  FAIL ") + c)
    if unexpected:
        ok = False

    if BINARY not in changed:
        ok = False
        print("FAIL SideStoreSupport binary was not replaced")

    for name in sorted(n for n in original if n.endswith("Info.plist") and n in new):
        try:
            a = plistlib.loads(original[name])
            b = plistlib.loads(new[name])
        except Exception:
            continue
        for key in ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion"):
            if a.get(key) != b.get(key):
                ok = False
                print(f"FAIL {name}: {key} {a.get(key)!r} -> {b.get(key)!r}")

    main_plist = plistlib.loads(new["Payload/LiveContainer.app/Info.plist"])
    print("Main bundle ID:", main_plist.get("CFBundleIdentifier"), main_plist.get("CFBundleShortVersionString"))

    new_binary = new.get(BINARY, b"")
    for marker in (b"LMRMemoryCapabilityProtocol", b"INCREASED_MEMORY_LIMIT", b"bundleIdCapabilities"):
        if marker not in new_binary:
            ok = False
            print("FAIL new SideStoreSupport is missing", marker.decode())

    missing_classes = objc_classes(original.get(BINARY, b"")) - objc_classes(new_binary)
    if missing_classes:
        ok = False
        print("FAIL classes missing from rebuilt SideStoreSupport:", sorted(c.decode() for c in missing_classes))

    print("RESULT:", "OK - identical to the original except SideStoreSupport" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
