#!/usr/bin/env bash
#
# Sonic Tools SVM — 一键编译 IPA
#
# 前置：1) 已装 Xcode（xcodebuild -version 能跑）
#       2) 已用 Apple ID 登录 Xcode，并把 Team ID 填进 pbxproj 或用环境变量传
#       3) 已执行 xcode-select -s <Xcode 路径>/Contents/Developer
#
# 用法：./make-ipa.sh            # Release
#       ./make-ipa.sh Debug
#       TEAM_ID=ABCDE12345 ./make-ipa.sh
#
set -euo pipefail

TEAM_ID="${TEAM_ID:-$(sed -n 's/.*DEVELOPMENT_TEAM = "\([A-Z0-9]*\)".*/\1/p' Subsonic.xcodeproj/project.pbxproj | head -1)}"
CONFIG="${1:-Release}"
SCHEME="Sonic Tools"
ARCHIVE="build/SonicTools.xcarchive"
EXPORT_PLIST="build/ExportOptions.plist"

cd "$(dirname "$0")"

echo "=== 0. 环境检查 ==="
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "✗ 找不到 xcodebuild。说明还没装 Xcode / 没切 xcode-select。" >&2
  echo "  → 见 BUILD.md §1" >&2; exit 1
fi
xcodebuild -version
echo "  DEVELOPER_DIR = $(xcode-select -p)"

if [ -z "$TEAM_ID" ]; then
  echo "✗ 没有 Team ID。请在 Xcode 里登录 Apple ID 并选 Team，然后："
  echo "    TEAM_ID=你的TeamID $0 ${CONFIG}" >&2; exit 1
fi
echo "  TEAM_ID = $TEAM_ID"

echo; echo "=== 1. 清理旧产物 ==="; rm -rf build

echo; echo "=== 2. Archive ==="
xcodebuild -project Subsonic.xcodeproj -scheme "$SCHEME" -configuration "$CONFIG" \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" -archivePath "$ARCHIVE" archive

echo; echo "=== 3. 生成 ExportOptions.plist ==="; mkdir -p build
cat > "$EXPORT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>development</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>stripSwiftSymbols</key><true/>
</dict></plist>
PLIST

echo; echo "=== 4. 导出 IPA ==="
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$EXPORT_PLIST" -exportPath build/ipa

echo; echo "============================================================"; ls -lh build/ipa/
echo "IPA 位置：$(cd build/ipa && pwd)"
echo; echo "下一步（三选一）："
echo "  A. SideStore / AltStore —— 用自己的 Apple ID 签，之后每周自动续签，不用连电脑（推荐）"
echo "  B. Sideloadly (Windows/Mac) —— 直接拖 .ipa 进去装，免费 Apple ID 需每 7 天重装"
echo "  C. Xcode 直接 Run 到真机"
echo "============================================================"
