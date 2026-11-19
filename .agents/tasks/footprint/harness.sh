#!/bin/zsh
# Measures the overlay's memory and CPU per show/hide (or per folder open/close) without the developer's screen.
#
# It builds a scratch copy of Sources/ in which the real OverlayController puts its panel 40,000 pt off every display
# and orders it in with orderFrontRegardless() instead of making it key. harness-main.swift runs it with the
# .prohibited activation policy, so nothing appears on screen, nothing takes focus, and no hotkey or login item is
# registered. The layout is a copy of the developer's layout.json; the preferences come from UserDefaults.
#
# Usage: .agents/tasks/footprint/harness.sh [controller|folders|zoom|watch|rescan] [cycles]
set -euo pipefail

repo=${0:A:h:h:h:h}
work=${TMPDIR:-/tmp}/macstart-footprint-harness
mode=${1:-controller}
cycles=${2:-200}

rm -rf "$work"
mkdir -p "$work/Sources"
cp -R "$repo/Sources/MacStartCore" "$work/Sources/MacStartCore"
cp -R "$repo/Sources/MacStart" "$work/Sources/Harness"
rm "$work/Sources/Harness/App/MacStartApp.swift"
cp "$repo/.agents/tasks/footprint/harness-main.swift" "$work/Sources/Harness/main.swift"

controller="$work/Sources/Harness/Overlay/OverlayController.swift"
sed -i '' -E \
    -e 's/panel\.setFrame\(screen\.frame, display: (false|true)\)/panel.setFrame(screen.frame.offsetBy(dx: -40000, dy: -40000), display: \1)/' \
    -e 's/panel\.makeKeyAndOrderFront\(nil\)/panel.orderFrontRegardless()/' \
    "$controller"
# Refuse to run when the patch did not apply: the panel would then cover the display and take the keyboard.
if grep -q 'makeKeyAndOrderFront' "$controller" || grep -qE 'setFrame\(screen\.frame,' "$controller"; then
    echo "harness.sh: OverlayController changed; update the off-screen patch before running." >&2
    exit 1
fi

cat > "$work/Package.swift" <<'EOF'
// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "Harness",
    platforms: [.macOS(.v27)],
    targets: [
        .target(name: "MacStartCore"),
        .executableTarget(name: "Harness", dependencies: ["MacStartCore"]),
    ]
)
EOF
cp "$HOME/Library/Application Support/MacStart/layout.json" "$work/layout.json"
(cd "$work" && swift build -c release 2>&1 | grep -E 'error:|Build complete')

preferences=$(defaults read cc.summ.MacStart preferences)
if [[ $mode == folders ]]; then
    HARNESS_MODE=controller HARNESS_FOLDERS=1 HARNESS_CYCLES=$cycles "$work/.build/release/Harness" "$work" "$preferences"
elif [[ $mode == watch || $mode == rescan ]]; then
    HARNESS_MODE=$mode "$work/.build/release/Harness" "$work" "$preferences"
elif [[ $mode == zoom ]]; then
    HARNESS_MODE=controller HARNESS_ZOOMCHECK=1 "$work/.build/release/Harness" "$work" "$preferences"
else
    HARNESS_MODE=controller HARNESS_CYCLES=$cycles "$work/.build/release/Harness" "$work" "$preferences"
fi
