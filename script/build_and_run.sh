#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:-run}"
name=AppDuo
app="$PWD/dist/$name.app"
/usr/bin/pkill -x "$name" >/dev/null 2>&1 || true
configuration="${CONFIGURATION:-debug}"
version="${APP_VERSION:-0.1.0}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "APP_VERSION must be major.minor.patch" >&2
    exit 2
fi
arch="$(uname -m)"
swift build -c "$configuration"
bin="$(swift build -c "$configuration" --show-bin-path)"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/$name" "$app/Contents/MacOS/$name"
# SwiftPM resource bundles must live next to the app's Resources lookup root.
for bundle in "$bin"/*.bundle; do
    [ -d "$bundle" ] || continue
    /usr/bin/ditto "$bundle" "$app/Contents/Resources/$(basename "$bundle")"
done
cp Sources/CloneCore/Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
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
case "$mode" in
 --build) ;;
 --dmg)
   stage="$(mktemp -d)"
   trap 'rm -rf "$stage"' EXIT
   /usr/bin/ditto "$app" "$stage/$name.app"
   ln -s /Applications "$stage/Applications"
   /usr/bin/hdiutil create -volname 'AppDuo' -srcfolder "$stage" -ov -format UDZO "$PWD/dist/AppDuo-$arch.dmg"
   ;;
 run) /usr/bin/open -n "$app" ;;
 --verify) /usr/bin/open -n "$app"; sleep 2; /usr/bin/pgrep -x "$name" >/dev/null ;;
 --debug) lldb -- "$app/Contents/MacOS/$name" ;;
 --logs|--telemetry) /usr/bin/open -n "$app"; /usr/bin/log stream --level info --predicate 'process == "AppDuo"' ;;
 *) echo "usage: $0 [run|--build|--dmg|--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;;
esac
