# Goal: v1.8.0 — dependencies, docs, version bump, release DMG

## User Request

協助 update latest dependencies, readme (移除過時的文件) + bump version + build production release dmg

## Refined Goal

Prepare and produce a maintenance release v1.8.0 of QuickRecorder:

1. **Dependency updates** — resolve all Swift Package dependencies to their latest available versions within their configured requirement rules, and update the revision pin for revision-pinned packages (SwiftLAME) to the latest upstream commit. Verify each resolved version is actually the newest available (check GitHub releases/commits), then confirm the project builds.
2. **Documentation cleanup** — delete the 4 dev-process markdown files (`test_filename_verification.md`, `BUG_REPORT_TRIPLE_EXTENSION.md`, `build.md`, `SPEC.md`) and fix every remaining reference to them (e.g. `CLAUDE.md` line ~223 references `BUG_REPORT_TRIPLE_EXTENSION.md`). Review `README.md` and `README_zh.md` for stale/outdated statements and update them.
3. **Version bump** — set release to **1.8.0**: `MARKETING_VERSION = 1.8.0` and `CURRENT_PROJECT_VERSION = 180` for all build configurations, and add a matching CHANGELOG.md entry (zh-TW, same style as existing entries, dated 2026-09-01) summarizing dependency updates + doc cleanup.
4. **Release DMG** — add `build-release.sh` that builds the Release configuration (arm64-only, ad-hoc signed, no app launch) and packages a DMG with an /Applications symlink. Run it and produce the artifact. The DMG itself must NOT be committed to git (add a `.gitignore` entry for the output dir).

## Acceptance Criteria

- [ ] `Package.resolved` pins each dependency to the latest available version/commit for its requirement rule (Sparkle ≥2.9.1 upToNextMajor → newest 2.x tag; KeyboardShortcuts ≥2.4.0 upToNextMajor → newest 2.x tag; MatrixColorSelector & AECAudioStream on `main` → latest commit; SwiftLAME → latest upstream commit). The Builder must state each dep's previous → new version in the commit body.
- [ ] `xcodebuild -project QuickRecorder.xcodeproj -scheme QuickRecorder -configuration Release -destination 'platform=macOS,arch=arm64' build` succeeds with zero errors.
- [ ] `MARKETING_VERSION = 1.8.0` and `CURRENT_PROJECT_VERSION = 180` in all build configurations of `project.pbxproj`.
- [ ] `CHANGELOG.md` has a `## [1.8.0] - 2026-09-01` entry in the existing zh-TW format.
- [ ] The 4 dev markdown files are deleted, and `grep -rn "BUG_REPORT_TRIPLE_EXTENSION\|test_filename_verification\|SPEC\.md"` finds no references to deleted files in remaining docs (README*, CLAUDE*).
- [ ] `build-release.sh` exists, is executable, performs Release build (arch=arm64, ad-hoc signing, no code launch) and packages a DMG via `hdiutil`; output directory is gitignored.
- [ ] Running `build-release.sh` produces a DMG that: (a) passes `hdiutil verify`, (b) mounts and contains `QuickRecorder.app` with `CFBundleShortVersionString = 1.8.0`, (c) app binary is arm64-only (`lipo -archs` reports `arm64`), (d) volume contains an `/Applications` symlink.
- [ ] The DMG binary artifact is not committed to git.

## Scope Boundaries

**In scope:**
- Swift package version resolution + `Package.resolved` regeneration
- Deletion of the 4 dev-process .md files and reference cleanup in remaining docs
- README.md / README_zh.md stale content review & update (only accuracy fixes; no redesign)
- Version bump to 1.8.0 + CHANGELOG entry
- `build-release.sh` + arm64 release DMG artifact (local, uncommitted)

**Out of scope:**
- Any feature changes, bug fixes, or refactoring of app source code
- Developer ID signing / notarization / Sparkle appcast updates
- Intel (x86_64) build or universal DMG
- Rewriting CLAUDE.md content beyond removing stale references to deleted files
- Publishing/uploading the DMG anywhere (GitHub Releases etc.)

## Applicable Project Conventions

**Quality gate command:**
- `xcodebuild -project QuickRecorder.xcodeproj -scheme QuickRecorder -configuration Release CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "(BUILD SUCCEEDED|BUILD FAILED|error:)"` — must report BUILD SUCCEEDED. Xcode (full IDE, not just CLT) is required on this machine.

**Commit convention:**
- Project style: conventional commits without scope, zh-TW description, version suffix (e.g. `fix: 螢幕+音頻錄影只有 1 秒鐘的 regression (v1.7.4)`)
- Skill override for this goal: `type(scope): [B] description` / `chore(scope): [I] description`, ≤72 chars; Builder must append version suffix `(v1.8.0)` to the description when applicable
- Assisted-by trailer required (Builder: `Assisted-by: OpenAI:GPT-5.6 Luna`, Inspector: `Assisted-by: OpenAI:GPT-5.6 Sol`)

**Guidelines:**
- No `.agents/guidelines/` or `.github/guidelines/` exist; `CLAUDE.md` and `CLAUDE_zh-TW.md` are the authoritative project docs — read `CLAUDE.md` first, especially the "Recording File Integrity" section (do not destabilize `movieFragmentInterval` logic; not expected to be touched here).

**Rules:**
- No AGENTS.md / CONSTITUTION.md in this repo.