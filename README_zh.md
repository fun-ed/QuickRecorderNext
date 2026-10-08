# 
<p align="center">
<img src="./QuickRecorder/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="200" height="200" />
<h1 align="center">QuickRecorder</h1>
<h3 align="center">多功能、轻量化、高性能的 macOS 屏幕录制工具<br><a href="./README.md">[English Version]</a><br><a href="https://lihaoyun6.github.io/quickrecorder/">[软件主页]</a>
</p>

> 本仓库（[fun-ed/QuickRecorderNext](https://github.com/fun-ed/QuickRecorderNext)）延续
> [fun-ed/QuickRecorder](https://github.com/fun-ed/QuickRecorder)，后者是
> [lihaoyun6/QuickRecorder](https://github.com/lihaoyun6/QuickRecorder) 的维护分支。
> 本仓库新增独立 Webcam 模式，并保留录制文件完整性修复与依赖更新
> （见 [CHANGELOG.md](./CHANGELOG.md)）。下方的软件主页与 Homebrew tap 属于原始上游项目。

## 运行截图
<p align="center">
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="./img/preview_dark.png">
  <source media="(prefers-color-scheme: light)" srcset="./img/preview.png">
  <img alt="QuickRecorder Screenshots" src="./img/preview.png" width="840"/>
</picture>
</p>

## 安装与使用
### 系统版本要求:
- macOS 12.3 及更高版本  

### 安装:
可[点此前往](https://github.com/fun-ed/QuickRecorderNext/releases/latest)下载本分支的最新版 DMG。QuickRecorder 1.8.3 是 build 183，目前仅提供 arm64 版本。打开 DMG，将 `QuickRecorder.app` 拖入“应用程序”文件夹.

Homebrew tap 安装的是**上游**版本, 而非本分支:

```bash
brew install lihaoyun6/tap/quickrecorder
```

### 从源码构建:
需要 Xcode 26 或更高版本 (KeyboardShortcuts 3.x 需要 swift-tools 6.2).

```bash
./build.sh           # Debug 构建, 安装到 /Applications/QuickRecorder-Dev.app 并运行
./build-release.sh   # arm64 Release 构建, 在 build-release/ 生成 ad-hoc 签名的 DMG
```

1.8.3 Release DMG 仅做 ad-hoc 签名, 未经公证. 首次启动若被 macOS 阻止, 请在 **系统设置 > 隐私与安全性** 中允许.
1.8.3 请从 GitHub Releases 下载。没有对应产物的有效签名前，不发布 Sparkle 更新项。


### 特色 / 使用:
- 使用 SwiftUI 编写, 体积小巧轻量化. 软件大小仅有不到 10MB, 无任何累赘功能. 

- 支持窗口录制, App 录制, 录制移动设备等; 支持窗口声音内录, 鼠标高亮, 隐藏桌面文件等功能. 
- 完整支持 macOS 14 新增的 **[演讲者前置](https://support.apple.com/zh-cn/guide/facetime/fctm6333f4bd/mac)** 特性, 可在实时叠加摄像头画面 (低版本 macOS 可以使用悬浮窗模式).  
- 支持 `HEVC with Alpha` 特性, 可在输出文件中包含 Alpha 通道 (目前仅 iMovie 与 FCPX 支持此特性)
- 更多功能陆续开发中...  

### Webcam 录制

打开主面板，选择 **Webcam** 进行仅摄像头录制，或选择 **摄像头＋屏幕（Webcam + Screen）**，将摄像头画面合成到一个显示器录制中。这是独立录制模式，不是现有屏幕／窗口录制流程中的叠加选项.

**Webcam** 支持 macOS 12.3 及更高版本。选择摄像头，并可选麦克风。此模式不需要“屏幕录制”权限，也不录制系统声音；不支持麦克风静音、回声消除、HDR 或透明视频。先开始预览，再选择“开始录制”。输出为 SDR MOV。“镜像预览”只影响预览，不会镜像保存的视频。需要摄像头权限；选择麦克风时还需要麦克风权限.

**摄像头＋屏幕（Webcam + Screen）** 需要 macOS 13 或更高版本、摄像头权限和“屏幕录制”权限。选择一个显示器、摄像头以及可选麦克风，也可录制系统声音。可调整画中画的角落和大小；“镜像保存视频中的摄像头画面”会影响输出。此模式仅支持 SDR，最高 1920×1080、30 fps；容器为 MP4 或 MOV，并按所选 H.264／HEVC 编码设置使用系统支持的编码器。不支持 HDR、透明视频、麦克风静音或回声消除。若同时录制系统声音和麦克风，可用“将麦克风录制到主音轨”将两者混为一个音轨；关闭后会保留为独立音轨。QuickRecorder 窗口不会录入画面。录制前请关闭 macOS Presenter Overlay。此模式不支持窗口、App 或区域录制.

两种模式都支持倒数、暂停／继续、停止和可选自动停止。可使用模式窗口中的控制按钮或已设置的录制快捷键。文件会保存到当前选择的保存文件夹。停止后请等到“正在保存录制…”结束再退出应用，尤其是 Webcam + Screen 正在混合音频时.

这两种 Webcam 模式都不使用 fragmented MP4 中断保护。若应用崩溃或被强制退出，输出文件可能无法播放.

### 离线验证

在仓库根目录运行:

```bash
swift verify_filename_logic.swift
swift verify_webcam_logic.swift
swift verify_webcam_screen_logic.swift
```

文件名脚本检查三重扩展名处理。Webcam 脚本使用模拟摄像头回调，不会访问实体设备。Webcam + Screen 脚本检查从生产代码提取的生命周期、时间轴、音频暂停、待处理影格、合成器和音频重封装逻辑，也会执行合成画面的 MP4／MOV 编码解码及保留视频编码的重封装。这些离线检查不验证真实摄像头录制与播放、实测影音同步、设备断开或 30 分钟连续录制.

## 常见问题
**1. 主面板关闭之后在哪里重新打开?**  
> 单击 QuickRecorder 的 Dock 栏图标或菜单栏图标即可随时重新呼出主功能面板.  

**2. 为什么 QuickRecorder 不是沙盒 App?**  
> 苹果沙盒权限管理机制比较复杂, 使用起来麻烦. 加之 QuickRecorder 并没有上架 App Store的打算, 故没有做成沙盒 App.

**3. 如何在后期剪辑中独立控制系统声音和麦克风录音的音量?**
> 在现有屏幕录制模式中，默认会在录制结束后将麦克风音频混入主音轨。关闭 `Record Microphone to Main Track` 可将系统声音与麦克风音频保留为独立音轨。使用 Webcam + Screen 时，在两种音源都开启后可在模式窗口中设置此选项.

**4. 如何排查录制问题?**
> QuickRecorder 包含 Debug Log 功能用于故障排查。前往 **Help > View Debug Log** 查看诊断信息。日志文件位于 `/tmp/qr-debug.log`。

**5. 如果录制过程中被强制结束 (Force Quit / Crash) 会怎样?**
> 在现有屏幕录制模式中，只有无音频且未开启 HDR 的录制才使用 **fragmented MP4**。QuickRecorder 每秒写入一次文件索引，因此应用被强制退出或崩溃时，最多损失最后一秒。启用任何音频输入或 HDR 都会停用此保护，因为 fragmented MP4 可能导致编码器或同步错误.
>
> 独立的 **Webcam** 和 **摄像头＋屏幕（Webcam + Screen）** 模式不使用 fragmented MP4；应用崩溃或被强制退出时，文件可能无法播放。下次启动时，QuickRecorder 也会通知保存目录中检测到的未完成录影.

**6. 推荐设定（降低现有屏幕录制模式的中断损坏风险）:**
> | 设定 | 推荐值 | 原因 |
> |------|--------|------|
> | Encoder | **H.264** | GOP 较短，中断后容易恢复 |
> | Format | **MP4** | Fragmented MP4 在此容器最稳定 |
> | Record HDR | **关闭** | 保留 Fragmented MP4 保护 |
> | Alpha Channel | **关闭** | 避免强制 HEVC + MOV 路径 |
> | Quality | **High** | 高码率，frame 自含信息多 |
> | Frame Rate | **60** | 每秒可恢复数据量较多 |
>
> 在现有屏幕录制模式中，若同时录制系统声音和麦克风并启用 `Record Microphone to Main Track`，按下停止后请**等待 10-15 秒再退出 App**，让 QuickRecorder 完成音频混合；否则可能留下临时档案 `.mp4.mp4.mp4`.

## 赞助
<img src="./img/donate.png" width="352"/>

## 致谢
[Azayaka](https://github.com/Mnpn/Azayaka) @Mnpn  
> 灵感来源以及屏幕录制引擎的部分代码来自于 Azayaka 项目, 同时我也是此项目的代码贡献者之一   

[KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) @sindresorhus  
> QuickRecorder 使用此swift库来处理快捷键事件  


[SwiftLAME](https://github.com/hidden-spectrum/SwiftLAME) @Hidden Spectrum
> QuickRecorder 使用此swift库来处理 MP3 输出

[Sparkle](https://github.com/sparkle-project/Sparkle) @sparkle-project
> QuickRecorder 使用此框架进行应用内更新

[AECAudioStream](https://github.com/lihaoyun6/AECAudioStream) / [MatrixColorSelector](https://github.com/lihaoyun6/MatrixColorSelector) @lihaoyun6
> 用于麦克风回声消除与颜色选择器

[ChatGPT](https://chat.openai.com) @OpenAI  
> 注: 本项目部分代码使用 ChatGPT 生成或重构整理
