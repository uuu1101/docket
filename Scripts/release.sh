#!/bin/bash
#
# Builds Docket and packages it as a DMG.
#
# The DMG carries a symlink to /Applications so the app is dragged there rather than run
# from Downloads — where it would work, but where "launch at login" would record the wrong
# path and an update would leave two copies behind.
#
# Signing tiers, lowest to highest:
#   (default)                                  ad-hoc — local test builds only
#   SIGN_IDENTITY="Developer ID Application"   a stable identity, but Gatekeeper still
#                                              rejects it until notarized
#   … plus NOTARY_PROFILE=docket-notary        notarizes and staples the DMG, which is
#                                              what lets recipients just double-click
#
# The notary profile is created once with:
#   xcrun notarytool store-credentials docket-notary \
#       --apple-id <apple-id-email> --team-id <TEAMID>
# using an app-specific password from appleid.apple.com.
set -euo pipefail

WORKSPACE="Docket.xcworkspace"
SCHEME="Docket"
CONFIGURATION="${CONFIGURATION:-Release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
DIST="dist"

step() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }

if [ -n "$NOTARY_PROFILE" ] && [ "$SIGN_IDENTITY" = "-" ]; then
    echo "NOTARY_PROFILE needs a real SIGN_IDENTITY: notarization rejects ad-hoc signatures." >&2
    exit 1
fi

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
# Hardened runtime and a secure timestamp are what notarization demands; ad-hoc builds
# skip them so local runs keep working on any machine.
sign_flags=()
if [ "$SIGN_IDENTITY" != "-" ]; then
    sign_flags=(--options runtime --timestamp)
fi
# Inside out: signing the app first would be invalidated by signing the framework after.
codesign --force --sign "$SIGN_IDENTITY" ${sign_flags[@]+"${sign_flags[@]}"} \
    "$app/Contents/Frameworks/DocketKit.framework"
codesign --force --sign "$SIGN_IDENTITY" ${sign_flags[@]+"${sign_flags[@]}"} "$app"
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

# The container gets a signature of its own: the app inside is what Gatekeeper runs,
# but an unsigned DMG still assesses as "no usable signature", which reads as broken.
if [ "$SIGN_IDENTITY" != "-" ]; then
    codesign --force --sign "$SIGN_IDENTITY" --timestamp "$dmg"
fi

if [ -n "$NOTARY_PROFILE" ]; then
    step "Notarizing (Apple's queue, typically a few minutes)"
    # On "Invalid": xcrun notarytool log <submission-id> --keychain-profile <profile>
    # names the exact file and reason.
    xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait

    step "Stapling the ticket"
    # Stapled, the DMG verifies even offline; unstapled, the first launch needs a
    # round-trip to Apple.
    xcrun stapler staple "$dmg"
fi

step "Done"
echo "  $dmg  ($(du -h "$dmg" | cut -f1))"
echo "  version    $version"
if [ -n "$NOTARY_PROFILE" ]; then
    echo "  notarized and stapled — recipients just double-click"
elif [ "$SIGN_IDENTITY" = "-" ]; then
    echo
    echo "  Ad-hoc signed: recipients need the quarantine step, and every update"
    echo "  re-asks for keychain access. For a real release:"
    echo "  SIGN_IDENTITY=\"Developer ID Application\" NOTARY_PROFILE=docket-notary make release"
else
    echo "  signed but not notarized — recipients still need the quarantine step"
fi
