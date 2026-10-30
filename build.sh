#!/bin/zsh
# GlassBar.app'i derler ve ~/Applications'a kurar. Kullanım: ./build.sh [--ac]
set -e
cd "${0:A:h}"
UYG=build/GlassBar.app
rm -rf "$UYG"
mkdir -p "$UYG/Contents/MacOS" "$UYG/Contents/Resources"

swiftc -O -swift-version 5 -target arm64-apple-macos14.0 \
  -framework AppKit -framework SwiftUI -framework CoreAudio -framework AudioToolbox -framework ServiceManagement -framework Accelerate \
  Sources/*.swift -o "$UYG/Contents/MacOS/GlassBar"

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
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Siri dinlerken Touch Bar'daki dalgayı sesinize göre hareket ettirmek için. Ses kaydedilmez.</string>
  <key>NSAudioCaptureUsageDescription</key><string>GlassBar listens to Spotify's audio level so the sound bar moves with the music. Nothing is recorded.</string>
  <key>NSAppleEventsUsageDescription</key><string>Müzik'te çalan parçayı göstermek ve Finder'da etiket eklemek için.</string>
</dict>
</plist>
PLIST

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
