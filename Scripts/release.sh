#!/bin/bash
#
# Builds Docket and packages it as a DMG for internal distribution.
#
# The DMG carries a symlink to /Applications so the app is dragged there rather than run
# from Downloads — where it would work, but where "launch at login" would record the wrong
# path and an update would leave two copies behind.
set -euo pipefail

WORKSPACE="Docket.xcworkspace"
SCHEME="Docket"
CONFIGURATION="${CONFIGURATION:-Release}"
# Ad-hoc by default. Pass a certificate name to keep the app's identity stable across
# versions; ad-hoc identity is the binary's hash, so every update makes macOS ask for
# keychain access again.
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
DIST="dist"

step() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }

step "Generating the project"
tuist generate --no-open >/dev/null

step "Building ($CONFIGURATION)"
xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" -configuration "$CONFIGURATION" \
    -destination 'platform=macOS' build >/dev/null

# Ask xcodebuild where it put things rather than guessing at the DerivedData path.
settings=$(xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" -configuration "$CONFIGURATION" \
    -destination 'platform=macOS' -showBuildSettings 2>/dev/null)
products_dir=$(printf '%s\n' "$settings" | awk -F' = ' '/ BUILT_PRODUCTS_DIR = /{print $2; exit}')
product_name=$(printf '%s\n' "$settings" | awk -F' = ' '/ FULL_PRODUCT_NAME = /{print $2; exit}')
app="$products_dir/$product_name"

[ -d "$app" ] || { echo "Build produced no app at $app" >&2; exit 1; }

step "Signing with identity: $SIGN_IDENTITY"
# Inside out: signing the app first would be invalidated by signing the framework after.
codesign --force --sign "$SIGN_IDENTITY" "$app/Contents/Frameworks/DocketKit.framework"
codesign --force --sign "$SIGN_IDENTITY" "$app"
codesign --verify --deep --strict "$app"
echo "  signature verified"

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")
volume="${product_name%.app}"
dmg="$DIST/$volume $version.dmg"

step "Packaging $dmg"
rm -rf "$DIST/staging"
mkdir -p "$DIST/staging"
cp -R "$app" "$DIST/staging/"
ln -s /Applications "$DIST/staging/Applications"
rm -f "$dmg"
hdiutil create -volname "$volume" -srcfolder "$DIST/staging" -ov -format UDZO "$dmg" >/dev/null
rm -rf "$DIST/staging"

# Informational: an app that is not notarized is rejected, which is expected here and is
# why the install notes have to mention the quarantine step.
gatekeeper=$(spctl --assess --type execute "$app" 2>&1 || true)

step "Done"
echo "  $dmg  ($(du -h "$dmg" | cut -f1))"
echo "  version    $version"
echo "  gatekeeper $([ -z "$gatekeeper" ] && echo "accepted" || echo "rejected — recipients need the quarantine step")"
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo
    echo "  Ad-hoc signed: every recipient re-allows keychain access after each update."
    echo "  Pass SIGN_IDENTITY=\"Apple Development: …\" to avoid that."
fi
