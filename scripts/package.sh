#!/bin/bash
# Builds LiveMoreRAM.ipa from the original IPA in base/, swapping in only the
# rebuilt SideStoreSupport binary. Everything else stays byte-for-byte identical.
#
# Usage: scripts/package.sh <built SideStoreSupport.framework> <output.ipa>
set -euo pipefail

BUILT_FW="$1"
OUT_IPA="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE_IPA="$ROOT/base/LiveContainer_SideStore.ipa"
WORK="$(mktemp -d)"

[ -f "$BUILT_FW/SideStoreSupport" ] || { echo "!! $BUILT_FW/SideStoreSupport not found"; exit 1; }
[ -f "$BASE_IPA" ] || { echo "!! $BASE_IPA not found"; exit 1; }

echo "== Unpacking original IPA"
(cd "$WORK" && unzip -q "$BASE_IPA")

TARGET_FW="$WORK/Payload/LiveContainer.app/Frameworks/SideStoreSupport.framework"
[ -d "$TARGET_FW" ] || { echo "!! SideStoreSupport.framework missing in original IPA"; exit 1; }

echo "== Replacing SideStoreSupport binary"
cp "$BUILT_FW/SideStoreSupport" "$TARGET_FW/SideStoreSupport"
chmod 755 "$TARGET_FW/SideStoreSupport"

# Refresh the framework's ad-hoc seal so its _CodeSignature matches the new
# binary. The sideloader re-signs everything with your certificate anyway.
codesign --force --sign - --timestamp=none --preserve-metadata=identifier "$TARGET_FW"

echo "== Packaging"
rm -f "$OUT_IPA"
(cd "$WORK" && zip -qry -X "$OUT_IPA" Payload)
rm -rf "$WORK"
echo "== Done: $OUT_IPA"
