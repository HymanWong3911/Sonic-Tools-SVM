# Sonic Tools SVM — 架构深度解析

> 生成于 2026-11-05 ｜ 源码基线 `67e0b4e`（2024-10-11, "Added PinkNoise and BrownNoise"）
> 上游 `tmatsugaki/Sonic-Tools-SVM`（GPL-3.0）｜ 全部结论均带 `file:line` 证据

---

## 0. 一句话概括

一个**纯 Objective-C / Objective-C++** 的 iOS 测量工具：麦克风 → vDSP FFT → 自绘频谱/示波器/电平表，
加速度计 → 振动谱，罗盘 → 磁场表，另带一个独立的手写信号发生器。
**零 Swift、零 SwiftUI、零第三方 SPM/Pod 依赖**，全部依赖都是系统框架 + 两份内嵌源码。

| 维度 | 事实 |
|---|---|
| 语言 | Objective-C (23 `.m`) + Objective-C++ (18 `.mm`)，**0 个 `.swift`** |
| UI | UIKit only，**100% Storyboard 驱动**（`Main.storyboard` 327 KB） |
| 渲染 | 自绘 `UIView` + `drawRect:` + CoreGraphics；**CoreAnimation 几乎不用**；**OpenGLES 完全不用** |
| 导航 | 扁平 `UITabBarController` + 10 个 tab，**无 `UINavigationController`** |
| DSP | Apple Accelerate / vDSP（`vDSP_fft_zrip`, radix-2）+ 作者自研 3 点 Lagrange 插值 |
| 音频 I/O | MoMu (Stanford CCRMA) 派生的 AudioUnit RemoteIO |
| 传感器 | CoreMotion 加速度计 + CoreLocation 磁罗盘 |
| 最低系统 | iOS 14.0 ｜ 版本 2.1.11 (build 231) ｜ Bundle `jp.mydns.rikki.Subsonic` |

---

## 1. 三大测量域映射

| 域 | 屏幕 | ViewController | 自绘 View | 数据源 |
|---|---|---|---|---|
| **声音** | 频谱分析器（FFT / RTA / RTA 1-3 / RTA 1-6 / RTA 1-12 / 频谱图，6 模式） | `SpectrumViewController` | `FFTView` (123 KB) | 麦克风 RemoteIO → vDSP FFT |
| | 示波器（时域） | `ScopeViewController` | `ScopeView` | 麦克风时域 |
| | RMS 电平表 | `SPLViewController` | `SPLView` | 麦克风 → `vDSP_rmsqv` |
| | 信号发生器 | `ToneGeneratorViewController` | storyboard 控件 | 输出端 RemoteIO 合成 |
| **振动** | 频谱（三轴 FFT） | `AccelometerSpectrumViewController` | `AccelometerSpectrumView` | `CMMotionManager` 128 Hz |
| | 示波器（三轴） | `AccelometerScopeViewController` | `AccelometerScopeView` | 加速度计 32 Hz |
| | RMS（G） | `AccelometerSPLViewController` | `AccelometerSPLView` | 加速度计 32 Hz |
| **磁场** | 示波器（µT） | `TeslameterScopeViewController` | `TeslameterScopeView` | `CLLocationManager` heading x/y/z |
| | RMS（µT） | `TeslameterSPLViewController` | `TeslameterSPLView` | 同上 |
| 非测量 | 信息页 / 窗函数弹窗 | `MiscViewController` / `WindowFunctionViewController` | — | — |

**磁场域没有频谱屏**——只有 Scope 和 RMS。

---

## 2. 音频采集链路（MoMu 派生的 RemoteIO）

```
麦克风 ──▶ AudioUnit RemoteIO (input bus 1)
              │  8.24 定点 / 32bit / 非交织 / 2ch     mo_audio.mm:445-453
              ▼
        SMALLRenderProc  (AU 回调)                    mo_audio.mm:161-200
              │  AudioUnitRender(bus 1)                mo_audio.mm:174
              │  convertToUser: 定点→浮点, 去交织      mo_audio.mm:100-123
              │    factor = 1<<24
              ▼
        MoAudio::m_callback → 各页面 lambda           mo_audio.mm:190
              ▼
        累积 4096 单声道样本 (≈92.9 ms)                SpectrumViewController.mm:71-84
              ▼
        vDSP_fft_zrip (4096, radix-2)                 FFTHelper.mm:127
              ▼
        vDSP_vdist → 线性幅度谱 (N/2 点)              FFTHelper.mm:138
              ▼
        峰值 bin → 3 点 Lagrange 顶点细化              SpectrumViewController.mm:127-162
```

**会话配置**：`kAudioSessionCategory_PlayAndRecord` + `kAudioSessionMode_Measurement`（关 AGC）
（`MainViewController.mm:59-60`, `mo_audio.mm:574-576`）；
I/O 缓冲 FFT 页 0.005 s、Scope/SPL 页 0.046 s（`definitions.h:50-51`）。

**信号发生器是独立的第二个 RemoteIO**（`ToneGeneratorViewController.mm:531-584`），
32-bit float / 单声道 / 44100 Hz，只出不进，与采集链路完全隔离。

---

## 3. README 宣称的「Lagrange 插值把分辨率从 ~11 Hz 提到 ~3 Hz」

> README 原文：`README.md:19`「the actual resolution is in the maximum of 3 Hz by Lagrange interpolation processing」

### 3.1 原语

`FFTHelper.mm:149-164`（声明 `FFTHelper.hh:45`）——标准 Lagrange 基函数，
但本工程**只用 3 个节点**，等价于**二次抛物线顶点插值**：

```c
Float64 lagrangeInterp(CGPoint points[], NSUInteger numPoints, Float32 x) {
    Float64 p, y = 0.0;
    for (i = 0; i < numPoints; i++) {
        p = points[i].y;
        for (j = 0; j < numPoints; j++)
            if (i != j) p *= (x - points[j].x) / (points[i].x - points[j].x);
        y += p;
    }
    return y;
}
```

### 3.2 唯一调用点

`SpectrumViewController.mm:127-162`（函数 `spectrumStrongestFrequencyHZ`）：

```c
Float32 df  = sampleRate / fftPoints;          // :133  = 10.766 Hz
Float32 f0 = HZ - df, f1 = HZ, f2 = HZ + df;    // :135-137
NSUInteger times = 40 * (fftPoints / 2048);    // :138  4096 点时 = 80
points[0..2] = { bin[max-1], bin[max], bin[max+1] }   // :140-145
for (i = 0; i < times; i++) {                  // :151
    Float32 x = f0 + (df2 / times) * i;        // :152  步进 = df/40 ≈ 0.269 Hz
    curValue = lagrangeInterp(points, 3, x);   // :153  ★ 唯一调用点
    if (curValue > maxValue) { maxValue = curValue; maxIndex = i; }
}
HZ = f0 + df2 * (maxIndex / (Float32)times);   // :161  反算峰值频率
```

### 3.3 结论与边界（重要）

1. **只细化「峰值频率读数」，不细化谱曲线。**
   绘图仍用原始 `outFFTData`（`SpectrumViewController.mm:198`），插值结果只写 `spectrum_view.maxHZ`（`:195`）。
   → **曲线横向分辨率仍然是 10.77 Hz/bin**，README 的「3 Hz」只对峰值数字成立。
2. **读数分辨率** ≈ 0.27 Hz（步进），**实际定位精度**受二次拟合误差限制（README 自述「最大约 3 Hz」）。
3. **加速度计频谱没有 Lagrange**：`AccelometerSpectrumViewController.mm:56-73` 只用 `vDSP_maxvi` + 线性换算。
4. 全仓 `lagrangeInterp` 调用点**仅此 1 处**。
5. 默认窗函数是 **Rectangular（不加窗）**（`Settings.bundle/Root.plist` → `DefaultValue = 0`），
   旁瓣泄漏会直接拉低顶点定位精度。

---

## 4. 关键参数速查表

| 项 | 值 | 出处 |
|---|---|---|
| 采样率 | 44100 Hz | `UserDefaults.m:62` |
| 音频 FFT 长度 | 4096（radix-2, log2m=12） | `UserDefaults.m:63`; `FFTHelper.mm:25-28` |
| 帧长 / hop | 4096 samples（≈92.9 ms，无重叠） | `UserDefaults.m:64`; `SpectrumViewController.mm:71-84` |
| **bin 间隔** | **10.766 Hz** | `SpectrumViewController.mm:125,133` |
| 通道 | 2（交织 → 取左声道） | `UserDefaults.m:57-61`; `SpectrumViewController.mm:184` |
| 硬件输入格式 | 8.24 定点 / 32bit / 非交织 / 2ch | `mo_audio.mm:445-453` |
| 定点缩放 | 1 / 2²⁴ | `mo_audio.mm:113,144` |
| 加速度计 FFT | 128 点 @ 128 Hz（bin = 1 Hz） | `AccelometerSpectrumView.h:29-32` |
| 加速度计 Scope/SPL | 32 Hz | `AccelometerScopeView.h:29`; `AccelometerSPLView.h:29` |
| 窗函数 | Rect(0) / Hamming(1) / Hanning(2) / Blackman(3)，**默认 0** | `FFTHelper.mm:99-115`; `SpectrumViewController.mm:407-410` |
| Lagrange 采样点 | 80（步进 ≈ 0.269 Hz） | `SpectrumViewController.mm:138,152` |
| 显示频率下限 | 10.0 Hz | `definitions.h:74` |
| UI 刷新节流 | 0.05 s | `definitions.h:76-77` |
| 麦克风增益默认值 | iPhone 15.0 dB / iPad 21.7 dB → `log10(g/2)` | `UserDefaults.m:126-139`; `SpectrumViewController.mm:110-114` |
| dB 换算（频谱） | `20·log10(1e6 · rawSPL)`（0 dB ↔ 20 µPa） | `definitions.h:57`; `FFTView.m:2887` |
| dB 换算（RMS） | `10·log10(rms) + 60.0` | `SPLView.h:38`; `SPLView.m:958-971` |

---

## 5. 信号发生器（全部手写，无第三方 DSP 库）

| 波形 | 实现 | 出处 |
|---|---|---|
| 正弦 | 相位累加器 + `sin()` | `ToneGeneratorViewController.mm:356-358` |
| 锯齿 | `theta/6` 取分数部分线性化 | `:359-361` |
| 三角 | `acos(cos(theta))` → **[0, π]，含直流偏置、幅度未归一** | `:362-364` |
| 粉噪 | `drand48()` + **7 极点 1/f IIR**（Paul Kellet "economy" 系数） | `PinkNoise.mm:39-54` |
| 棕噪 | `drand48()` + **一阶漏积分**（decay 0.99） | `BrownNoiseFilter.mm:24-48` |
| 扫频 | 按音频回调次数分段步进（<100→+1 … <100k→+7 Hz/回调） | `ToneGeneratorViewController.mm:390-415` |

粉噪核心（`PinkNoise.mm:47-54`）：

```c
for (int j = 0; j < NUM_FILTERS; j++)
    _pinkNoise[j] = coefficients[j]*_pinkNoise[j] + _whiteNoise*gains[j];
Float32 pink = _pinkNoise[0]+…+_pinkNoise[6] + _whiteNoise*0.5362;
buffer[i] = pink * 0.11f;
```

---

## 6. MoMu 依赖的真实边界

| 文件 | MoMu 派生 | 是否编译进 target | 角色 |
|---|---|---|---|
| `mo_audio.hh/.mm` | ✅ BSD | ✅ | **活跃**：RemoteIO 采集层 |
| `mo_def.hh` | ✅ | ✅（被 mo_audio 引用） | 常量宏 `ONE_PI/SAFE_DELETE/…` |
| `mo_gfx.hh/.mm` | ✅ | ❌ | **完全死代码**：OpenGL ES 1.0 工具，全仓零调用点 |
| `FFTHelper.hh/.mm` | ❌ 自研 GPL | ✅ | vDSP FFT 封装 + Lagrange 原语 |
| `PinkNoise/BrownNoiseFilter` | ❌ 自研 | ✅ | 1/f、1/f² 整形 |
| `PinkNoiseFFT` | ❌ 自研 | ❌ | **死代码**，且自身有内存分配 bug（见 §8） |

MoMu 本身**不含 FFT、不含音高检测**——只提供音频 I/O 封装。

---

## 7. 导航架构的两个亮点

### 7.1 用户可自定义 tab 顺序并持久化

`MainViewController.mm:82-110`（`viewWillAppear:`）读取 `TabbarTagOrder`，
重排 `customizableViewControllers` 后 `setViewControllers:`；
`:151-159`（`tabBar:didEndCustomizingItems:`）写回顺序；
`:144-149` 记录 `SelectedTabIndex`；`:107` 冷启动恢复上次所在 tab。

### 7.2 "Environment" 不是测量预设

`Subsonic/Environment.h/.m` 是**设备/OS 能力查询工具类**（`systemMajorVersion` ×16、`isLIPad` ×6、
`isPortrait` ×5、`normalizeEnvRelatedValue:` 屏幕缩放补偿、`peekModalViewController`），
与测量预设无关。真正的预设是 **Typical Settings / Exploration Settings**
（`FFTView.m:2319-2358` / `:2360-2399`）：

- **Typical**：对数刻度、Blackman 窗、关彩色、RTA 平均 0、噪声底 0.3
- **Exploration**：线性刻度、开彩色、隐藏标尺、噪声底 0.0

长按测量屏复位：`FFTView.m:2297-2316`。

---

## 8. 已知缺陷清单（客观事实）

| # | 问题 | 位置 |
|---|---|---|
| 1 | `malloc(fftSize >> 1 * sizeof(float))` 运算符优先级错误 → 实际只分配 `fftSize>>4`，随后 `vDSP_ztoc` 写 `fftSize` 个 float → **堆越界**（该文件未编译，暂时无害） | `PinkNoiseFFT.mm:36-37,72` |
| 2 | `PinkNoiseFFT` 从不调用 `vDSP_fft_zrip`，不是真 FFT | `PinkNoiseFFT.mm` 全文 |
| 3 | 三角波含直流偏置、幅度未归一 | `ToneGeneratorViewController.mm:363` |
| 4 | 棕噪滤波器 `prevOutputs` 分配后未用；二次乘 decay 使等效系数变 0.9801；`static prevOutput` 跨实例共享 | `BrownNoiseFilter.mm:32,26,44` |
| 5 | 扫频速率依赖音频缓冲周期，非时间恒定 | `ToneGeneratorViewController.mm:390-415` |
| 6 | 默认不加窗，旁瓣泄漏降低 Lagrange 顶点定位精度 | `Settings.bundle/Root.plist` |
| 7 | Lagrange 只细化峰值读数，不细化谱曲线 | `SpectrumViewController.mm:195,198` |
| 8 | 下混通道时按 `N=frameSize*numChannels` 取 stride=2，可读到 `2N-2`，超出本回调有效数据区 | `SpectrumViewController.mm:184`; `ScopeViewController.mm:87` |
| 9 | 声压标定基于固定常数 `DECIBEL_OFFSET=60.0` + 设备类型默认增益，**非绝对校准** | `SPLView.h:38`; `UserDefaults.m:126-139` |
| 10 | `AudioSession*` 旧 API 仍在用（iOS 7+ 废弃） | `mo_audio.mm:268,550,576,584,599,626,637,647,657` |
| 11 | `mo_gfx`、`MoAudio::vibrate()` 为死代码 | `mo_gfx.*`; `mo_audio.mm:859-862` |
| 12 | `Subsonic/Settings.m` **不存在**（只有常量头 `Settings.h`） | `Subsonic/` |
| 13 | 仓库根 `Settings.bundle/` 未进 target，内容是**另一个 App 的遗留字符串**（alarm 相关） | 仓库根目录 |
| 14 | `tr` / `tr-CY` / `tr-TR` 本地化目录未加入 Xcode variant group → **不随包分发** | `project.pbxproj` |
| 15 | `AccelometerSPLViewController.h:32` 的 key 是 `AcceloPLPanOffsetX`，与同组 `AcceloSPL*` 拼写不一致 | `AccelometerSPLViewController.h:32` |
| 16 | `definitions.h:42` 注释写「TSVファイル出力」，实际输出的是逗号分隔 CSV | `definitions.h:42` |
| 17 | `Info.plist` 残留 Fabric/Crashlytics 与 AdMob unit ID 常量，均无对应依赖 | `Info.plist`; `definitions.h:80-98` |
| 18 | `Main.storyboard:1416` Info tab 的 `userLabel="Accelometer SPL"` 是误导性历史标签 | `Main.storyboard:1416` |
| 19 | `AccelometerSpectrumViewController.mm:325` 注释写 "Update at 32Hz"，实际常量是 128 | `AccelometerSpectrumViewController.mm:325` |
| 20 | 工程无 `UINavigationController`，但 `self.navigationController` 仍被访问（恒为 nil，死代码残留） | `SpectrumViewController.mm:293-296` |

---

## 9. 数据导出

写 App 的 `Documents` 目录，`fopen(path,"a")` + `fprintf`，`NSTimer` 每 0.1 s 驱动。
文件名：`<本地化屏幕名>_<yyyy-MM-dd HH-mm-ss>.csv`。

| 数据源 | 表头 | 行格式 | 位置 |
|---|---|---|---|
| SND Spectrum | `Timestamp,LoudestFrequency(Hz),Loudness(dB)` | `<yyyy/MM/dd HH:mm:ss.SSS>,<Hz整数>,<dB两位小数>` | `FFTView.m:2816,2903` |
| SND Spectrogram | 首行 `1000Hz,2000Hz,…` | 每行 fftBufferSize-1 个 dB | `FFTView.m:2818-2824,2866-2898` |
| SND RMS | `Timestamp,Level(dB)` | `<时间戳>,<%g>` | `SPLView.m:838,877` |
| VIB RMS | `Timestamp,Acceleration(G)` | `<时间戳>,<%g>` | `AccelometerSPLView.m:842,879` |
| MF RMS | `Timestamp,MagneticForce(uT)` | `<时间戳>,<%g>` | `TeslameterSPLView.m:903,947` |

通过 `Info.plist` 的 `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` 暴露给
Files.app / Mac 端 iTunes 文件共享。

---

## 10. 本地化

磁盘 20 个 `.lproj` + `Base`，但**实际进 target 的只有 17 种**
（pbxproj 的三个 PBXVariantGroup：`Localizable.strings` / `Main.storyboard` / `LaunchScreen.storyboard`）：

`en, ja, zh-Hans, zh-Hant, zh-HK, zh-Hant-MO, de, ru, ko, ar, hi, es-419, pt-BR, es, pt-PT, th, vi`

**中文四套齐全**：`zh-Hans` / `zh-Hant` / `zh-HK` / `zh-Hant-MO`。

**编码坑**：`Localizable.strings` = UTF-16LE；`Main.strings` = **UTF-8**；`Root.strings` = UTF-16LE。

接线四路：`NSLocalizedString` 代码调用 / `Localizable.strings` / `Main.strings`（key = storyboard ObjectID，
如 `"4VG-jl-cvA.title" = "振动有效值";`）/ `Settings.bundle/*/Root.strings`（仅 en/ja）。

`Info.plist` 未本地化：`CFBundleDisplayName` 恒为 `Sonic Tools`。

---

## 11. 许可

- 主体 **GPL-3.0**（根 `LICENSE` 为全文，35,149 B；每个源文件头有三段式 GPL 声明）。
- MoMu 部分 **BSD 风格**（`mo_audio.hh:1-36` 完整保留署名）。
- README 末尾并列 GPLv3 摘要 + MoMu BSD 全文。
- **注**：该 App 曾在 App Store 分发，README 未说明 GPLv3 的源码提供义务。

---

## 12. 上游状态

- 上游 `tmatsugaki/Sonic-Tools-SVM`：69 stars，最后 push **2024-10-11**，22 个 commit。
- **App Store 条目 id1245046029 已全量下架**（详见 `BUILD.md`）。
- 上游 issue #6（2026-08-03）报告下架，**作者未回复**；issue #2（CSV 最大 500 条）作者回复过"已提交修复版本"。
