# Sonic Tools SVM 安装教程（从 App Store 下架到自己装上）

> 这份教程记录的是**完整实战路径**，包含每一个真实的报错和对应的解法。
> 照着做不需要在 Mac 上装 Xcode，也不需要买开发者账号。

---

## 目录

- [0. 现状：App Store 已经没有了](#0-现状app-store-已经没有)
- [1. 方案总览](#1-方案总览)
- [2. 云端出 IPA（GitHub Actions）](#2-云端出-ipa-github-actions)
- [3. 手机端签名安装](#3-手机端签名安装)
- [4. 故障排查表](#4-故障排查表症状--原因--解法)
- [5. 长期免维护](#5-长期免维护用-sidestore)
- [6. 卸载与清理](#6-卸载与清理)
- [7. 一页速查](#7-一页速查)

---

## 0. 现状：App Store 已经没有了

原 App Store 条目 `id 1245046029` / `jp.mydns.rikki.Subsonic` **已从 App Store 全量下架**。

### 怎么核实「真的下架了」（而不是猜）

```bash
# 1) iTunes lookup API —— 只能接受数字 trackId，不接受 bundle id
curl --compressed "https://itunes.apple.com/lookup?id=1245046029&country=cn"
#   → "resultCount": 0
#   ⚠️ 必须加 --compressed，否则拿到 gzip 头会报 UnicodeDecodeError: 0x8b

# 2) 商品页 —— 302 跳商店首页 = 商品页不存在
curl -sIL "https://apps.apple.com/cn/app/sonic-tools-svm/id1245046029" | head -1

# 3) 上游 issue —— 2026-08-03 有用户报告「已被移除」，作者未回复
#    https://github.com/tmatsugaki/Sonic-Tools-SVM/issues/6
```

**要穷举全部 storefront 才算数**（本项目实测扫了 157 个，零存活）。只查一两个区会给出错误的乐观结论。

### 作者是欢迎我们自建的

下架商品页的描述原文（第三方聚合站留存）：

> *"Since the source code of this is widely published as an open source software on GitHub,
> **you can make custom version of this**.
> We welcome the users who want us to make customized version of this app."*

### 一个容易误解的点

**下架只影响「重新下载」，不影响已经装在设备上的 App。**
如果 iPhone 上还留着这个 App，它仍然能正常运行 —— 只是没法再从 App Store 重新下载、也没法装到新设备。
（如果你手机上只剩一个带云图标的占位符，那是购买记录残留，点不回来的。）

---

## 1. 方案总览

| 方案 | 需要 Mac | 需要 Xcode | 证书有效期 | 适合谁 |
|---|---|---|---|---|
| **A. Actions 出 IPA + AltStore** | 只在装 AltStore 时 | ❌ | 7 天，每周要连电脑续签 | 想先试试功能 |
| **B. Actions 出 IPA + SideStore** | 只在引导时 | ❌ | 7 天，**但自动续签** | **长期用 ✅** |
| **C. 本地 Xcode 编译 + 直连安装** | ✅ | ✅（约 16 GB） | 免费 7 天 / 付费 1 年 | 要改源码调试 |

> **本文主线走方案 B。** 全程不需要 Xcode，也不需要在 Mac 上留 16 GB 空间。

---

## 2. 云端出 IPA（GitHub Actions）

### 原理

`public repo` → GitHub 免费 macOS runner → **无签名**编译 → 把 `.app` 塞进 `Payload/` 打成 `.ipa` → 发布到 Release。

未签名的 ipa 不能直接装，但可以用你自己的 Apple ID 签一次（见第 3 节）。

### 工作流

仓库里已内置 `.github/workflows/build-ipa.yml`（5 步）：

```
Checkout → 校验 iOS SDK → 无签名构建 → 打包 Payload → 发布到 ci-ipa release
```

**任何一次 push 都会触发**，也可以在 Actions 页面手动 Run workflow。

### 下载

```
https://github.com/HymanWong3911/Sonic-Tools-SVM/releases/download/ci-ipa/SonicTools-unsigned.ipa
```

### 产物自检清单（下载后本地验，比「链接能打开」靠谱得多）

```bash
unzip -o SonicTools-unsigned.ipa "Payload/*.app/Info.plist" -d .
PL=$(find . -name Info.plist | head -1)
for k in CFBundleIdentifier CFBundleShortVersionString CFBundleVersion MinimumOSVersion; do
  printf "%-30s " "$k"; /usr/libexec/PlistBuddy -c "Print :$k" "$PL"; done

# 架构必须是 arm64
lipo -info "Payload/Sonic Tools.app/Sonic Tools"

# 关键框架必须链上（vDSP / 加速度计 / 罗盘 / RemoteIO）
otool -L "Payload/Sonic Tools.app/Sonic Tools" | grep -iE "Accelerate|CoreMotion|CoreLocation|AudioToolbox"
```

本项目实测通过值：

| 项 | 值 |
|---|---|
| 包体 | 687 KB |
| `CFBundleIdentifier` | `com.hymanwong.sonictools` |
| 版本 | `2.1.11` (231) |
| 最低系统 | iOS 14.0 |
| 架构 | Mach-O 64-bit **arm64** |
| 链接框架 | Accelerate / CoreMotion / CoreLocation / AudioToolbox / UIKit |
| 本地化 | 17 种（含简繁中港澳门） |

### ⚠️ 三个 CI 必踩的坑（都在本仓库的历史提交里修掉了）

**① 不要用 `setup-xcode` 固定旧版 Xcode**

```
error: iOS 18.2 Platform Not Installed.
```

runner 镜像**只保留「默认 Xcode + 与之匹配的 iOS 平台」**。切到旧版 Xcode 后，Xcode 二进制还在，
但对应的 iOS Platform 目录已被镜像裁掉 → ibtool 直接报平台不存在。
**解法：删掉 setup-xcode 步骤，用镜像默认版本**，并加一步显式校验：

```yaml
- run: |
    xcodebuild -version && xcodebuild -showsdks
    if ! xcodebuild -showsdks | grep -q "iOS"; then
      echo "::error::runner 上没有可用的 iOS SDK"; exit 1
    fi
```

**② fork 拥有者可能没有 admin 权限，日志 API 取不到**

```
GET /repos/{owner}/{repo}/actions/jobs/{id}/logs
→ 403 {"message":"Must have admin rights to Repository."}
```

**解法：把日志做成公开可读的两条通道。**

```yaml
# ① 日志落成 release 附件（公开仓免鉴权可下载）
xcodebuild ... 2>&1 | tee build.log
gh release upload ci-ipa build.log --clobber

# ② 编译器错误打成 GitHub 注解（公开 API 可读）
grep -E "(error|fatal error):" build.log | head -40 \
  | sed 's/%/%25/g; s/\r/%0D/g' \
  | while IFS= read -r l; do echo "::error::${l:0:1000}"; done
```

读注解：

```bash
CID=$(curl -s --compressed "https://api.github.com/repos/OWNER/REPO/commits/BRANCH/check-runs" \
      | python3 -c "import json,sys;print(json.load(sys.stdin)['check_runs'][0]['id'])")
curl -s --compressed "https://api.github.com/repos/OWNER/REPO/check-runs/$CID/annotations" | python3 -m json.tool
```

**发布步骤一定要加 `if: always()`**，否则失败时一个产物都没有，等于白跑一轮。

**③ workflow 里 `cd` 之后必须用绝对路径**

```yaml
# ✗ cd 之后 shell 还在 build/ 里，build/ipa/... 变成 build/build/ipa/...
PL="build/ipa/Payload/$(basename "$APP")/Info.plist"

# ✓ 用 $GITHUB_WORKSPACE
WS="$GITHUB_WORKSPACE"
PL="$WS/build/ipa/Payload/$(basename "$APP")/Info.plist"
```

这个坑的表现极具迷惑性：**产物已经生成并发布成功，但步骤报 exit 1**。

**④ YAML 块标量里内嵌多行脚本必须缩进**，顶格写会撑破块标量 → `could not find expected ':'`。

---

## 3. 手机端签名安装

### 3.1 先选对工具（别装错）

**App Store 搜「eSign」会搜到一堆同名应用 —— 国区那个不是侧载工具。**

本项目实测逐个核对国区 24 个叫 eSign 的应用，**全是 PDF 填表 / 电子签名工具**，
没有一个是装 IPA 的。同理，`IPA Installer: Dev Utility` 的说明里写着
*"NOT INTENDED FOR CONSUMER USE ... Installation requires a properly signed IPA file"* —— 它只装**已签名**的包。

**正确组合（全程不需要 Mac 常年开着）：**

| 工具 | 平台 | 作用 |
|---|---|---|
| **AltServer** | Mac | 引导安装第一个侧载 App（需要 **USB 连一次**） |
| **AltStore** | iPhone | 中间态。**引导完成后会被 SideStore 顶替** |
| **SideStore** | iPhone | **最终形态**：自己跟自己配对，每 3 天自动续签 |

### 3.2 前置条件（按顺序做，别跳）

#### ① 开发者模式 —— 但它**装完才出现**

> **设置 → 隐私与安全性 → 开发者模式 → 打开 → 重启手机**

**iOS 16+ 强制要求。** 而且这个开关只有在**装过开发者签名的 App 之后**才会出现在设置里 ——
所以顺序是「先装 AltStore → 点开它一次 → 再回去开开发者模式 → 重启」。

> 不开的后果：**App 装得上，但一点就闪退**。很多人以为是签名失败，其实是没开开发者模式。

#### ② 数据线必须能传数据（不是只供电）

**判据（Mac 上 2 秒可验）**：

```bash
python3 - <<'PY'
import socket, plistlib, struct
s=socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.settimeout(5); s.connect("/var/run/usbmuxd")
b=plistlib.dumps({"MessageType":"ListDevices","ClientVersionString":"p","ProgName":"p","kLibUSBMuxVersion":3})
s.send(struct.pack("IIII",16+len(b),1,8,0)+b)
h=s.recv(16); ln,_,_,_=struct.unpack("IIII",h); d=b""
while len(d)<ln-16: d+=s.recv(ln-16-len(d))
for x in plistlib.loads(d).get("DeviceList",[]):
    p=x.get("Properties",{})
    print(p.get("SerialNumber"), "配对:", "有" if p.get("PairRecordData") else "无")
PY
```

- **能列出设备** → 数据线 OK
- **列出 0 个** → 数据线只供电，或 USB 受限模式

macOS 的 USB 枚举能看到 iPhone（能充电、能读序列号）**不代表数据通了**。
这条组合症状 = **换一根确定能传数据的线** + **直插机身 USB 口，别插 Hub**。

> iOS 15+ 插线后会问「**允许配件连接吗？**」→ 选**允许**。
> 超过 7 天没解锁过的手机会进入 **USB 受限模式**，数据一律不给。

#### ③ 信任 Mac

> **设置 → 通用 → VPN与设备管理** → 找到这台电脑 → **信任**

> ⚠️ 「信任」在 **VPN与设备管理**，**不在**「传输或还原 iPhone」。后者是「抹掉所有内容和设置」。

如果列表里已经有这台 Mac 但 Mac 侧仍然拿不到配对凭据：
**在手机上把这台电脑「移除」，然后解锁重插线，重新信任** —— 强制走一次完整握手。

### 3.3 安装步骤

**Mac 端**

1. 下载 AltServer：<https://altstore.io>（独立 App，**不需要 Xcode**）
2. 打开 AltServer → 菜单栏图标 → **Install AltStore → 你的 iPhone**
3. 填 **Apple ID + App 专用密码**
   - ⚠️ **必须是 App 专用密码，不是登录密码**（带两步验证的登录密码一定失败）
   - 生成：`appleid.apple.com` → 登录 → **安全性** → **生成 App 专用密码**（只显示一次）
   - ⚠️ **必须是自己的主 Apple ID**，别用共享号 —— 证书绑账号
   - ⚠️ 如果这个 Apple ID 从没在 App Store 下过任何 App（"裸号"），先去 App Store 随便下一个免费 App 让它"激活"

**iPhone 端**

4. 打开 AltStore → **My Apps** → 左下 **+** → 选 `SideStore.ipa` → 安装
5. 打开 SideStore → **设置** → 填**同一个 Apple ID** → 保存
6. SideStore 第一次会问要不要开 VPN → **同意**（它靠这个在本地模拟一台装了 iTunes 的电脑来续签）
7. SideStore → **+** → 选 `SonicTools-unsigned.ipa` → 安装
8. **设置 → 通用 → VPN与设备管理 → 找到「开发者 App」→ 信任**

### 3.4 ⚠️ 弹窗「App Contains Extensions」→ 选 **Keep App Extensions**

```
Non-developer Apple IDs are limited to creating 10 App IDs per week.
Would you like to remove this app's extensions so they don't count towards your limit?
```

**选 Keep App Extensions（保留扩展）。**

SideStore 的扩展不是可选装饰：

| 扩展 | 作用 | 去掉的后果 |
|---|---|---|
| `SideStoreHelper`（VPN 扩展） | 在手机上模拟一台装了 iTunes 的电脑 | **SideStore 直接废掉** —— 装不了 App，也永远无法自动续签 |
| `SideStoreCore`（JIT 扩展） | 辅助执行 | 部分功能失效 |

**关于 10 个 App ID / 周**：免费 Apple ID 每周最多创建 10 个 App ID，**主 App 和每个扩展各算一个**。
本方案大致占用：AltStore ~2 + SideStore 3 + Sonic Tools 1 ≈ **6 / 10**，够用。
**别一周内装超过 10 个侧载 App**，超了得等一周。

### 3.5 用完可以拔线

SideStore 跑起来之后：

- **电脑完全不用再连**
- **AltServer 可以退出**（菜单栏图标 → Quit）
- SideStore 每 3 天自动刷新证书

---

## 4. 故障排查表（症状 → 原因 → 解法）

| 症状 | 真因 | 解法 |
|---|---|---|
| **HTTP 429 / "Apple's authentication servers returned an error"** | Apple 对**出口 IP** 的限流。国内家宽多为 **CGNAT 共享 IP**，同运营商下大量用户同时侧载 → 整个 IP 段被限 | ① **换出口 IP**：4G/5G 随身 WiFi 或借手机热点<br>② **等 15–30 分钟**，期间**千万别反复点**（每次重试都会把封禁往后推）<br>③ 查 `appleid.apple.com → 设备`，删掉不用的设备（报错原文是 `Non-developer Apple IDs are limited to creating 10 App IDs per week`；**额度用满时等和换 IP 都没用**，只能删旧的腾位置）<br>④ 确认用的是 App 专用密码 |
| **设置里找不到「开发者模式」** | 还没装过开发者签名的 App，开关不显示 | 先装上 AltStore，**点开它一次**，再回去找 |
| **AltStore 装上了但打不开** | 没开开发者模式 | 设置 → 隐私与安全性 → 开发者模式 → 开 → **重启** |
| **装 AltStore 时弹窗要求移除扩展** | 正常提示 | 选 **Keep App Extensions** |
| **侧载 App 装上后不自动旋转 / 界面卡在竖屏** | 设备侧临时状态：iOS 26 上首次安装、证书刷新或开发者模式切换后，旋转状态偶尔会卡住 | **重启手机**即可恢复；要根治，在 VC 里显式声明 `shouldAutorotate` → YES、`supportedInterfaceOrientations` → `UIInterfaceOrientationMaskAll`、`prefersInterfaceOrientationLocked` → NO（iOS 16+） |
| **App 装上了点开闪退** | 没在 VPN与设备管理 里信任证书 | 设置 → 通用 → VPN与设备管理 → 信任 |
| **AltStore 说连不上 AltServer** | Mac↔iPhone 没配对，或不在同一网络 | ① 确认两边同一 Wi-Fi<br>② 重新信任 Mac（移除后重插线）<br>③ 兜底：**把 ipa 直接拖到 Mac 上的 AltServer 窗口**（走安装代理，可绕过配对） |
| **不弹「信任此电脑」** | 数据线只供电 / USB 受限模式 | 换数据线 + 直插机身口 + 解锁手机后重插 |
| **`usbmuxd` 列出 0 个设备** | 同上 | 同上 |
| **CI 报 `iOS xx.x Platform Not Installed`** | 固定了旧版 Xcode，镜像裁掉了它的 iOS 平台 | 用镜像默认 Xcode（见 2.①） |
| **CI 失败但拿不到日志** | fork 拥有者没 admin 权限 | 用 `::error::` 注解 + release 附件（见 2.②） |

---

## 5. 长期免维护（用 SideStore）

装好 SideStore 之后：

- **证书自动续签**，每 3 天一次，**不用连电脑**
- 唯一禁忌：**别删 SideStore**，它就是续签引擎
- 想知道下次到期时间：SideStore → **My Apps** → 每行右边的到期日

以后要装新东西，同样在 SideStore 里 **+** 即可。

---

## 6. 卸载与清理

**手机上**：长按图标删除 → **同时删掉 SideStore**（否则它会继续占 App ID 额度）。

**Mac 上**：

```bash
# 退掉 AltServer
osascript -e 'quit app "AltServer"' 2>/dev/null
rm -rf ~/Downloads/AltServer

# 清理临时产物
rm -f ~/Downloads/SideStore.ipa ~/Downloads/SonicTools-unsigned.ipa
```

> ⚠️ 删 SideStore 之前想清楚：**没有 SideStore 就没有自动续签**，
> 里面的每个 App 都会在 7 天后失效，需要重新走一遍第 3 节。

---

## 7. 一页速查

```
【Mac 端】
① 装 AltServer（altstore.io）→ 菜单栏图标 → Install AltStore → 你的 iPhone
② 填 Apple ID + App 专用密码（appleid.apple.com 生成）

【iPhone 端】
③ 点开 AltStore 一次 → 设置 → 隐私与安全性 → 开发者模式 → 开 → 重启
④ 设置 → 通用 → VPN与设备管理 → 信任电脑
⑤ AltStore → My Apps → + → SideStore.ipa（弹扩展提示选 Keep）
⑥ 打开 SideStore → 设置 → 同一个 Apple ID → 保存 → 同意开 VPN
⑦ SideStore → + → SonicTools-unsigned.ipa → 安装
⑧ 设置 → 通用 → VPN与设备管理 → 信任「开发者 App」
⑨ 拔掉数据线。以后再也不用连电脑。
```

**产物链接**

```
https://github.com/HymanWong3911/Sonic-Tools-SVM/releases/download/ci-ipa/SonicTools-unsigned.ipa
```

---

## 安全提示

- **别用别人的共享 Apple ID 签名** —— 证书绑账号，对方随时能远程换掉你的证书
- **App 专用密码只用于侧载**，泄露了请立刻去 `appleid.apple.com` 撤销
- **免费证书 7 天到期是正常的**，SideStore 会自动续
- **信号发生器会实时出声，不要戴耳机**（上游 README 明确警告）
- 频谱显示的峰值是 **Lagrange 插值**的结果，**读数精度 ≠ 曲线分辨率**，别拿它当调音依据

---

## 许可

本文档与本 fork 同样以 **GPL-3.0** 发布。
上游项目：`tmatsugaki/Sonic-Tools-SVM`（作者公开欢迎用户自行构建定制版本）。
