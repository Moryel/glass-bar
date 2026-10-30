#!/bin/zsh
# TouchBar2.app'i derler ve ~/Applications'a kurar. Kullanım: ./build.sh [--ac]
set -e
cd "${0:A:h}"
UYG=build/TouchBar2.app
rm -rf "$UYG"
mkdir -p "$UYG/Contents/MacOS" "$UYG/Contents/Resources"

swiftc -O -swift-version 5 -target arm64-apple-macos14.0 \
  -framework AppKit -framework SwiftUI -framework CoreAudio -framework AudioToolbox -framework ServiceManagement \
  Sources/*.swift -o "$UYG/Contents/MacOS/TouchBar2"

# çeviriler (sistemin diline göre; listede olmayan dillerde İngilizce)
cp -R Resources/*.lproj "$UYG/Contents/Resources/"

cat > "$UYG/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.yukselozge.TouchBar2</string>
  <key>CFBundleName</key><string>TouchBar2</string>
  <key>CFBundleDisplayName</key><string>TouchBar2</string>
  <key>CFBundleExecutable</key><string>TouchBar2</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>tr</string></array>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Siri dinlerken Touch Bar'daki dalgayı sesinize göre hareket ettirmek için. Ses kaydedilmez.</string>
  <key>NSAppleEventsUsageDescription</key><string>Müzik'te çalan parçayı göstermek ve Finder'da etiket eklemek için.</string>
</dict>
</plist>
PLIST

mkdir -p ~/Applications
pkill -x TouchBar2 2>/dev/null && sleep 0.5 || true
rm -rf ~/Applications/TouchBar2.app
cp -R "$UYG" ~/Applications/
# iCloud klasöründeki ek öznitelikler imzayı bozar; kurulan kopyayı temizleyip imzala
xattr -cr ~/Applications/TouchBar2.app
# Yerel imza sertifikası varsa onunla imzala: kimlik her derlemede aynı kalır, Erişilebilirlik izni düşmez.
# Yoksa geçici (ad-hoc) imza; o zaman izin her derlemede yeniden verilmeli.
KIMLIK=$(security find-identity -p codesigning 2>/dev/null | awk '/"TouchBar2 Yerel Imza"/ {print $2; exit}')
codesign --force --sign "${KIMLIK:--}" ~/Applications/TouchBar2.app
echo "Kuruldu: ~/Applications/TouchBar2.app"
[[ "$1" == "--ac" ]] && open ~/Applications/TouchBar2.app
exit 0
