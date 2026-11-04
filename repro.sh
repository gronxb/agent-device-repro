#!/bin/sh
# Reproduces callstack/agent-device#4208 on an iOS simulator.
#
# usage: ./repro.sh [--driver agent-device|probe] [simulator-udid]
#
#   --driver agent-device  (default) swipe with `agent-device gesture swipe <preset>`.
#   --driver probe         swipe with probe/probe.m, an edge-marked HID touch.
#                          This is the expected behavior; every case passes.
#
# Environment:
#   AGENT_DEVICE  agent-device command (default: agent-device). For a source checkout:
#                 AGENT_DEVICE="node /path/to/agent-device/bin/agent-device.mjs"
#
# Exit status: 0 when every case passes, 1 when a case fails.
set -eu

DRIVER=agent-device
if [ "${1:-}" = "--driver" ]; then
  DRIVER="$2"
  shift 2
fi
case "$DRIVER" in
  agent-device | probe) ;;
  *) echo "unknown driver: $DRIVER" >&2; exit 2 ;;
esac

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUNDLE=dev.agentdevice.repro.edgepan
AGENT_DEVICE="${AGENT_DEVICE:-agent-device}"
UDID="${1:-$(xcrun simctl list devices booted -j | python3 -I -c '
import json, sys
for runtime, devices in json.load(sys.stdin)["devices"].items():
    for device in devices:
        if "iOS" in runtime and device["name"].startswith("iPhone"):
            print(device["udid"]); sys.exit()
')}"
if [ -z "$UDID" ]; then
  echo "Boot an iPhone simulator first, or pass its UDID." >&2
  exit 2
fi

STATE_DIR="${TMPDIR:-/tmp}/agent-device-repro-edge-swipe"
ad() {
  $AGENT_DEVICE --state-dir "$STATE_DIR" --session edge-swipe --platform ios --udid "$UDID" "$@"
}

"$ROOT/build.sh" "$UDID"
echo "agent-device: $($AGENT_DEVICE --version)"
echo "simulator: $(xcrun simctl list devices | grep "$UDID" | sed 's/^ *//')"
echo "driver: $DRIVER"
echo

# swipe <agent-device preset> <probe fromX> <probe toX>
swipe() {
  if [ "$DRIVER" = probe ]; then
    xcrun simctl spawn "$UDID" "$ROOT/build/probe" "$2" "$3" 1
  else
    ad gesture swipe "$1" >/dev/null
  fi
}

# run_case <label> <preset> <fromX> <toX> <expected text> <launch flags...>
failed=0
run_case() {
  label="$1"; preset="$2"; from="$3"; to="$4"; expected="$5"
  shift 5
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE" "$@" >/dev/null
  sleep 2
  # Attach the session to the running app. It keeps the launch flags.
  ad open "$BUNDLE" >/dev/null
  swipe "$preset" "$from" "$to"
  sleep 1.5
  screen="$(ad snapshot | grep -oE '"(edge|pan): [0-9]+"|"last: [^"]*"|"nav (root|pushed)"' | tr '\n' ' ')"
  if echo "$screen" | grep -q "\"$expected\""; then result=PASS; else result=FAIL; failed=1; fi
  printf '%s  %-46s expected "%s"\n      %s\n' "$result" "$label" "$expected" "$screen"
}

run_case "right-edge -> left-edge recognizer" right-edge 0.0 0.85 "edge: 1"
run_case "left-edge -> right-edge recognizer" left-edge 0.98 0.15 "edge: 1" -edges right
run_case "right-edge -> UINavigationController pop" right-edge 0.0 0.85 "nav root" \
  -nav YES -contentPop NO

ad close >/dev/null 2>&1 || true
$AGENT_DEVICE daemon stop --state-dir "$STATE_DIR" >/dev/null 2>&1 || true
exit "$failed"
