# 构建 / 安装指南（Sonic Tools SVM）

> 上游：`tmatsugaki/Sonic-Tools-SVM`（GPL-3.0），本 fork：`HymanWong3911/Sonic-Tools-SVM`
> 分支：`feature/build-ready`

## ⭐ 方案 A（推荐）：GitHub Actions 云端出 IPA，手机上签名安装

**Mac 上什么都不用装**——不用下载 16 GB Xcode，不用 macOS 15+，不占你系统盘仅剩的 12 GiB。

### A1. 取 IPA

云端 runner 已构建好并发布：

```
https://github.com/HymanWong3911/Sonic-Tools-SVM/releases/download/ci-ipa/SonicTools-unsigned.ipa
```

在 iPhone 的 Safari 里直接打开这个链接下载（或 AirDrop / iCloud Drive 传到手机）。

**已验证的产物特征**（2026-11-05 实测）：

| 项 | 值 |
|---|---|
| 包体 | 687 KB |
| `CFBundleIdentifier` | `com.hymanwong.sonictools` |
| `CFBundleShortVersionString` / `CFBundleVersion` | `2.1.11` / `231` |
| `MinimumOSVersion` | 14.0 |
| 架构 | Mach-O 64-bit **arm64** |
| 链接框架 | Accelerate / CoreMotion / CoreLocation / AudioToolbox / UIKit（vDSP、加速度计、罗盘、RemoteIO 全在） |
| 本地化 | de/ar/zh-Hans/ja/en/… 17 种（中文 4 套齐全） |

### A2. 在手机上签名并安装

未签名的 ipa 不能直接装，需要用你自己的 Apple ID 签一次。两条路：

**① eSign**（App Store 上有，最省事，**完全不需要电脑**）
1. iPhone App Store 装 **eSign**（或 **SideStore** / **AltStore**）
2. eSign → **Add App → 选择刚下载的 ipa** → 用你的 Apple ID 登录并签名
3. 点 Install → 在「设置 → 通用 → VPN与设备管理」里信任你的开发者证书
4. 之后打开 App 点一下刷新即可续签

**② SideStore**（推荐，续签自动化）
1. 装 **SideStore**
2. SideStore → **Add Apps → 用你的 Apple ID 登录**（它自己管证书）
3. 导入 ipa → 安装
4. 开启后台刷新，**以后每周不用连电脑**

> ⚠️ 免费 Apple ID 的证书只有 **7 天**有效期，App 打开时顶部会显示倒计时。
> SideStore / eSign 会自动续签；如果你用 Xcode 直连安装，则每 7 天要重装一次。

### A3. 自己重新触发构建

```bash
git push github feature/build-ready     # 任何改动都会触发
# 或在 Actions 页面点 "Build unsigned IPA" → Run workflow
```

工作流：`.github/workflows/build-ipa.yml`（5 步：checkout → 校验 iOS SDK → 无签名构建 →
打包 Payload → 发布到 `ci-ipa` release）。

**两个已修的坑**（都在 commit 里）：
- 不要用 `setup-xcode` 固定旧版 Xcode——runner 镜像会裁掉旧版的 iOS 平台，报
  `iOS 18.2 Platform Not Installed`（Xcode 二进制还在，SDK 没了）。用镜像默认版本即可。
- 打包步骤里 `cd` 之后要用**绝对路径**（`$GITHUB_WORKSPACE`），否则 `set -e` 会因相对路径错位而中止。

---

## 0. 为什么需要自己构建

上游 App Store 条目 **id1245046029 / `jp.mydns.rikki.Subsonic`** 已从 App Store **全量下架**（2026 年上半年）。
2026-08-03 上游仓库 issue #6「App has been removed from iOS app store」记录了这件事，作者未回复。

已核实的事实（三方独立佐证）：

| 证据 | 结果 |
|---|---|
| `itunes.apple.com/lookup?id=1245046029` | `resultCount: 0`（**157 个 storefront 全扫，无一存活**） |
| `apps.apple.com/{store}/app/sonic-tools-svm/id1245046029` | 302 跳转到商店首页（商品页不存在） |
| 上游 issue #6（2026-08-03） | 用户报告「已被移除」，作者未回复；最后一次 push 2024-10-11 |

**作者的官方表态**（下架商品页描述原文，第三方聚合站留存）：

> *"Since the source code of this is widely published as an open source software on GitHub,
> **you can make custom version of this**.
> We welcome the users who want us to make customized version of this app."*

→ **从源码自建是作者指定、公开欢迎的路径**，不是灰色绕路。

**重要**：下架只影响「重新下载」，**不影响已安装的设备**。如果 iPhone 上还留着这个 App，它仍然能正常运行，
只是没法再从 App Store 重新下载、也没法在新设备上装。

## 1. 方案 B 前置条件（在 Mac 本地编译时需要）

| 项 | 要求 | 说明 |
|---|---|---|
| macOS | ≥ 14.5 | 本机 14.8.5 (23J423) / Intel x86_64 |
| Xcode | **16.2**（最高 16.3） | Xcode 26 需要 macOS 15.6+，本机装不了 |
| 磁盘 | ~16 GB | 本机系统盘只剩 12 GiB → **Xcode 必须装到外置盘** |
| Apple ID | 必需 | 免费账号可签，但证书 **7 天**有效（每周要重装一次）；付费开发者 1 年 |
| 真机 | 必需 | 麦克风 / 加速度计 / 磁罗盘，**模拟器测不出任何东西** |

> 方案 B 只在你想改代码、或想在 Xcode 里直接 Run 调试时才需要。**只是想装到手机上用，走方案 A 就行。**

### 外置盘安装 Xcode（本机磁盘不够时的做法）

```bash
# 1) 下载（约 10 GB，Apple CDN 需 Apple ID 登录）
curl -L -o ~/Downloads/Xcode_16.2.xip \
  "https://developer.apple.com/services-account/download?path=/Developer_Tools/Xcode_16.2/Xcode_16.2.xip"
#    ↑ 该地址会 302 到 idmsa.apple.com 登录页，用你自己的 Apple ID 登录后取得直链
#    也可以直接在 Safari 打开 https://developer.apple.com/download/all/ 下载

# 2) 解压到外置盘（/Volumes/数据盘 有 297 GiB 空闲）
xip -x ~/Downloads/Xcode_16.2.xip        # 解压出 Xcode.xip → Xcode.app
mv Xcode.app "/Volumes/数据盘/Xcode/"

# 3) 切换开发者目录
sudo xcode-select -s "/Volumes/数据盘/Xcode/Contents/Developer"
xcodebuild -version
xcrun simctl list runtimes   # 如需模拟器，另装 iOS runtime
```

## 2. 本 fork 已做的构建修复

上游工程用 Xcode 12.5 时代的设置，用现代 Xcode 直接开箱会失败。本分支已修：

| 文件 | 修改 | 原因 |
|---|---|---|
| `Subsonic.xcodeproj/project.pbxproj` | `CLANG_CXX_LANGUAGE_STANDARD`: `gnu++0x` → `gnu++17` | **硬编译错误**：Xcode 15+ 删除了 `gnu++0x` |
| 同上 | `CODE_SIGN_IDENTITY`: `iPhone Developer` → `Apple Development` | Xcode 14+ 改名的证书类型 |
| 同上 | `DEVELOPMENT_TEAM`: `F42S2EFB55` → `""` | 原作者的 Team ID，必须用你自己的 |
| 同上 | `PRODUCT_BUNDLE_IDENTIFIER`: `jp.mydns.rikki.Subsonic` → `com.hymanwong.sonictools` | 你无权签署别人的 Bundle ID |
| `Subsonic.xcodeproj/xcshareddata/xcschemes/Sonic Tools.xcscheme` | 新增共享 scheme | 上游 scheme 在 `xcuserdata/matsu.xcuserdatad/`（原作者的用户目录），且引用**两个不存在的测试 target**（`SubsonicTests` / `SubsonicUITests`），headless 构建会失败 |
| `Subsonic/Info.plist` | 删除 `Fabric`/Crashlytics 字典 | 死配置，工程里没有对应依赖 |
| `Subsonic/Info.plist` | `UIRequiredDeviceCapabilities` 去掉 `armv7` | 只构建 arm64，保留 armv7 与实际能力矛盾 |
| `Subsonic/Info.plist` | 新增 `NSLocationWhenInUseUsageDescription` | 磁力计页用 `CLLocationManager` 读罗盘，缺这个 key 会静默失败 |

## 3. 签名与安装（Xcode GUI）

1. `open Subsonic.xcodeproj`
2. Xcode → Settings → Accounts → 登录你的 Apple ID（免费账号也行）
3. 选中 **Sonic Tools** target → **Signing & Capabilities**
   - 勾选 *Automatically manage signing*
   - **Team**: 选你自己的（Personal Team 即可）
   - **Bundle Identifier**: 确认是 `com.hymanwong.sonictools`，若与别人冲突改后缀即可
4. 真机用 USB 连上 iPhone，在 target → *Run Destinations* 里选你的设备
5. 首次运行 iPhone 上会要求**信任开发者证书**：设置 → 通用 → VPN与设备管理 → 信任
6. 点 Run。第一次会报「Personal Team 需 7 天有效期」，到时重装即可

## 4. 命令行构建

```bash
# 需要先把 Team ID 填进工程（或用环境变量覆盖）
# Team ID 在 Xcode → Settings → Accounts → Manage Certificates 可见，
# 或 https://developer.apple.com/account → Membership 里看

xcodebuild \
  -project Subsonic.xcodeproj \
  -scheme "Sonic Tools" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=你的TeamID \
  build \
  -derivedDataPath ./build

# 产物
ls ./build/Build/Products/Release-iphoneos/
```

打 IPA（用于 AirDrop / 爱思 / Sideloadly 侧载）：

```bash
xcodebuild -project Subsonic.xcodeproj -scheme "Sonic Tools" \
  -configuration Release -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=你的TeamID \
  -archivePath ./build/SonicTools.xcarchive archive

xcodebuild -exportArchive -archivePath ./build/SonicTools.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath ./build/ipa
```

`ExportOptions.plist`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key>          <string>development</string>
  <key>signingStyle</key>    <string>automatic</string>
  <key>teamID</key>          <string>你的TeamID</string>
  <key>stripSwiftSymbols</key><true/>
</dict></plist>
```

## 5. 运行时注意

- **必须有真机**：模拟器没有麦克风输入、加速度计、罗盘。
- 声音测量会**实时输出扫频/噪声**信号，**别戴耳机**（上游 README 明确警告）。
- 导出的 CSV 在 App 的 `Documents` 目录，经 `UIFileSharingEnabled` 暴露给 Files.app。
- 振动/磁场页用 `CLLocationManager` 的**磁罗盘 heading**，不是 `CMMagnetometer`——读数会随设备姿态变化。
- 免费 Apple ID 签名：**每 7 天**要重新连电脑跑一次安装。

## 6. 未修复的已知问题（上游缺陷，供参考）

- `PinkNoiseFFT.mm:36-37`：`malloc(fftSize >> 1 * sizeof(float))` 运算符优先级错误，实际只分配 1/4 所需内存（该文件未加入 target，暂时无害）。
- 三角波 `acos(cos(theta))` 输出 `[0, π]`，含直流偏置、幅度未归一。
- 默认窗函数是 Rectangular（不加窗），旁瓣泄漏会降低 Lagrange 峰值定位精度。
- 扫频速率按音频回调次数推进，不是时间恒定。
- `mo_gfx.hh/.mm`、`MoAudio::vibrate()`、`Subsonic/Settings.m`（不存在）均为死代码。

详见 `docs/ARCHITECTURE.md`。
