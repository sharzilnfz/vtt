#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
APP="$ROOT/.build/VTT.app"

cd "$ROOT"
swift build --configuration "$CONFIGURATION" --product VTT
BIN_DIR="$(swift build --configuration "$CONFIGURATION" --show-bin-path)"

# Assemble in a fresh staging directory so failed builds leave the previous app intact.
STAGING="$(mktemp -d "$ROOT/.build/VTT-package.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
BUNDLE="$STAGING/VTT.app"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN_DIR/VTT" "$BUNDLE/Contents/MacOS/VTT"
cp "$ROOT/scripts/Info.plist" "$BUNDLE/Contents/Info.plist"
chmod +x "$BUNDLE/Contents/MacOS/VTT"

# Preserve package resources in the standard signed-app resource directory.
shopt -s nullglob
RESOURCE_BUNDLES=("$BIN_DIR/"*.bundle)
if [[ ${#RESOURCE_BUNDLES[@]} -eq 0 ]]; then
    echo "No SwiftPM resource bundles found in $BIN_DIR; refusing an incomplete app." >&2
    exit 1
fi
for RESOURCE in "${RESOURCE_BUNDLES[@]}"; do
    NAME="$(basename "$RESOURCE")"
    ditto "$RESOURCE" "$BUNDLE/Contents/Resources/$NAME"
    # Command-line SwiftPM accessors also search beside the executable.
    ln -s "../Resources/$NAME" "$BUNDLE/Contents/MacOS/$NAME"
done

/usr/bin/plutil -lint "$BUNDLE/Contents/Info.plist"
/usr/bin/codesign --force --deep --sign "$SIGNING_IDENTITY" "$BUNDLE"
/usr/bin/codesign --verify --deep --strict "$BUNDLE"
rm -rf "$APP"
mv "$BUNDLE" "$APP"
echo "Built $APP"
echo "Launch with: open \"$APP\""
echo "Keep the bundle at a stable path for macOS permissions. Ad-hoc rebuilds may require granting permissions again."
