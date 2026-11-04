# iOS simulator edge swipes never start UIScreenEdgePanGestureRecognizer

Reproduction for [callstack/agent-device#4208](https://github.com/callstack/agent-device/issues/4208).

`agent-device gesture swipe right-edge` and `left-edge` reach the app on an iOS simulator, but
UIKit does not mark the touch as a screen-edge touch (`UITouch._edgeType` is `0`). A
`UIScreenEdgePanGestureRecognizer` never begins, and a `UINavigationController` does not pop
when its iOS 26 full-content pop gesture is off.

## Requirements

- macOS with Xcode and an iOS simulator runtime. No Xcode project or CocoaPods.
- A booted iPhone simulator.
- `agent-device` on `PATH` (`npm i -g agent-device`).

## Run

```sh
git clone -b ios-edge-swipe https://github.com/gronxb/agent-device-repro.git
cd agent-device-repro
./repro.sh                 # uses the first booted iPhone simulator
./repro.sh <udid>          # or a specific simulator
```

To test an agent-device source checkout:

```sh
AGENT_DEVICE="node /path/to/agent-device/bin/agent-device.mjs" ./repro.sh
```

`repro.sh` builds the app with `swiftc`, installs it, runs three edge cases and two controls, and
exits with `1` if a case fails. It first lists the simulator's touchscreen HID services
(`HID touchscreens:`). With agent-device, each edge case also prints the service the runner sent the
touch through (`selected:`), from the runner's `AGENT_DEVICE_RUNNER_EDGE_TOUCHSCREEN` log line.

To test the fix in [callstack/agent-device#4211](https://github.com/callstack/agent-device/pull/4211):

```sh
git clone -b fix/ios-simulator-edge-swipe https://github.com/gronxb/agent-device.git
(cd agent-device && pnpm install --frozen-lockfile && pnpm build)
AGENT_DEVICE="node $PWD/agent-device/bin/agent-device.mjs" ./agent-device-repro/repro.sh <udid>
```

## Current result (red)

agent-device 0.21.36 and `main` at `035c2b6ca`, iPhone 16, iOS 26.4:

```
FAIL  right-edge -> left-edge recognizer             expected "edge: 1"
      "edge: 0" "pan: 1" "last: touch x=8.0 edgeType=0 states=never-began(possible)"
FAIL  left-edge -> right-edge recognizer             expected "edge: 1"
      "edge: 0" "pan: 1" "last: touch x=385.0 edgeType=0 states=never-began(possible)"
FAIL  right-edge -> UINavigationController pop       expected "nav root"
      "nav pushed"
```

`pan: 1` shows that the touch reached the app. `edgeType=0` shows that UIKit did not mark it as
an edge touch.

## Expected result

`./repro.sh --driver probe` sends the same swipes as edge-marked touches with
[`probe/probe.m`](probe/probe.m). Every case passes:

```
PASS  right-edge -> left-edge recognizer             expected "edge: 1"
      "edge: 1" "pan: 1" "last: touch x=0.0 edgeType=1 states=began>changed>ended"
PASS  left-edge -> right-edge recognizer             expected "edge: 1"
      "edge: 1" "pan: 1" "last: touch x=385.0 edgeType=1 states=began>changed>ended"
PASS  right-edge -> UINavigationController pop       expected "nav root"
      "nav root"
```

The probe runs inside the simulator with `xcrun simctl spawn`. It dispatches a digitizer touch
through `IOHIDEventSystemClient` with the sender ID of the simulator touchscreen service and the
`FromEdgeFlat | FromEdgeTip` event mask. The same touch without the mask gives `edgeType=0`.
An XCTest synthesized touch gives `edgeType=0` even at x = 0.

## Files

| File | Purpose |
| --- | --- |
| [`App/main.swift`](App/main.swift) | UIKit app: an edge recognizer, a control pan, and a navigation mode. |
| [`probe/probe.m`](probe/probe.m) | Edge-marked HID touch that shows the expected behavior. |
| [`probe/touchscreens.m`](probe/touchscreens.m) | Lists the simulator's touchscreen HID services and their properties. |
| [`build.sh`](build.sh) | Builds and installs the app, and builds the probes. |
| [`repro.sh`](repro.sh) | Runs the cases with agent-device or the probe. |

App launch flags: `-edges right` watches the right edge. `-nav YES -contentPop NO` shows a
pushed `UINavigationController` screen that only the edge pop gesture can pop.
