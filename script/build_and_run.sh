#!/bin/bash
set -euo pipefail
MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
APP_BUNDLE="$ROOT_DIR/dist/RayNeo Steady.app"
"$ROOT_DIR/script/build_app.sh" debug
case "$MODE" in
  --build-only) ;;
  run) open -n "$APP_BUNDLE" ;;
  --verify) open -n "$APP_BUNDLE"; sleep 1; pgrep -x RayNeoSteady >/dev/null ;;
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/RayNeoSteady" ;;
  --logs|--telemetry) open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'process == "RayNeoSteady"' ;;
  *) echo "Usage: $0 [run|--build-only|--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;;
esac
