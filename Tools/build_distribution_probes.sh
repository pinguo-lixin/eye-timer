#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
probe_root="$task_root/.build/distribution-probes"
mkdir -p "$probe_root"
cd "$task_root"
swiftc -o "$probe_root/probe" Tools/DistributionProbe/main.swift Sources/EyeTimer/Core/*.swift Sources/EyeTimer/Views/*.swift
python3 - "$probe_root" <<'PY'
import pathlib, plistlib, shutil, sys
root = pathlib.Path(sys.argv[1])
for mode in ('plain', 'sandbox'):
    bundle = root / f'EyeTimerProbe-{mode}.app'
    binary_dir = bundle / 'Contents/MacOS'
    binary_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(root / 'probe', binary_dir / 'EyeTimerProbe')
    info = dict(CFBundleName=f'EyeTimer Probe {mode}', CFBundleExecutable='EyeTimerProbe',
                CFBundleIdentifier=f'com.eyetimer.distributionprobe.{mode}', CFBundlePackageType='APPL',
                CFBundleVersion='1', CFBundleShortVersionString='1.0',
                LSUIElement=True, LSMinimumSystemVersion='13.0')
    (bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
(root / 'sandbox.entitlements').write_bytes(plistlib.dumps({
    'com.apple.security.app-sandbox': True,
    'com.apple.security.device.audio-output': True,
}))
PY
codesign --force --sign - "$probe_root/EyeTimerProbe-plain.app"
codesign --force --sign - --entitlements "$probe_root/sandbox.entitlements" "$probe_root/EyeTimerProbe-sandbox.app"
codesign --verify --strict "$probe_root/EyeTimerProbe-plain.app"
codesign --verify --strict "$probe_root/EyeTimerProbe-sandbox.app"
echo "Prepared isolated probe apps in $probe_root"
