# 更新日誌

## [1.8.3] - 2026-10-08

### 介面更新

- 重排 Webcam + Screen 視窗：左側顯示合成預覽、輸出格式與錯誤訊息，右側分成擷取來源、音訊與子母畫面設定。
- 將單一顯示器選單移到右上方，方便在多螢幕環境選擇錄影目標。開始錄影後仍鎖定來源與版面設定。
- 以四角縮圖取代子母畫面位置選單，保留大小與輸出鏡像設定。
- 固定底部錄影控制列，讓自動停止、開始、暫停／繼續、停止及儲存狀態保持可見。
- 補齊繁中、簡中與義大利文的介面分區文字。錄影引擎、音訊混合、時間軸及既有 fragmented MP4 設定均未變更。

### 驗證與發行限制

- 新增 `verify_webcam_screen_ui.swift`，以模擬裝置在固定 780×555 視窗產生英文、繁中、義大利文共 30 張快照，涵蓋所有錄影狀態、缺少來源與長錯誤訊息。
- Release arm64 編譯、Webcam-only 與 Webcam + Screen 離線回歸、本地化語法與 `git diff --check` 通過。UI 快照使用合成測試畫面，不是實體裝置錄影驗收。
- 版本升至 1.8.3，build 183。發佈包僅提供 arm64，使用 ad-hoc 簽章且未經公證，透過 GitHub Release 手動下載；缺少對應的有效 EdDSA 產物簽章，因此保留既有 Sparkle feed。
- 實體攝影機錄影與播放、Mode 2 影音同步量測、裝置中斷及 30 分鐘連續錄影驗證仍未完成。

## [1.8.2] - 2026-10-08

### 新功能

- 新增獨立 Webcam 錄影入口，macOS 12.3 以上可用；選擇攝影機與可選麥克風即可錄製 SDR MOV，不需要螢幕錄製權限。預覽鏡像只影響預覽，不會鏡像輸出影片。支援倒數、暫停／繼續、停止、自動停止與共用快捷鍵。
- Webcam-only 模式不支援系統音訊、AEC、錄影中麥克風靜音、HDR 或透明影片。
- 新增獨立 Webcam + Screen 模式，macOS 13 以上可錄製單一顯示器與攝影機子母畫面。可調整四角位置、大小及輸出鏡像，SDR 輸出最高 1920×1080、30 fps，容器為 MP4 或 MOV，使用 H.264／HEVC 並依可用編碼器回退。
- Webcam + Screen 可選麥克風與系統音訊；兩者同時錄製時，可將音訊混成單一音軌，或保留分離音軌。靜止桌面不會中止 Webcam 畫面更新。
- 兩種 Webcam 模式各自使用錄影後端，不與舊有螢幕錄影共用 writer。Webcam + Screen 不支援視窗、App 或區域擷取；QuickRecorder 視窗會排除在畫面外，且不可同時使用 macOS Presenter Overlay。
- Webcam + Screen 不支援 HDR、透明影片、AEC 或錄影中麥克風靜音。既有螢幕錄影的 fragmented MP4 設定維持不變；兩種新 Webcam 模式都沒有 fragmented MP4 中斷保護，異常結束時檔案可能無法播放。

### 修復

- Webcam + Screen 錄影啟動時暫存並重播待處理影格，避免錄影時間軸建立期間遺失完整影格。
- 修復非同步音訊混音與封裝的資產生命週期：保留來源影片與混音音訊資產，直到封裝完成。混音或封裝失敗時保留原始多軌錄影，並提供檔案位置。

### 發行與文件

- 專案遷移至 public `fun-ed/QuickRecorderNext`，舊 `fun-ed/QuickRecorder` 保留為 Git upstream。App 的 Sparkle feed URL 指向新 repo；1.8.2 以 GitHub Release 提供手動下載，不建立缺少有效產物簽章的 Sparkle 更新項目。
- 更新 README、`CLAUDE.md` 與 `CLAUDE_zh-TW.md`，補充模式操作、離線驗證與實機驗收限制；App「關於」視窗四個語系的原始碼連結及 Markdown 下載入口均指向 `fun-ed/QuickRecorderNext`。

### 驗證與限制

- 離線檢查涵蓋 Webcam-only 模擬回呼，以及 Webcam + Screen 的生命週期、時間軸、待處理影格、合成器與 MP4／MOV 寫入和重封裝；不會使用實體攝影機或麥克風。
- 尚未完成實體攝影機錄影與播放、以 100 ms 門檻量測影音同步、裝置中斷及 30 分鐘連續錄影驗證。1.8.2 發佈包僅提供 arm64，使用 ad-hoc 簽名且未經公證。

## [1.8.1] - 2026-09-27

### 依賴更新

- Sparkle: 2.9.6 → 2.10.0
- KeyboardShortcuts: 2.4.0 → 3.1.0（major 升級；3.0.0 的破壞性變更 `defaultShortcut` → `initialShortcut` 本專案未使用）
- MatrixColorSelector: `0853e68`（main 最新提交，無變更）
- AECAudioStream: `0eab971`（main 最新提交，無變更）
- SwiftLAME: `45d1b02`（無變更）。此提交即上游 `main` 分支與 tag `0.1.0`。上游預設分支 `develop`（`e8256a8`）較新但未發布，本專案不跟進

### 其他

- 專案遷移至 `fun-ed/QuickRecorder`，Sparkle 更新來源 `SUFeedURL` 改指向新 repo 的 `appcast.xml`
- 更新 README、CLAUDE.md 的建置說明與依賴版本

## [1.8.0] - 2026-09-01

### 依賴更新

- Sparkle: 2.9.1 → 2.9.6
- KeyboardShortcuts: 2.4.0 → 2.4.0（依配置規則解析）
- MatrixColorSelector: `0853e68` → `0853e68`（main 最新提交）
- AECAudioStream: `0eab971` → `0eab971`（main 最新提交）
- SwiftLAME: `e8256a8` → `45d1b02`（main 最新提交）

### 文件整理

- 移除過時的開發流程文件與驗證文件
- 更新 README 錄影中斷保護說明，反映音頻錄影的實際限制

## [1.7.4] - 2026-05-20

### 緊急修復 🚨

- **錄影只有 1-2 秒的 regression（涵蓋 v1.7.3 未修復的場景）**
  - v1.7.3 只在「mic + 系統音 + remux 三軌」模式停用 fragmented MP4，但實測**任何含 audio input 的錄影**都會觸發相同 bug：AVAssetWriter 在第一個 1s fragment 後 `awInput.isReadyForMoreMediaData` 永久回傳 false，後續 audio sample 被靜默丟棄。
  - **症狀**：3 個獨立失敗檔的 ffprobe 顯示完全相同的 47 AAC frames（=1.0s @ 48kHz），與實際錄影長度（5 分鐘）完全脫鉤
  - **根因**：SCStream 透過獨立 callback 投遞 video/audio sample buffer，速率不同，無法在 fragment boundary 維持同步
  - **修復**：擴大跳過條件——只要 `recordMic` 或 `recordWinSound` 任一啟用就停用 `movieFragmentInterval`（僅純螢幕無音頻錄影才啟用 fragment 保護）
  - 影響：螢幕 + 任何音頻錄影中斷時整檔可能損壞（與 v1.7.1 行為相同）；正常按 stop（含 Cmd+Q）仍正常

### 已知限制（v1.7.4 更新後）

| 錄影模式 | Fragmented MP4 保護 | 中斷時表現 |
|---------|---------------------|-----------|
| 純螢幕（無任何音頻） | ✅ 啟用 | 最多遺失 1 秒 |
| 螢幕 + 任何音頻（系統音 / 麥克風 / 兩者） | ❌ 停用 | 整檔可能損壞 |
| HDR | ❌ 停用 | 整檔可能損壞 |

### 後續調查項目

- 為何 AVAssetWriter fragmented mode 與 SCStream audio sample buffer 無法同步（可能解法：dispatch queue 序列化 append、segmented writing、或重寫 audio buffering）

## [1.7.3] - 2026-05-14

### 緊急修復 🚨

- **多軌音頻模式下錄影只有幾秒鐘的 regression**
  - v1.7.2 重新啟用 fragmented MP4 後，當 `recordMic + recordWinSound + remuxAudio` 三個都啟用時，AVAssetWriter 同時管理 video + 2 個 audio input。Fragment boundary 對齊在三個 input 上出現問題，只寫了第一個 fragment（≈1-3 秒）後續 sample 全被丟棄。
  - 症狀：錄了 5 分鐘但檔案 duration 只有 1-3 秒，fps 從 60 變成 14.99
  - 修復：多軌音頻模式下不啟用 fragmentInterval（單軌、僅系統音、僅麥克風仍啟用）
  - 影響：多軌音頻模式錄影中斷時檔案仍可能損壞（與 v1.7.1 相同）；但**只要正常按 stop（含 Cmd+Q）就無問題**

### 已知限制

| 錄影模式 | Fragmented MP4 保護 | 中斷時表現 |
|---------|---------------------|-----------|
| 純螢幕（無音頻） | ✅ 啟用 | 最多遺失 1 秒 |
| 螢幕 + 系統音 | ✅ 啟用 | 最多遺失 1 秒 |
| 螢幕 + 麥克風 | ✅ 啟用 | 最多遺失 1 秒 |
| 螢幕 + 系統音 + 麥克風 + remux | ❌ 停用 | 整個檔案可能損壞 |
| HDR | ❌ 停用 | 整個檔案可能損壞 |

## [1.7.2] - 2026-05-14

### 修復

- **重新啟用 Fragmented MP4 防止錄影中斷檔案損壞**（修復 commit `a6c645e` 之後再次出現的 moov atom 遺失問題）
  - `RecordEngine.swift`：在非 HDR 模式下啟用 `movieFragmentInterval = 1.0s`
  - 將 fragment interval 從 0.5s 改為 1.0s 給 encoder 多一點 buffer 時間
  - 跳過 HDR 模式以避免 VTVideoEncoderMalfunctionErr (-16341)
  - 異常終止時最多遺失最後 1 秒，其餘檔案仍可正常播放

### 新增

- **啟動時自動偵測未完成錄影**
  - `QuickRecorderApp.swift::cleanupOrphanRecordings()`：在 `applicationDidFinishLaunching` 掃描 saveDirectory
  - 偵測 `.mp4.mp4.mp4` / `.mov.mov.mov` / `.mp4.mp4` / `.mov.mov` 等中斷殘留檔
  - 透過通知告知使用者，方便手動恢復

### 建議設定（避免損壞 + 易於修復）

| 設定 | 推薦值 | 原因 |
|------|--------|------|
| encoder | H.264 | 短 GOP，中斷後容易救回 |
| videoFormat | mp4 | Fragmented MP4 最穩 |
| recordHDR | false | 避免 -16341 encoder error |
| videoQuality | 1.0 (high) | 高 bitrate，frame 自含資訊多 |
| frameRate | 60 | 細節多，可救資料量大 |

## [1.7.1] - 2026-04-21

### 安全性修復 🚨

- **Sparkle 升級至 2.9.1**：修補 [CVE-2025-0509](https://github.com/advisories/GHSA-wc9m-r3v6-9p5h)（Signing Checks Bypass，CVSS 7.4）
  - 攻擊者可在舊版 Sparkle 中以未授權 payload 取代簽名更新檔
  - 影響版本：Sparkle ≤ 2.6.3

### 依賴更新

- KeyboardShortcuts: 2.2.4 → 2.4.0

### 修復

- 修復 macOS 14+ 對 `AVCaptureDeviceTypeExternal` 的 Continuity Camera deprecation warning
  - `Info.plist` 加入 `NSCameraUseContinuityCameraDeviceType`
  - `SCContext.getCameras()` / `getiDevice()` 在 macOS 14+ 改用 `.external` + `.continuityCamera`

## [未發布] - 2024-12-23

### 新增功能

#### 麥克風靜音切換（來自 PR #220）
- 錄影時可切換麥克風靜音/取消靜音
- 在狀態列控制器加入麥克風按鈕
- 支援快捷鍵設定（設定 > Hotkey > Toggle Microphone Mute）
- 靜音時會輸出靜音音訊以保持音軌同步

#### Debug Log 功能
- 在 Help 選單加入「View Debug Log」選項
- 可查看錄影過程的診斷資訊
- Log 檔案位置：`/tmp/qr-debug.log`

### 修復

#### 錄影 Session 狀態追蹤
- 新增 `sessionStarted` 狀態變數追蹤 AVAssetWriter session
- 如果錄影開始後立即停止（尚未收到任何 frame），顯示「Recording Cancelled」通知
- 避免產生無法播放的損壞檔案

### 已知問題

#### Fragmented MP4（已停用）
- `movieFragmentInterval` 功能已停用
- 原因：與 VideoToolbox 編碼器不相容，會導致錯誤 -16341
- 目前錄影如果異常終止（App 崩潰），檔案可能損壞
- 正常停止錄影不受影響

**修改的檔案：**

| 檔案 | 修改內容 |
|------|----------|
| `SCContext.swift` | 新增 `sessionStarted`、`isMicMuted`、`debugLog()` 函數 |
| `RecordEngine.swift` | 麥克風靜音處理、debug log |
| `QuickRecorderApp.swift` | Help 選單加入 Debug Log、麥克風靜音快捷鍵 |
| `SettingsView.swift` | 麥克風靜音快捷鍵設定 UI |
| `StatusBar.swift` | 麥克風靜音按鈕 |
