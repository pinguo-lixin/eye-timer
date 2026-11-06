#!/bin/bash
# 拖拽时桌面框选矩形的 A/B/C 三组自动化验证。
#
#   A: 修复关闭（对照）—— 应当检出蓝色矩形
#   B: 兜底路径 + 修复开启 —— 应当干净
#   C: 事件 tap 路径 —— 应当干净
#
# 流程：清理遮挡窗口 → 把挂件移到裸桌面 → 三组各跑一次 → 还原窗口 → 像素比对
#
# 用法：./Tools/run_marquee_ab.sh

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="/Applications/EyeTimer.app/Contents/MacOS/EyeTimer"
MOVE_X="${MOVE_X:-2900}"     # 挂件落点（AppKit，左下原点）
MOVE_Y="${MOVE_Y:-1132}"

if [[ ! -x "$APP" ]]; then
    echo "❌ 找不到 $APP，请先执行 ./build_app.sh 并安装到 /Applications"
    exit 1
fi

cleanup() {
    echo ""
    echo "── 还原被隐藏的窗口 ──"
    swift "$ROOT/Tools/clear_desktop_area.swift" restore 2>/dev/null | tail -3
    pkill -f EyeTimer 2>/dev/null
}
trap cleanup EXIT

echo "── 清理遮挡窗口 ──"
swift "$ROOT/Tools/clear_desktop_area.swift" hide 2953 254 240 2>/dev/null | tail -4
sleep 2

run_group() {
    local tag="$1"; shift
    pkill -f EyeTimer 2>/dev/null; sleep 1.5
    env "$@" "$APP" --move "$MOVE_X" "$MOVE_Y" >/dev/null 2>&1 &
    sleep 3

    local out
    out="$(swift "$ROOT/Tools/visual_marquee_test.swift" "$tag" 2>&1)"
    echo "$out" | grep -E "❌|✅" | head -4

    if echo "$out" | grep -q "❌"; then
        echo "  ⚠️ 本组作废（区域被遮挡），但截屏仍会执行"
    fi

    echo "── 像素分析 ──"
    swift "$ROOT/Tools/marquee_analyze.swift" \
        "/tmp/vis_base_$tag.png" "/tmp/vis_during_$tag.png" "$tag 组" 2>/dev/null \
        | grep -v warning | tail -6
}

echo ""
echo "════════ A 组：修复关闭（对照，应检出矩形）════════"
run_group A EYETIMER_FORCE_FALLBACK=1 EYETIMER_DISABLE_MARQUEE_FIX=1

echo ""
echo "════════ B 组：兜底路径 + 修复开启（应干净）════════"
run_group B EYETIMER_FORCE_FALLBACK=1

echo ""
echo "════════ C 组：事件 tap 路径（应干净）════════"
run_group C DUMMY=1

echo ""
echo "════════ A vs B 直接相减 ════════"
swift "$ROOT/Tools/marquee_diff_ab.swift" /tmp/vis_during_A.png /tmp/vis_during_B.png 2>/dev/null \
    | grep -v warning | tail -8
echo ""
echo "截图: /tmp/vis_base_{A,B,C}.png  /tmp/vis_during_{A,B,C}.png"
