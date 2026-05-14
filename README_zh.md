# 
<p align="center">
<img src="./QuickRecorder/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="200" height="200" />
<h1 align="center">QuickRecorder</h1>
<h3 align="center">多功能、轻量化、高性能的 macOS 屏幕录制工具<br><a href="./README.md">[English Version]</a><br><a href="https://lihaoyun6.github.io/quickrecorder/">[软件主页]</a>
</p>

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
可[点此前往](../../releases/latest)下载最新版安装文件. 或使用homebrew安装:  

```bash
brew install lihaoyun6/tap/quickrecorder
```

### 特色 / 使用:
- 使用 SwiftUI 编写, 体积小巧轻量化. 软件大小仅有不到 10MB, 无任何累赘功能. 

- 支持窗口录制, App 录制, 录制移动设备等; 支持窗口声音内录, 鼠标高亮, 隐藏桌面文件等功能. 
- 完整支持 macOS 14 新增的 **[演讲者前置](https://support.apple.com/zh-cn/guide/facetime/fctm6333f4bd/mac)** 特性, 可在实时叠加摄像头画面 (低版本 macOS 可以使用悬浮窗模式).  
- 支持 `HEVC with Alpha` 特性, 可在输出文件中包含 Alpha 通道 (目前仅 iMovie 与 FCPX 支持此特性)
- 更多功能陆续开发中...  

## 常见问题
**1. 主面板关闭之后在哪里重新打开?**  
> 单击 QuickRecorder 的 Dock 栏图标即可随时重新呼出主功能面板.  

**2. 为什么 QuickRecorder 不是沙盒 App?**  
> 苹果沙盒权限管理机制比较复杂, 使用起来麻烦. 加之 QuickRecorder 并没有上架 App Store的打算, 故没有做成沙盒 App.

**3. 如何在后期剪辑中独立控制系统声音和麦克风录音的音量?**
> QuickRecorder 默认会在录制结束后将麦克风输入的音频合并到主音轨. 如果需要后期编辑的话, 可以在设置面板中关闭 `将麦克风录制到主音轨` 选项. 关闭后系统声音和麦克风将分别录制为两条音轨, 可以独立编辑.

**4. 如何排查录制问题?**
> QuickRecorder 包含 Debug Log 功能用于故障排查。前往 **Help > View Debug Log** 查看诊断信息。日志文件位于 `/tmp/qr-debug.log`。

**5. 如果录制过程中被强制结束 (Force Quit / Crash) 会怎样?**
> 从 v1.7.2 起，QuickRecorder 启用 **Fragmented MP4** 写入 — 文件的索引每 1 秒写入一次，不再只在结束时写。即使录制中途 App 被强制结束或崩溃，**最多只损失最后 1 秒**的画面，其余片段仍可正常播放。下次启动 App 时，也会自动扫描保存目录，提示是否有未完成的录影。
>
> **注意:** `Record HDR` 开启时，此保护会**自动停用**（HEVC Main10 与 fragmented MP4 不相容，会触发编码器错误）。录制 HDR 内容时若中断，文件仍可能无法播放。

**6. 推荐设定（降低损坏风险）:**
> | 设定 | 推荐值 | 原因 |
> |------|--------|------|
> | Encoder | **H.264** | GOP 较短，中断后容易恢复 |
> | Format | **MP4** | Fragmented MP4 在此容器最稳定 |
> | Record HDR | **关闭** | 保留 Fragmented MP4 保护 |
> | Alpha Channel | **关闭** | 避免强制 HEVC + MOV 路径 |
> | Quality | **High** | 高码率，frame 自含信息多 |
> | Frame Rate | **60** | 每秒可恢复数据量较多 |
>
> 若使用多轨音频模式（`Record Microphone to Main Track` + 系统音 + 麦克风全部开启），按下停止后请**多等 10-15 秒再关闭 App**，让音频混合流程跑完 — 否则可能会留下临时档案 `.mp4.mp4.mp4`。

## 赞助
<img src="./img/donate.png" width="352"/>

## 致谢
[Azayaka](https://github.com/Mnpn/Azayaka) @Mnpn  
> 灵感来源以及屏幕录制引擎的部分代码来自于 Azayaka 项目, 同时我也是此项目的代码贡献者之一   

[KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) @sindresorhus  
> QuickRecorder 使用此swift库来处理快捷键事件  


[SwiftLAME](https://github.com/hidden-spectrum/SwiftLAME) @Hidden Spectrum
> QuickRecorder 使用此swift库来处理 MP3 输出

[ChatGPT](https://chat.openai.com) @OpenAI  
> 注: 本项目部分代码使用 ChatGPT 生成或重构整理
