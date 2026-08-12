#!/bin/bash
# ============================================================
# 影视星河设备管理系统 · 苹果端 IPA 一键生成脚本（在 Mac 上运行）
#   用法1（无签名，产出可被 Sideloadly/AltStore 重签安装的 IPA）：
#       bash build-ipa.sh
#   用法2（用你的开发者团队签名，产出可直接安装的 IPA）：
#       bash build-ipa.sh <你的TeamID>
#       TeamID 在 https://developer.apple.com 账号 Membership 页查看，
#       或 Xcode → Signing & Capabilities 里的 Team 对应 10 位字母数字。
# ============================================================
set -e
cd "$(dirname "$0")"

TEAM="$1"
CONF=Release
DD=build

if [ -n "$TEAM" ]; then
  echo "==> 使用团队 $TEAM 签名编译..."
  xcodebuild -project YingshiDeviceMgr.xcodeproj \
    -scheme YingshiDeviceMgr -configuration $CONF \
    -derivedDataPath "$DD" \
    CODE_SIGNING_ALLOWED=YES \
    DEVELOPMENT_TEAM="$TEAM" \
    CODE_SIGN_IDENTITY="Apple Development" \
    CODE_SIGN_STYLE=Automatic | tail -8
  OUT=YingshiDeviceMgr-signed.ipa
else
  echo "==> 无签名编译（CODE_SIGNING_ALLOWED=NO）..."
  xcodebuild -project YingshiDeviceMgr.xcodeproj \
    -scheme YingshiDeviceMgr -configuration $CONF \
    -derivedDataPath "$DD" \
    CODE_SIGNING_ALLOWED=NO | tail -8
  OUT=YingshiDeviceMgr-unsigned.ipa
fi

APP="$DD/Build/Products/$CONF-iphoneos/YingshiDeviceMgr.app"
if [ ! -d "$APP" ]; then
  echo "!! 编译未产出 .app，请查看上方 xcodebuild 错误信息。"
  exit 1
fi

rm -rf Payload
mkdir -p Payload
cp -r "$APP" Payload/
rm -f "$OUT"
zip -qr "$OUT" Payload
rm -rf Payload

echo "============================================================"
echo "已生成：$(pwd)/$OUT"
if [ -z "$TEAM" ]; then
  echo "该 IPA 未签名，可在 Windows/Mac 上用 Sideloadly 或 AltStore"
  echo "输入你自己的 Apple ID 重签后安装到 iPhone。"
else
  echo "该 IPA 已用你的团队签名，可用 Xcode Organizer / AltStore"
  echo "安装到已注册设备（免费账号 7 天有效期，需定期重签）。"
fi
echo "============================================================"
