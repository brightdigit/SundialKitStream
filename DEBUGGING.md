# Debugging a watch↔phone app on device (CLI, no Xcode UI)

Durable recipes for building to, launching on, and live-debugging a physical
iPhone + Apple Watch that talk over WatchConnectivity (SundialKitStream). Replace
`<scheme>`, `<bundle-id>`, and the CoreDevice UUIDs with your app's values.

## Build + install to physical devices

```sh
xcodebuild -workspace App.xcworkspace -scheme <watch-scheme> \
  -destination 'platform=watchOS,id=<watch-coredevice-uuid>' \
  -derivedDataPath /tmp/dd-watch build
xcrun devicectl device install app --device <watch-coredevice-uuid> \
  /tmp/dd-watch/Build/Products/Debug-watchos/<App>_watchOS.app
```

(Same pattern for the iPhone with the iOS scheme and `Debug-iphoneos`. For an iOS
app that embeds the watch app, installing the iPhone `.app` also propagates the
embedded watch app — but slowly; a direct `devicectl` install to the watch is
faster for a debug loop.)

- **Launch an app in foreground:** `xcrun devicectl device process launch
  --terminate-existing --device <uuid> <bundle-id>`. Fails with "device was not,
  or could not be, unlocked" while the device is locked — unlock and retry.
- **Find a PID:** `xcrun devicectl device info processes --device <uuid> | grep <App>`.
- **List devices / CoreDevice IDs:** `xcrun devicectl list devices`.

## LLDB attach over the wireless tunnel

`xcrun lldb -o "device select <coredevice-uuid>" -o "device process attach
-p <pid>"`. Attach takes 30–60 s. In `--batch` mode `process interrupt` is broken
("Process must be launched") — use the Python bridge instead (`script
lldb.debugger.GetSelectedTarget().GetProcess().Stop()`), then `thread backtrace
all`. NOTE: one attach/detach cycle has been observed to SIGKILL the app — attach
once, dump, detach.

## Known flakes

- The watch's `devicectl` tunnel only establishes when the Apple Watch is
  **awake/unlocked AND on the same Wi-Fi as the Mac**. Otherwise `devicectl device
  install`/`process launch` times out indefinitely with CoreDeviceError 4000 /
  RemotePairingError 1001 (not a warm-up blip — it never succeeds). Joining the
  watch to the Mac's Wi-Fi clears it; the iPhone tunnel is unaffected because it
  bridges through USB/Bluetooth.
- CoreDeviceError 4000 on launch = tunnel still warming up; retry a few times.
- CoreDeviceError 3 mid-stream = a `--console` attachment dropped; relaunch.
- `Network.NWError -54` (connection reset) during tunnel negotiation = transient;
  retry.

## Notes

- `log stream --device <UDID>` is not supported on macOS.
- The Apple Watch is not a usbmuxd peer, so `idevicesyslog` can't reach it.
- `Console.app` (Window → Devices) works for both as a manual fallback.
- A `--console`-launched app only attaches stdio when devicectl *starts* the
  process, so relaunch (`--terminate-existing`) each capture session.
