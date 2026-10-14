---
name: quickrecorder-workflow
description: QuickRecorder build, debug, verify, release, and /Applications install procedure. Use before running xcodebuild, build.sh, build-release.sh, installing the app, or debugging a recording.
---

Project reference (architecture, settings keys, fragment rules, version locations) lives in `CLAUDE.md`. This skill holds the procedures. Every path ends **clean**: the only `QuickRecorder.app` bundles on disk are `/Applications/QuickRecorder.app` and, after `./build.sh`, `/Applications/QuickRecorder-Dev.app`. Spotlight indexes the home folder, so any other bundle shows up as a duplicate app.

## Compile check

```bash
xcodebuild -project QuickRecorder.xcodeproj -scheme QuickRecorder -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Build products stay in the default `~/Library/Developer/Xcode/DerivedData`, which Spotlight skips. Only `build-release.sh` sets `-derivedDataPath` / `CONFIGURATION_BUILD_DIR`. Done when the output ends in `BUILD SUCCEEDED`.

## Debug run

1. `./build.sh` builds Debug, replaces `/Applications/QuickRecorder-Dev.app`, and runs it in the foreground with logs on stdout.
2. Read `/tmp/qr-debug.log` (written by `debugLog(...)` in `SCContext.swift`).
3. For recording bugs, record in the exact failing config, then `ffprobe -hide_banner <file>`; duration must match wall-clock time.
4. Logic changes: run the matching offline script (`swift verify_filename_logic.swift`, `verify_webcam_logic.swift`, `verify_webcam_screen_logic.swift`, `verify_webcam_screen_ui.swift`, `verify_webcam_cancel_ui.swift`). They cannot prove capture latency, permissions, or long-running behavior; report those as unverified.

## Release build

1. Version bump: update the DMG path/volume name in `build-release.sh`, `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.pbxproj`, and `CHANGELOG.md` together.
2. `./build-release.sh`. Its `EXIT` trap deletes `build-release/build` and `build-release/dmg-root` on success or failure.
3. Done when `build-release/` contains only `QuickRecorder-<version>-arm64.dmg` (plus `SHA256SUMS` if you generate it with `shasum -a 256`).

## Install to /Applications

Install from the DMG, never from a build folder. The block is fail-closed: it stops before touching `/Applications` unless the DMG mounts, its app passes `codesign`, and the backup copy matches; a failed copy or launch restores the backup.

```bash
dmg=build-release/QuickRecorder-<version>-arm64.dmg app=/Applications/QuickRecorder.app bash -euo pipefail <<'EOF'
test -f "$dmg"
work=$(mktemp -d)                          # $TMPDIR is outside Spotlight
mnt="$work/mnt" bak="$work/QuickRecorder.app"
mkdir "$mnt"
hdiutil attach -nobrowse -readonly -mountpoint "$mnt" "$dmg" >/dev/null
trap 'hdiutil detach "$mnt" >/dev/null 2>&1 || true' EXIT
src="$mnt/QuickRecorder.app"
test -d "$src"
codesign --verify --deep --strict "$src"
version=$(defaults read "$src/Contents/Info" CFBundleShortVersionString)

osascript -e 'quit app "QuickRecorder"' || true
sleep 2
if [ -d "$app" ]; then
  ditto "$app" "$bak"
  diff -rq "$app" "$bak" >/dev/null
fi

restore() {
  echo "install failed: $1; restoring previous app" >&2
  rm -rf "$app"
  if [ -d "$bak" ]; then ditto "$bak" "$app"; fi
  echo "backup kept at $bak" >&2
  exit 1
}
rm -rf "$app" && ditto "$src" "$app" || restore copy
[ "$(defaults read "$app/Contents/Info" CFBundleShortVersionString)" = "$version" ] || restore version
codesign --verify --deep --strict "$app" || restore codesign
open "$app" && sleep 3
pgrep -f "$app/Contents/MacOS/QuickRecorder" >/dev/null || restore launch

hdiutil detach "$mnt" >/dev/null && trap - EXIT
rm -rf "$work"
echo "installed $version"
EOF
```

Done when it prints `installed <version>`. On `install failed`, the previous app is back in place; report the failing step.

## Clean check

Run after every build or install:

```bash
mdfind 'kMDItemCFBundleIdentifier == "*QuickRecorder*"c'
```

Done when it lists only the `/Applications` bundles above. Delete any other bundle you created (stray `build/`, `dmg-root/`, copies in backup folders) and re-run.

## Publish

GitHub release: `gh release create <version> --repo fun-ed/QuickRecorderNext` with the DMG and `SHA256SUMS`, as the `fun-ed` account. Commit, push, tag, and publish only on explicit request. Leave `appcast.xml` unchanged unless a published artifact and its valid EdDSA signature both exist.
