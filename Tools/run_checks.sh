#!/bin/bash
# Local regression checks. Does not install, publish, request TCC access, or register login items.
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
check_root="$task_root/.build/checks"
mkdir -p "$check_root"
export SWIFT_MODULECACHE_PATH="${SWIFT_MODULECACHE_PATH:-${TMPDIR:-/tmp}/eye-timer-module-cache}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$SWIFT_MODULECACHE_PATH}"
cd "$task_root"

swift build --disable-sandbox
swiftc -o "$check_root/e2e" Tools/E2E/main.swift \
    Sources/EyeTimer/Core/TimerModels.swift Sources/EyeTimer/Core/TimerEngine.swift \
    Sources/EyeTimer/Core/StatsStore.swift Sources/EyeTimer/Core/AppSettings.swift
"$check_root/e2e"
swiftc -o "$check_root/menu" Tools/WidgetMenuTests/main.swift Sources/EyeTimer/Core/*.swift Sources/EyeTimer/Views/*.swift
"$check_root/menu"
swiftc -o "$check_root/preview" Tools/WidgetPreview/main.swift Sources/EyeTimer/Core/*.swift Sources/EyeTimer/Views/*.swift
"$check_root/preview" "$check_root/widget-previews"
bash build_app.sh
python3 - "$task_root/dist/EyeTimer.app" <<'PY'
import pathlib, plistlib, sys
bundle = pathlib.Path(sys.argv[1])
info = plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'com.eyetimer.app'
assert info['LSUIElement'] is True
assert (bundle / 'Contents/MacOS' / info['CFBundleExecutable']).is_file()
icon = bundle / 'Contents/Resources' / info['CFBundleIconFile']
# CFBundleIconFile may omit the .icns extension; PNG fallback names include it.
if not icon.suffix:
    icon = icon.with_suffix('.icns')
assert icon.is_file(), f'Missing app icon: {icon}'
assert (bundle / 'Contents/PkgInfo').read_bytes() == b'APPL????'
print('App Bundle validated: 5 checks')
PY
echo "All automated regression checks passed. Interactive permission/desktop checks are documented separately."
