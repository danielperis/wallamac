#!/bin/zsh
# Compila WallaMac.app (necesita las Command Line Tools de Xcode)
set -e
cd "$(dirname "$0")"
APP=build/WallaMac.app
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macos14.0 \
  Sources/*.swift -o build/WallaMac-arm64
swiftc -O -swift-version 5 -parse-as-library -target x86_64-apple-macos14.0 \
  Sources/*.swift -o build/WallaMac-x86_64
lipo -create build/WallaMac-arm64 build/WallaMac-x86_64 -output "$APP/Contents/MacOS/WallaMac"
rm build/WallaMac-arm64 build/WallaMac-x86_64

# Icono
ICONSET=build/AppIcon.iconset && mkdir -p $ICONSET
"$APP/Contents/MacOS/WallaMac" --render-icon build/icon1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon1024.png --out $ICONSET/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon1024.png --out $ICONSET/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns $ICONSET -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf $ICONSET build/icon1024.png

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>WallaMac</string>
  <key>CFBundleDisplayName</key><string>WallaMac</string>
  <key>CFBundleIdentifier</key><string>com.wallamac.app</string>
  <key>CFBundleExecutable</key><string>WallaMac</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDevelopmentRegion</key><string>es</string>
</dict></plist>
PLIST

codesign --force --deep -s - "$APP"
echo "✓ $APP"
