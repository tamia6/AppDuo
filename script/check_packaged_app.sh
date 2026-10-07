#!/bin/bash
set -euo pipefail
app="$(cd "$(dirname "${1:?usage: $0 APP}")" && pwd)/$(basename "$1")"
codesign --verify --deep --strict "$app"
test -f "$app/Contents/Frameworks/Sparkle.framework/Sparkle"
/usr/bin/otool -L "$app/Contents/MacOS/AppDuo" | /usr/bin/grep -q "@rpath/Sparkle.framework"
test -f "$app/Contents/Resources/AppIcon.icns"
test ! -L "$app/Contents/Resources/AppIcon.icns"
test ! -e "$app/AppDuo_CloneCore.bundle"
resources="$app/Contents/Resources/AppDuo_CloneCore.bundle/Contents/Resources/Resources"
if [[ ! -d "$resources" ]]; then
    resources="$app/Contents/Resources/AppDuo_CloneCore.bundle/Resources"
fi
cmp "$app/Contents/Resources/AppIcon.icns" "$resources/AppIcon.icns"
# This read-only launch mode checks the actual GUI executable's resource accessor.
# A missing bundle must fail even when the build directory is still available.
"$app/Contents/MacOS/AppDuo" --check-resources
