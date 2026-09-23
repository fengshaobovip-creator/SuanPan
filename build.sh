#!/bin/bash
# 构建「算盘」.app
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$DIR/算盘.app"
ARCH="$(uname -m)"
ICNS="$DIR/AppIcon.icns"

echo "▸ 清理旧的产物"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "▸ 准备图标"
if [ ! -f "$ICNS" ]; then
  TMP="$(mktemp -d)"
  swiftc -O -swift-version 5 -framework AppKit -o "$TMP/icongen" "$DIR/tools/IconGen.swift"
  "$TMP/icongen" "$TMP/icon_1024.png"
  mkdir -p "$TMP/icon.iconset"
  while read -r px name; do
    if [ -z "$px" ]; then continue; fi
    sips -z "$px" "$px" "$TMP/icon_1024.png" --out "$TMP/icon.iconset/icon_${name}.png" >/dev/null
  done <<'SIZES'
16 16x16
32 16x16@2x
32 32x32
64 32x32@2x
128 128x128
256 128x128@2x
256 256x256
512 256x256@2x
512 512x512
SIZES
  cp "$TMP/icon_1024.png" "$TMP/icon.iconset/icon_512x512@2x.png"
  iconutil -c icns "$TMP/icon.iconset" -o "$ICNS"
  rm -rf "$TMP"
fi
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"

echo "▸ 写入 Info.plist"
cp "$DIR/Info.plist" "$APP/Contents/Info.plist"

echo "▸ 编译 Swift 源码 (universal: arm64 + x86_64)"
BIN="$APP/Contents/MacOS/SuanPan"
TBIN="$(mktemp -d)"
BUILT=""

for A in arm64 x86_64; do
  if swiftc -O -swift-version 5 \
       -target "${A}-apple-macosx26.0" \
       -framework AppKit \
       -o "$TBIN/SuanPan-$A" \
       "$DIR/main.swift" 2>"$TBIN/err-$A"; then
    echo "  ✓ $A"
    BUILT="$BUILT $A"
  else
    echo "  ✗ $A（跳过，见下）"
    sed 's/^/      /' "$TBIN/err-$A" | head -6
  fi
done

if [ -f "$TBIN/SuanPan-arm64" ] && [ -f "$TBIN/SuanPan-x86_64" ]; then
  lipo -create "$TBIN/SuanPan-arm64" "$TBIN/SuanPan-x86_64" -output "$BIN"
elif [ -f "$TBIN/SuanPan-arm64" ]; then
  cp "$TBIN/SuanPan-arm64" "$BIN"
elif [ -f "$TBIN/SuanPan-x86_64" ]; then
  cp "$TBIN/SuanPan-x86_64" "$BIN"
else
  echo "✗ 两个架构都编译失败，中止"; rm -rf "$TBIN"; exit 1
fi
rm -rf "$TBIN"

echo "▸ Ad-hoc 签名"
codesign --force --sign - "$APP" 2>/dev/null || echo "  (签名跳过，不影响本机运行)"

echo "▸ 完成: $APP"
