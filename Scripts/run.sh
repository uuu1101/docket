#!/bin/bash
# Launches the debug build, replacing any copy already running.
set -euo pipefail

settings=$(xcodebuild -workspace "Docket.xcworkspace" -scheme "Docket" -configuration Debug \
    -destination 'platform=macOS' -showBuildSettings 2>/dev/null)
products_dir=$(printf '%s\n' "$settings" | awk -F' = ' '/ BUILT_PRODUCTS_DIR = /{print $2; exit}')
product_name=$(printf '%s\n' "$settings" | awk -F' = ' '/ FULL_PRODUCT_NAME = /{print $2; exit}')
app="$products_dir/$product_name"
executable=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$app/Contents/Info.plist")

pkill -f "$product_name/Contents/MacOS" 2>/dev/null || true
sleep 1
"$app/Contents/MacOS/$executable" >/dev/null 2>&1 &
echo "Launched $product_name"
