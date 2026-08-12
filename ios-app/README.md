# 影视星河设备管理系统 · 苹果原生版（v4.0）

与鸿蒙端一模一样功能与界面的 SwiftUI 工程。Windows 环境无法编译 iOS，请在 Mac 上构建。

## 构建步骤（Mac）
1. 安装 Xcode 15 或更高版本（iOS 16+ 目标）。
2. 双击 `YingshiDeviceMgr.xcodeproj` 打开工程。
3. 选中 TARGETS → YingshiDeviceMgr → Signing & Capabilities：
   - 勾选 Automatically manage signing，选择你的开发者团队（个人 Apple ID 亦可真机调试）。
   - 如需上架/分发，将 Bundle Identifier `com.yingshi.devicemgr` 换成你账号下的唯一 ID。
4. 选择目标设备（模拟器或真机），Product → Run（调试）或 Archive（Release 出 IPA）。

## 生成 IPA 文件

苹果规定 iOS 编译只能在 macOS/Xcode 上进行，Windows 无法直接生成 IPA。提供两条一键路径：

### 方式一：有 Mac —— 一键脚本
在 Mac 上进入 `ios-app` 目录执行：
```bash
bash build-ipa.sh            # 产出无签名 YingshiDeviceMgr-unsigned.ipa
bash build-ipa.sh <TeamID>   # 用你的 Apple 开发团队签名，产出可直接安装的 IPA
```

### 方式二：没有 Mac —— GitHub Actions 云端编译
1. 将本仓库（至少 `ios-app/` 目录，含 `.github/workflows/build-ipa.yml`）推送到你的 GitHub 仓库。
2. 打开仓库 Actions → build-ipa → Run workflow。
3. 构建完成后在 Run 详情页下载制品 `YingshiDeviceMgr-unsigned-ipa`，得到无签名 IPA。

### 无签名 IPA 如何装到 iPhone（Windows 即可）
1. 下载 Sideloadly（https://sideloadly.io）或 AltStore。
2. iPhone 用数据线连电脑，在 Sideloadly 中拖入无签名 IPA，填入你自己的 Apple ID。
3. 点击 Start 完成重签并安装；首次需在 iPhone 上「设置 → 通用 → VPN与设备管理」信任该开发者。
4. 免费 Apple ID 签名有效期 7 天，到期后重复上述步骤重签即可。

## 说明
- 服务器地址在 `YingshiDeviceMgr/App.swift` 的 `Session.base`（当前 http://47.104.244.29:3001），Info.plist 已放行 HTTP 明文（NSAllowsArbitraryLoads）。
- 相机权限用途：扫描设备条形码（Vision 框架解码 Code128/EAN-13/QR，无需第三方库）。
- 版本号：MARKETING_VERSION 4.0.0 / CURRENT_PROJECT_VERSION 4（与安卓、鸿蒙端 v4.0 对齐）。
- 功能清单（与鸿蒙端一致）：管理员发布通知、扫条形码查设备、扫条形码录编号、聊天已读/未读回执、群聊解散与成员删减、设备类型选择、人员登录/下线时间、每日天气、渐变头部等美化界面。
