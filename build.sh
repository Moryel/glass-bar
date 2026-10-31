#!/bin/zsh
# Builds GlassBar.app and installs it to ~/Applications.
# Usage: ./build.sh [--ac]   ·   ./build.sh release  → Intel + Apple Silicon, ad-hoc signed, build/GlassBar.zip (doesn't install)
set -e
cd "${0:A:h}"
VERSION=1.0
APP=build/GlassBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

compile() {
  swiftc -O -swift-version 5 -target $1-apple-macos14.0 \
    -framework AppKit -framework SwiftUI -framework CoreAudio -framework AudioToolbox -framework ServiceManagement -framework Accelerate \
    Sources/*.swift -o "$2"
}
if [[ "$1" == "release" ]]; then
  mkdir -p build/arch
  compile arm64 build/arch/arm64
  compile x86_64 build/arch/x86_64
  lipo -create build/arch/arm64 build/arch/x86_64 -output "$APP/Contents/MacOS/GlassBar"
  rm -rf build/arch
else
  compile arm64 "$APP/Contents/MacOS/GlassBar"
fi

# translations (by system language; English for languages not listed)
cp -R Resources/*.lproj "$APP/Contents/Resources/"
# app icon (source: tasarim/uygulama_simgesi.swift)
cp Resources/GlassBar.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.yukselozge.GlassBar</string>
  <key>CFBundleName</key><string>GlassBar</string>
  <key>CFBundleDisplayName</key><string>GlassBar</string>
  <key>CFBundleExecutable</key><string>GlassBar</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>tr</string></array>
  <key>CFBundleIconFile</key><string>GlassBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>GlassBar uses the microphone level to move the Siri waves on the Touch Bar while Siri is listening. Nothing is recorded.</string>
  <key>NSAudioCaptureUsageDescription</key><string>GlassBar listens to Spotify's audio level so the sound bar moves with the music. Nothing is recorded.</string>
  <key>NSAppleEventsUsageDescription</key><string>GlassBar shows what is playing in Music and Spotify and adds Finder tags.</string>
</dict>
</plist>
PLIST
sed -i '' "s/<string>VERSION<\/string>/<string>$VERSION<\/string>/" "$APP/Contents/Info.plist"

if [[ "$1" == "release" ]]; then
  # ad-hoc signature so it runs on any Mac (the personal certificate isn't distributed)
  xattr -cr "$APP"
  codesign --force --sign - "$APP"
  rm -f build/GlassBar.zip
  ditto -c -k --norsrc --noextattr --noqtn --keepParent "$APP" build/GlassBar.zip
  echo "Ready: build/GlassBar.zip ($(lipo -archs "$APP/Contents/MacOS/GlassBar"), version $VERSION)"
  exit 0
fi

mkdir -p ~/Applications
pkill -x GlassBar 2>/dev/null && sleep 0.5 || true
rm -rf ~/Applications/GlassBar.app
cp -R "$APP" ~/Applications/
# extended attributes from the iCloud folder break the signature; clean the installed copy and sign it
xattr -cr ~/Applications/GlassBar.app
# Sign with the local signing certificate if present: the identity stays the same across builds, so the Accessibility permission sticks.
# Otherwise ad-hoc; the permission then has to be granted again after each build.
IDENTITY=$(security find-identity -p codesigning 2>/dev/null | awk '/"TouchBar2 Yerel Imza"/ {print $2; exit}')
codesign --force --sign "${IDENTITY:--}" ~/Applications/GlassBar.app
echo "Installed: ~/Applications/GlassBar.app"
[[ "$1" == "--ac" ]] && open ~/Applications/GlassBar.app
exit 0
