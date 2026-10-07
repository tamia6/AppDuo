#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:-run}"
name=AppDuo
app="$PWD/dist/$name.app"
if [[ "$mode" != "--build" && "$mode" != "--dmg" ]]; then
    /usr/bin/pkill -x "$name" >/dev/null 2>&1 || true
fi
configuration="${CONFIGURATION:-debug}"
version="${APP_VERSION:-0.1.5}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "APP_VERSION must be major.minor.patch" >&2
    exit 2
fi
arch="$(uname -m)"
swift build -c "$configuration"
bin="$(swift build -c "$configuration" --show-bin-path)"
# Do not retain resource bundles or icon links from an older staging layout.
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/$name" "$app/Contents/MacOS/$name"
if [[ "$configuration" == "release" ]]; then
    /usr/bin/strip -S -x "$app/Contents/MacOS/$name"
fi
# Keep resources inside Contents so codesign can seal the entire app.
for bundle in "$bin"/*.bundle; do
    [ -d "$bundle" ] || continue
    /usr/bin/ditto "$bundle" "$app/Contents/Resources/$(basename "$bundle")"
done
# Copy the icon to the location declared in Info.plist.
resource_icon="$name"_CloneCore.bundle/Contents/Resources/Resources/AppIcon.icns
if [[ ! -f "$app/Contents/Resources/$resource_icon" ]]; then
    resource_icon="$name"_CloneCore.bundle/Resources/AppIcon.icns
fi
cp "$app/Contents/Resources/$resource_icon" "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$name</string>
<key>CFBundleIdentifier</key><string>com.atbclone.swift</string>
<key>CFBundleName</key><string>AppDuo</string>
<key>CFBundleDisplayName</key><string>AppDuo</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>$version</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
/usr/bin/codesign --force --deep --sign - "$app"
bash script/check_packaged_app.sh "$app"
case "$mode" in
 --build) ;;
 --dmg)
   stage="$(mktemp -d)"
   trap 'rm -rf "$stage"' EXIT
   /usr/bin/ditto "$app" "$stage/$name.app"
   ln -s /Applications "$stage/Applications"
   /usr/bin/hdiutil create -volname 'AppDuo' -srcfolder "$stage" -ov -format UDZO -imagekey zlib-level=9 "$PWD/dist/AppDuo-$arch.dmg"
   ;;
 run) /usr/bin/open -n "$app" ;;
 --verify) /usr/bin/open -n "$app"; sleep 2; /usr/bin/pgrep -x "$name" >/dev/null ;;
 --debug) lldb -- "$app/Contents/MacOS/$name" ;;
 --logs|--telemetry) /usr/bin/open -n "$app"; /usr/bin/log stream --level info --predicate 'process == "AppDuo"' ;;
 *) echo "usage: $0 [run|--build|--dmg|--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;;
esac
