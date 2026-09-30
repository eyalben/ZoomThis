#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
if [ "$#" -gt 0 ]; then project_root="$1"; fi
build_dir="$(mktemp -d /private/tmp/zoomthis-regressions.XXXXXX)"
trap 'rm -rf "$build_dir"' EXIT
xcrun swiftc -parse-as-library -default-isolation MainActor -module-cache-path "$build_dir/module-cache" \
  "$project_root/ZoomThis/DrawingState.swift" \
  "$project_root/ZoomThis/DrawingAction.swift" \
  "$project_root/ZoomThis/ZoomOverlayView.swift" \
  "$project_root/ZoomThis/HotkeyManager.swift" \
  "$project_root/ZoomThis/BreakTimerController.swift" \
  "$project_root/ZoomThis/BreakTimerView.swift" \
  "$project_root/ZoomThis/OverlayPanel.swift" \
  "$project_root/ZoomThis/ZoomOverlayController.swift" \
  "$project_root/ZoomThis/ToolTipHUD.swift" \
  "$(dirname "$0")/RegressionTests.swift" \
  -o "$build_dir/regressions"
"$build_dir/regressions"
