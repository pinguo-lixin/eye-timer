#!/bin/bash
# Creates download assets from a validated app. No installation or system changes.
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "${1:-}" == "--skip-build" && $# == 1 ]]; then
    :
elif [[ $# == 0 ]]; then
    bash "$task_root/build_app.sh"
else
    echo "Usage: bash Tools/package_release.sh [--skip-build]" >&2
    exit 1
fi

app_path="$task_root/dist/EyeTimer.app"
release_version="${APP_VERSION:-$(cat "$task_root/VERSION")}"
release_arch="${APP_ARCH:-$(uname -m)}"
python3 - "$app_path" "$release_version" "$release_arch" <<'PY'
import pathlib, plistlib, re, subprocess, sys
app, version, arch = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
assert re.fullmatch(r'\d+\.\d+\.\d+', version), 'Invalid version'
assert arch in ('arm64', 'x86_64'), 'Invalid architecture'
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
assert info['CFBundleShortVersionString'] == version, 'Stale app version; rebuild first'
binary = app / 'Contents/MacOS' / info['CFBundleExecutable']
assert subprocess.check_output(['lipo', '-archs', str(binary)], text=True).strip() == arch, 'Wrong architecture; rebuild first'
subprocess.run(['codesign', '--verify', '--strict', str(app)], check=True)
assert (app / 'Contents/Resources/LICENSE.txt').is_file()
PY

artifact_root="$task_root/dist/releases"
mkdir -p "$artifact_root"
asset_name="EyeTimer-$release_version-$release_arch"
stage_dir="$(mktemp -d "$task_root/.build/dmg.XXXXXX")"
trap 'rm -rf "$stage_dir"' EXIT
ditto "$app_path" "$stage_dir/EyeTimer.app"
ln -s /Applications "$stage_dir/Applications"
cp "$task_root/Resources/Install.txt" "$stage_dir/安装说明.txt"
cp "$task_root/LICENSE" "$stage_dir/LICENSE.txt"

hdiutil create -volname "EyeTimer $release_version" -srcfolder "$stage_dir" \
    -ov -format UDZO "$artifact_root/$asset_name.dmg"
hdiutil verify "$artifact_root/$asset_name.dmg"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$artifact_root/$asset_name.zip"
unzip -tq "$artifact_root/$asset_name.zip"
ditto -x -k "$artifact_root/$asset_name.zip" "$stage_dir/zip-check"
test -x "$stage_dir/zip-check/EyeTimer.app/Contents/MacOS/EyeTimer"
codesign --verify --strict "$stage_dir/zip-check/EyeTimer.app"
cmp "$app_path/Contents/MacOS/EyeTimer" "$stage_dir/zip-check/EyeTimer.app/Contents/MacOS/EyeTimer"
(
    cd "$artifact_root"
    shasum -a 256 "$asset_name.dmg" "$asset_name.zip" > "$asset_name.sha256"
    shasum -a 256 --check "$asset_name.sha256"
)
echo "Download assets: $artifact_root/$asset_name.{dmg,zip,sha256}"
