# iOS: an unreachable paired device is reported as booted

Reproduces [callstack/agent-device#4209](https://github.com/callstack/agent-device/issues/4209).

`agent-device devices` lists every paired iPhone or iPad that
`xcrun devicectl list devices` returns as `booted: true`, even when CoreDevice
cannot reach it (`tunnelState: "unavailable"`: unplugged, off the network).
`agent-device boot --udid <device>` then succeeds on it, and the first command
that fails is the app launch (`CoreDeviceError 4016`).

## Needs

- macOS with Xcode 15 or later.
- An iPhone or iPad paired with this Mac and unreachable now: unplug it and
  turn off its Wi-Fi. `xcrun devicectl list devices` shows it as `unavailable`.

## Run

```sh
git clone -b ios-unavailable-device https://github.com/gronxb/agent-device-repro.git
cd agent-device-repro
./repro.sh            # exit 1 while any case fails
```

Pass the device's UDID to pick one; otherwise the script uses the first
unreachable paired device. For a source checkout:

```sh
AGENT_DEVICE="node /path/to/agent-device/bin/agent-device.mjs" ./repro.sh
```

## Expected output

agent-device 0.21.36:

```
FAIL  devices lists the unreachable device with booted: false
      booted: true
FAIL  boot refuses the unreachable device as not_ready
      succeeded: booted=true
```

With the fix:

```
PASS  devices lists the unreachable device with booted: false
PASS  boot refuses the unreachable device as not_ready
```

The script uses its own state directory and session, and closes the session
it opens.
