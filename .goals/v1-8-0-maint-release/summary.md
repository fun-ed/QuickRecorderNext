# Summary — QuickRecorder v1.8.0 Maintenance Release

## 最終結果

Builder 與 Inspector 迭代 2 輪後達成目標，Inspector 最終判決 **PASS**（9/9 檢查全數通過）。
成品：`build-release/QuickRecorder-1.8.0-arm64.dmg`（本機產物，已 gitignore）。

## 各驗收標準達成情形

| # | 驗收標準 | 結果 | 證據 |
|---|---------|------|------|
| 1 | 依賴更新至最新可用版本 | ✅ | Package.resolved + pbxproj：Sparkle 2.9.1→2.9.6（2.x 最高 tag）、SwiftLAME e8256a8→45d1b021（main HEAD）；KeyboardShortcuts 2.4.0、MatrixColorSelector、AECAudioStream 經查已為最新（branch/minor 約束下無新版） |
| 2 | Release build 成功 | ✅ | `xcodebuild -configuration Release` → `** BUILD SUCCEEDED **`（ad-hoc 簽署） |
| 3 | 版本號 1.8.0 / build 180 | ✅ | pbxproj 兩組 config 均 MARKETING_VERSION=1.8.0、CURRENT_PROJECT_VERSION=180 |
| 4 | CHANGELOG 新增 1.8.0 條目 | ✅ | `## [1.8.0] - 2026-09-01` zh-TW 條目，風格與既有條目一致 |
| 5 | 移除過時開發文件且無殘留引用 | ✅ | 刪除 test_filename_verification.md、BUG_REPORT_TRIPLE_EXTENSION.md、build.md、SPEC.md；CLAUDE.md/README.md/README_zh.md 相關引用一併清理 |
| 6 | 新增 build-release.sh 產出 script | ✅ | arm64 Release、ad-hoc、hdiutil UDZO 打包、不啟動 app、輸出至 gitignored 的 build-release/ |
| 7 | DMG 完整性驗證 | ✅ | hdiutil verify 通過；掛載檢查 CFBundleShortVersionString=1.8.0、lipo =arm64、/Applications symlink、ad-hoc 簽章（迭代 1 與 2 各驗一次） |
| 8 | DMG 不被版控追蹤 | ✅ | `.gitignore:94 build-release/`；`git ls-files '*.dmg'` 空 |

## 迭代歷史

| 迭代 | 判決 | 重點 |
|------|------|------|
| 1 | FAIL | 8 項產品標準全過；唯一問題：Builder commit 標題缺 `(v1.8.0)` 尾綴 |
| — | 修復 | 以歷史改寫（reset --hard + amend + cherry-pick）僅改標題：`520e251 chore(release): [B] 發布 QuickRecorder (v1.8.0)`；Inspector 以 patch ID `ea422e0c…` 證明新舊迭代 1 commit 內容逐位元組相同 |
| 2 | **PASS** | 9 項檢查全過：標題 45 字元含尾綴、commit body/trailer 未動、`git diff d12e740…HEAD` 為空（產品樹零變動）、DMG 重新驗證通過 |

## 品質關卡

Release build 在迭代 1 為 BUILD SUCCEEDED；迭代 2 以 `git diff` 證明產品樹逐位元組相同，無需重跑。

## 對使用者的影響

- 依賴回到最新（Sparkle 自動更新元件安全修補到位）
- 版本 1.8.0 / build 180，可正式標記發布
- 過時的開發用文件移除，README 只剩對使用者有效的內容
- 一鍵 `./build-release.sh` 即可產出經驗證的 arm64 DMG

## 建議（後續可改善）

1. **Intel (x86_64) DMG**：目前僅產 arm64，若有 Intel 使用者需求可擴充 script 支援 universal binary
2. **Developer ID 簽署 + 公證 (notarization)**：現為 ad-hoc 簽署，他機安裝需手動繞過 Gatekeeper
3. **CI workflow**：以 GitHub Actions 在 PR 自動跑 Release build + DMG 驗證，避免人工遺漏
4. **測試缺口**：專案無任何 unit/UI test target，錄影核心邏輯（RecordEngine、mixAudioTracks）建議補最小測試
5. **電影片段 MP4 保護範圍**：CLAUDE.md 記錄 v1.7.4 限縮後的 fragmented MP4 僅覆蓋純螢幕錄影，音頻組態的斷檔保護仍是 open question

## 夥伴檔案

- goal.md（不動的目標契約）
- status.json（完成的迭代追蹤）
- inspector-feedback-1.md / inspector-feedback-2.md