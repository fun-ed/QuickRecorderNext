#
<p align="center">
<img src="./QuickRecorder/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="200" height="200" />
<h1 align="center">QuickRecorder</h1>
<h3 align="center">A lightweight and high-performance screen recorder for macOS<br><a href="./README_zh.md">[中文版本]</a><br><a href="https://lihaoyun6.github.io/quickrecorder/">[Landing Page]</a>
</p>

> This repository ([fun-ed/QuickRecorderNext](https://github.com/fun-ed/QuickRecorderNext)) continues
> [fun-ed/QuickRecorder](https://github.com/fun-ed/QuickRecorder), a maintained fork of
> [lihaoyun6/QuickRecorder](https://github.com/lihaoyun6/QuickRecorder). It adds independent webcam modes
> alongside recording-integrity fixes and dependency updates (see [CHANGELOG.md](./CHANGELOG.md)).
> The landing page and Homebrew tap below belong to the original upstream.

## Screenshot
<p align="center">
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="./img/preview_en_dark.png">
  <source media="(prefers-color-scheme: light)" srcset="./img/preview_en.png">
  <img alt="QuickRecorder Screenshots" src="./img/preview_en.png" width="840"/>
</picture>
</p>

## Installation and Usage
### System Requirements:
- macOS 12.3 and Later

### Install:
Download the latest release DMG of this fork [here](https://github.com/fun-ed/QuickRecorderNext/releases/latest). QuickRecorder 1.8.2 is build 182 and is available for arm64 only. Open the DMG and drag `QuickRecorder.app` to the Applications folder.

The Homebrew tap installs the **upstream** build, not this fork:

```bash
brew install lihaoyun6/tap/quickrecorder
```

### Build from source:
Requires Xcode 26 or later (KeyboardShortcuts 3.x needs swift-tools 6.2).

```bash
./build.sh           # Debug build, installs /Applications/QuickRecorder-Dev.app and runs it
./build-release.sh   # arm64 Release build, ad-hoc signed DMG in build-release/
```

The 1.8.2 release DMG is ad-hoc signed, not notarized. On first launch, macOS may block it; allow it in **System Settings > Privacy & Security**.
Use GitHub Releases for 1.8.2. A Sparkle update-feed entry is not published until a matching
artifact signature is available.


### Features/Usage:
- You can use QuickRecorder to record your screens / windows / applications / mobile devices... etc.

- QuickRecorder supports driver-free audio loopback recording, mouse highlighting, screen magnifier and many more useful features.  
- The new **"[Presenter Overlay](https://support.apple.com/guide/facetime/presenter-overlay-video-conferencing-fctm6333f4bd/mac)"** in macOS 14 was fully supported by QuickRecorder, which can overlay the camera in real time on your recording *(macOS 12/13 can only use camera floating window)*  
- QuickRecorder is able to record `HEVC with Alpha` video format, that can contain alpha channel in the output file *(currently only iMovie and FCPX support this feature)*  

### Webcam recording

Open the main panel and choose **Webcam** for webcam-only recording or **Webcam + Screen** to record a display with a webcam picture-in-picture. These are separate recording modes, not options in the existing screen/window capture flow.

**Webcam** works on macOS 12.3 and later. Select a camera and, if wanted, a microphone. It does not need Screen Recording permission or capture system audio. Microphone mute, echo cancellation, HDR, and alpha transparency are not supported. Start the preview, then choose **Start recording**. The saved video is SDR MOV. **Mirror preview** affects only the preview, not the saved video. Camera permission is required; microphone permission is needed if you select a microphone.

**Webcam + Screen** requires macOS 13 or later, camera permission, and Screen Recording permission. Select one display, a camera, and optionally a microphone. You can also record system audio. Choose the picture-in-picture corner and size; **Mirror webcam in saved video** changes the saved image. The mode is SDR only, with output up to 1920×1080 and 30 fps, in MP4 or MOV with the selected H.264 or HEVC setting when supported. HDR, alpha transparency, microphone mute, and echo cancellation are not supported. If you record both system audio and microphone, choose whether to mix them into one track or keep separate tracks. QuickRecorder windows are excluded. Turn off macOS Presenter Overlay before recording. Window, app, and region capture are not available in this mode.

Both modes support countdown, pause/resume, stop, and optional auto-stop. Use the mode window's controls or the configured recording shortcuts. Files go to the selected save folder. After stopping, wait until **Saving recording…** finishes before quitting, especially when Webcam + Screen is mixing audio.

Neither Webcam mode uses the fragmented MP4 protection described below. A crash or force quit can leave its output unplayable.

### Offline verification

Run these commands from the repository root:

```bash
swift verify_filename_logic.swift
swift verify_webcam_logic.swift
swift verify_webcam_screen_logic.swift
```

The filename script checks triple-extension naming. The Webcam script exercises simulated camera output callbacks, not physical devices. The Webcam + Screen script checks production-extracted lifecycle, timeline, audio-pause, pending-frame, compositor, and audio-remux logic, including synthetic MP4/MOV encode/decode and codec-preserving remux. These offline checks do not validate real camera recording or playback, measured audio/video sync, device disconnects, or a 30-minute recording soak.

## Q&A
**1. Where can I reopen the main panel after closing it?**
> Click the Dock tile or Menubar icon of QuickRecorder to reopen the main panel at any time.

**2. Why does QuickRecorder not a sandbox app?**
> QuickRecorder has no plans to be uploaded to the App Store, so it does not need to be designed as a sandbox app.  

**3. How to independently control the volume of system sound and sound from microphone in other video editor?**
> In existing screen-capture modes, QuickRecorder merges microphone audio into the main track by default. Turn off `Record Microphone to Main Track` to keep system audio and microphone audio on separate tracks. In Webcam + Screen, this option is in the mode window and appears when both inputs are selected.

**4. How can I troubleshoot recording issues?**
> QuickRecorder includes a debug log feature for troubleshooting. Go to **Help > View Debug Log** to view diagnostic information. The log file is located at `/tmp/qr-debug.log`.

**5. What happens if recording is interrupted (force quit / crash)?**
> In the existing screen-capture modes, only recordings without audio or HDR use **fragmented MP4**. QuickRecorder writes the metadata index every second, so a force quit or crash can lose at most the last second of those recordings. Any audio input or HDR disables this protection because fragmented writing can cause encoder or synchronization failures.
>
> The independent **Webcam** and **Webcam + Screen** modes do not use fragmented MP4; a crash or force quit may leave those files unplayable. QuickRecorder also notifies you about interrupted recordings found in the save folder on next launch.

**6. Recommended settings for existing screen-capture modes to reduce interruption risk:**
> | Setting | Recommended | Why |
> |---------|-------------|-----|
> | Encoder | **H.264** | Short GOP — recovers more cleanly after interruption |
> | Format | **MP4** | Fragmented MP4 most stable in this container |
> | Record HDR | **Off** | Keeps fragmented MP4 protection active |
> | Alpha Channel | **Off** | Avoids forced HEVC + MOV path |
> | Quality | **High** | Higher bitrate = more self-contained frames |
> | Frame Rate | **60** | More data per second to recover |
>
> In existing screen-capture modes, if you record system audio and microphone audio with `Record Microphone to Main Track` enabled, **wait 10–15 seconds after pressing stop** before quitting so QuickRecorder can mix the audio. Otherwise, a temporary `.mp4.mp4.mp4` file may remain on disk.

## Donate
<img src="./img/donate.png" width="350"/>

## Thanks
[Azayaka](https://github.com/Mnpn/Azayaka) @Mnpn
> The source of inspiration and part of the code of the screen recording engine comes from the Azayaka project, and I am also one of the code contributors to this project

[KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) @sindresorhus  
> QuickRecorder uses this swift library to handle shortcut key events  

[SwiftLAME](https://github.com/hidden-spectrum/SwiftLAME) @Hidden Spectrum
> QuickRecorder uses this swift library to handle MP3 output

[Sparkle](https://github.com/sparkle-project/Sparkle) @sparkle-project
> QuickRecorder uses this framework for in-app updates

[AECAudioStream](https://github.com/lihaoyun6/AECAudioStream) / [MatrixColorSelector](https://github.com/lihaoyun6/MatrixColorSelector) @lihaoyun6
> Used for microphone echo cancellation and the color picker

[ChatGPT](https://chat.openai.com) @OpenAI
> Note: Part of the code in this project was generated or refactored using ChatGPT.
