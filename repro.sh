#!/bin/sh
# Reproduces callstack/agent-device#4209: a paired iPhone that CoreDevice cannot reach
# is reported as booted, and `boot` succeeds on it.
#
# usage: ./repro.sh [physical-device-udid]
#
#   Without a UDID, the script uses the first paired physical device that
#   `xcrun devicectl list devices` reports with tunnelState "unavailable".
#
# Environment:
#   AGENT_DEVICE  agent-device command (default: agent-device). For a source checkout:
#                 AGENT_DEVICE="node /path/to/agent-device/bin/agent-device.mjs"
#
# Exit status: 0 when every case passes, 1 when a case fails, 2 when the
# precondition (an unreachable paired device) is not met.
set -eu

AGENT_DEVICE="${AGENT_DEVICE:-agent-device}"
STATE_DIR="${TMPDIR:-/tmp}/agent-device-repro-unavailable-device"
SESSION=unavailable-device
DEVICECTL_JSON="$(mktemp)"
trap 'rm -f "$DEVICECTL_JSON"' EXIT

xcrun devicectl list devices --json-output "$DEVICECTL_JSON" >/dev/null
UDID="${1:-$(python3 -I -c '
import json, sys
for device in json.load(open(sys.argv[1]))["result"]["devices"]:
    hardware = device.get("hardwareProperties", {})
    connection = device.get("connectionProperties", {})
    if hardware.get("reality") == "physical" and connection.get("tunnelState") == "unavailable":
        print(hardware.get("udid") or device["identifier"]); sys.exit()
' "$DEVICECTL_JSON")}"
if [ -z "$UDID" ]; then
  echo "No paired physical device is unavailable. Unplug a paired iPhone and turn off its Wi-Fi, or pass its UDID." >&2
  exit 2
fi
TUNNEL="$(python3 -I -c '
import json, sys
for device in json.load(open(sys.argv[1]))["result"]["devices"]:
    if sys.argv[2] in (device.get("hardwareProperties", {}).get("udid"), device.get("identifier")):
        print(device.get("connectionProperties", {}).get("tunnelState", "")); sys.exit()
' "$DEVICECTL_JSON" "$UDID")"
if [ "$TUNNEL" != unavailable ]; then
  echo "devicectl reports tunnelState \"$TUNNEL\" for $UDID; the repro needs \"unavailable\"." >&2
  exit 2
fi

echo "agent-device: $($AGENT_DEVICE --version)"
echo "xcode: $(xcodebuild -version | head -1)"
echo "device: $UDID, devicectl tunnelState=$TUNNEL"
echo

FAILED=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; echo "      $2"; FAILED=1; }

# Case 1: the inventory must not report the device as booted.
BOOTED="$($AGENT_DEVICE devices --platform ios --json --state-dir "$STATE_DIR" | python3 -I -c '
import json, sys
for device in json.load(sys.stdin)["data"]["devices"]:
    if device["id"] == sys.argv[1]:
        print(str(device.get("booted")).lower()); sys.exit()
print("missing")
' "$UDID")"
if [ "$BOOTED" = false ]; then
  pass "devices lists the unreachable device with booted: false"
else
  fail "devices lists the unreachable device with booted: false" "booted: $BOOTED"
fi

# Case 2: boot must refuse the device with a typed not-ready reason.
BOOT="$($AGENT_DEVICE boot --platform ios --udid "$UDID" --session "$SESSION" --json --state-dir "$STATE_DIR" 2>&1 || true)"
$AGENT_DEVICE close --session "$SESSION" --state-dir "$STATE_DIR" >/dev/null 2>&1 || true
VERDICT="$(printf '%s' "$BOOT" | python3 -I -c '
import json, sys
result = json.load(sys.stdin)
if result.get("success"):
    print("succeeded: booted=%s" % json.dumps(result["data"].get("booted")))
else:
    error = result["error"]
    details = error.get("details") or {}
    print("%s kind=%s tunnelState=%s" % (error["code"], details.get("kind"), details.get("tunnelState")))
')"
if [ "$VERDICT" = "COMMAND_FAILED kind=not_ready tunnelState=unavailable" ]; then
  pass "boot refuses the unreachable device as not_ready"
else
  fail "boot refuses the unreachable device as not_ready" "$VERDICT"
fi

exit "$FAILED"
