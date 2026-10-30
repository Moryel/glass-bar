#!/bin/zsh
# GlassBar.app'i derler ve ~/Applications'a kurar.
# Kullanım: ./build.sh [--ac]   ·   ./build.sh release  → Intel + Apple Silicon, geçici imza, build/GlassBar.zip (kurmaz)
set -e
cd "${0:A:h}"
SURUM=1.0
UYG=build/GlassBar.app
rm -rf "$UYG"
mkdir -p "$UYG/Contents/MacOS" "$UYG/Contents/Resources"

derle() {
  swiftc -O -swift-version 5 -target $1-apple-macos14.0 \
    -framework AppKit -framework SwiftUI -framework CoreAudio -framework AudioToolbox -framework ServiceManagement -framework Accelerate \
    Sources/*.swift -o "$2"
}
if [[ "$1" == "release" ]]; then
  mkdir -p build/mimari
  derle arm64 build/mimari/arm64
  derle x86_64 build/mimari/x86_64
  lipo -create build/mimari/arm64 build/mimari/x86_64 -output "$UYG/Contents/MacOS/GlassBar"
  rm -rf build/mimari
else
  derle arm64 "$UYG/Contents/MacOS/GlassBar"
fi

# çeviriler (sistemin diline göre; listede olmayan dillerde İngilizce)
cp -R Resources/*.lproj "$UYG/Contents/Resources/"
# uygulama simgesi (kaynağı: tasarim/uygulama_simgesi.swift)
cp Resources/GlassBar.icns "$UYG/Contents/Resources/"

cat > "$UYG/Contents/Info.plist" <<'PLIST'
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
  <key>CFBundleShortVersionString</key><string>SURUM</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>GlassBar uses the microphone level to move the Siri waves on the Touch Bar while Siri is listening. Nothing is recorded.</string>
  <key>NSAudioCaptureUsageDescription</key><string>GlassBar listens to Spotify's audio level so the sound bar moves with the music. Nothing is recorded.</string>
  <key>NSAppleEventsUsageDescription</key><string>GlassBar shows what is playing in Music and Spotify and adds Finder tags.</string>
</dict>
</plist>
PLIST
sed -i '' "s/<string>SURUM<\/string>/<string>$SURUM<\/string>/" "$UYG/Contents/Info.plist"

if [[ "$1" == "release" ]]; then
  # herkesin Mac'inde çalışsın diye geçici imza (kişisel sertifika dağıtılmaz)
  xattr -cr "$UYG"
  codesign --force --sign - "$UYG"
  rm -f build/GlassBar.zip
  ditto -c -k --norsrc --noextattr --noqtn --keepParent "$UYG" build/GlassBar.zip
  echo "Hazır: build/GlassBar.zip ($(lipo -archs "$UYG/Contents/MacOS/GlassBar"), sürüm $SURUM)"
  exit 0
fi

mkdir -p ~/Applications
pkill -x GlassBar 2>/dev/null && sleep 0.5 || true
rm -rf ~/Applications/GlassBar.app
cp -R "$UYG" ~/Applications/
# iCloud klasöründeki ek öznitelikler imzayı bozar; kurulan kopyayı temizleyip imzala
xattr -cr ~/Applications/GlassBar.app
# Yerel imza sertifikası varsa onunla imzala: kimlik her derlemede aynı kalır, Erişilebilirlik izni düşmez.
# Yoksa geçici (ad-hoc) imza; o zaman izin her derlemede yeniden verilmeli.
KIMLIK=$(security find-identity -p codesigning 2>/dev/null | awk '/"TouchBar2 Yerel Imza"/ {print $2; exit}')
codesign --force --sign "${KIMLIK:--}" ~/Applications/GlassBar.app
echo "Kuruldu: ~/Applications/GlassBar.app"
[[ "$1" == "--ac" ]] && open ~/Applications/GlassBar.app
exit 0
