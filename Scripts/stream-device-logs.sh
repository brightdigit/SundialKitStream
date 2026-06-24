#!/bin/bash
# Stream live logs from a physical iPhone and Apple Watch simultaneously.
#
# A generic helper for a watch<->phone app that talks over WatchConnectivity
# (SundialKitStream). Configure it for your app via flags or the matching
# environment variables:
#
#   --ios-bundle-id    <id>    IOS_BUNDLE_ID    iPhone app bundle identifier
#   --watch-bundle-id  <id>    WATCH_BUNDLE_ID  Watch app bundle identifier
#   --process-filter   <name>  PROCESS_FILTER   idevicesyslog process filter (iPhone USB path)
#   --console-env      <NAME>  CONSOLE_ENV      env var injected as DEVICECTL_CHILD_<NAME>=1
#   --out-dir          <dir>   OUT_DIR          output directory (default: logs)
#
# iPhone: idevicesyslog (libimobiledevice) filtered to PROCESS_FILTER when the
#         phone is USB-visible; otherwise a devicectl console launch (below),
#         which works over the wireless CoreDevice tunnel.
# Watch:  `xcrun devicectl device process launch --console`, which launches the
#         app with its stdout/stderr attached to this terminal. OSLog lines are
#         NOT mirrored to stdout, so point --console-env at the variable your app
#         checks to mirror its logger to print() in token-optimized form (injected
#         below via devicectl's DEVICECTL_CHILD_ prefix). SundialKitStream's
#         send/receive diagnostics can be bridged into that same logger so they
#         appear as structured lines too.
#
# Usage:
#   stream-device-logs.sh --ios-bundle-id com.example.App \
#       --watch-bundle-id com.example.App.watchkitapp --process-filter App
#   stream-device-logs.sh ... --iphone-only
#   stream-device-logs.sh ... --watch-only
#   stream-device-logs.sh ... --out-dir /tmp/applogs
#
# Output: <out-dir>/<timestamp>-iphone.log and -watch.log (raw, unprefixed —
# easy to grep), plus a [iPhone]/[Watch]-prefixed merged view on the terminal.
# Ctrl-C stops both streams (and terminates console-launched apps — devicectl
# forwards the signal to the launched process).

set -euo pipefail

IOS_BUNDLE_ID="${IOS_BUNDLE_ID:-}"
WATCH_BUNDLE_ID="${WATCH_BUNDLE_ID:-}"
PROCESS_FILTER="${PROCESS_FILTER:-}"
CONSOLE_ENV="${CONSOLE_ENV:-}"
OUT_DIR="${OUT_DIR:-logs}"
STREAM_IPHONE=1
STREAM_WATCH=1

# Print the leading comment block (everything after the shebang up to the first
# non-comment line) as help text.
usage() {
    awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "$0"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ios-bundle-id)
            IOS_BUNDLE_ID="${2:?--ios-bundle-id requires a value}"
            shift 2
            ;;
        --watch-bundle-id)
            WATCH_BUNDLE_ID="${2:?--watch-bundle-id requires a value}"
            shift 2
            ;;
        --process-filter)
            PROCESS_FILTER="${2:?--process-filter requires a value}"
            shift 2
            ;;
        --console-env)
            CONSOLE_ENV="${2:?--console-env requires a value}"
            shift 2
            ;;
        --out-dir)
            OUT_DIR="${2:?--out-dir requires a path}"
            shift 2
            ;;
        --iphone-only)
            STREAM_WATCH=0
            shift
            ;;
        --watch-only)
            STREAM_IPHONE=0
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: unknown argument '$1' (try --help)" >&2
            exit 1
            ;;
    esac
done

if [[ $STREAM_IPHONE -eq 1 && -z "$IOS_BUNDLE_ID" ]]; then
    echo "Error: --ios-bundle-id (or IOS_BUNDLE_ID) is required unless --watch-only." >&2
    exit 1
fi
if [[ $STREAM_WATCH -eq 1 && -z "$WATCH_BUNDLE_ID" ]]; then
    echo "Error: --watch-bundle-id (or WATCH_BUNDLE_ID) is required unless --iphone-only." >&2
    exit 1
fi

# --- Device discovery -------------------------------------------------------

# Prints "identifier|name" of the first connected physical device for the
# given platform (iOS / watchOS), or nothing if none is connected.
discover_coredevice() {
    local platform=$1
    local devices_json
    devices_json=$(mktemp -t devicectl-devices)
    xcrun devicectl list devices --json-output "$devices_json" -q >/dev/null
    python3 -c "
import json, sys
data = json.load(open(sys.argv[1]))
for dev in data['result']['devices']:
    hw = dev.get('hardwareProperties', {})
    if (hw.get('platform') == sys.argv[2]
            and hw.get('reality') == 'physical'
            and dev.get('connectionProperties', {}).get('tunnelState') == 'connected'):
        print(dev['identifier'] + '|' + dev.get('deviceProperties', {}).get('name', sys.argv[2]))
        break
" "$devices_json" "$platform"
    rm -f "$devices_json"
}

IPHONE_UDID=""
IPHONE_COREDEVICE_ID=""
IPHONE_NAME=""
if [[ $STREAM_IPHONE -eq 1 ]]; then
    if command -v idevice_id >/dev/null 2>&1; then
        IPHONE_UDID=$({ idevice_id -l; idevice_id -n; } 2>/dev/null | head -n1 || true)
    fi
    if [[ -z "$IPHONE_UDID" ]]; then
        IPHONE_INFO=$(discover_coredevice iOS)
        if [[ -z "$IPHONE_INFO" ]]; then
            echo "Error: no iPhone visible to libimobiledevice or devicectl." >&2
            echo "       Plug it in or make sure it's on the same network, unlocked, and trusted." >&2
            exit 1
        fi
        IPHONE_COREDEVICE_ID="${IPHONE_INFO%%|*}"
        IPHONE_NAME="${IPHONE_INFO#*|}"
    fi
fi

WATCH_ID=""
WATCH_NAME=""
if [[ $STREAM_WATCH -eq 1 ]]; then
    WATCH_INFO=$(discover_coredevice watchOS)
    if [[ -z "$WATCH_INFO" ]]; then
        echo "Error: no connected physical Apple Watch found via devicectl." >&2
        echo "       Is the Watch on, unlocked, and paired? (Connecting can take ~30s after wake.)" >&2
        exit 1
    fi
    WATCH_ID="${WATCH_INFO%%|*}"
    WATCH_NAME="${WATCH_INFO#*|}"
fi

# --- Streaming ---------------------------------------------------------------

mkdir -p "$OUT_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
IPHONE_LOG="$OUT_DIR/$TIMESTAMP-iphone.log"
WATCH_LOG="$OUT_DIR/$TIMESTAMP-watch.log"

# Each background pipeline gets its own process group (set -m) so cleanup can
# kill the whole pipeline, not just its last member.
set -m

PIDS=""
cleanup() {
    trap - INT TERM EXIT
    for pid in $PIDS; do
        kill -- -"$pid" 2>/dev/null || true
    done
}
trap cleanup INT TERM EXIT

# Launches an app on a device with its stdio attached to this terminal.
# $1 = CoreDevice identifier, $2 = bundle id, $3 = optional extra flag.
#
# When CONSOLE_ENV is set, DEVICECTL_CHILD_<CONSOLE_ENV>=1 is injected so the
# app can mirror its logger (including any bridged SundialKitStream diagnostics)
# to stdout in token-optimized form — OSLog itself is not forwarded to stdout.
launch_console() {
    local env_prefix=()
    if [[ -n "$CONSOLE_ENV" ]]; then
        env_prefix=(env "DEVICECTL_CHILD_${CONSOLE_ENV}=1")
    fi
    # shellcheck disable=SC2086  # $3 is an optional flag, intentionally unquoted
    "${env_prefix[@]}" xcrun devicectl device process launch --console ${3:-} \
        --device "$1" "$2"
}

# Console-launch with retries. Immediate failures are usually a CoreDevice
# tunnel still warming up after the device wakes (error 4000
# "RemoteServiceDiscovery connectivity is not available"), which resolves
# within seconds — so retry a few times before giving up. stdio only attaches
# when devicectl itself starts the process, hence --terminate-existing.
console_stream() {
    local device_id=$1 bundle_id=$2
    local attempt started
    for attempt in 1 2 3; do
        started=$SECONDS
        if launch_console "$device_id" "$bundle_id" "--terminate-existing"; then
            return 0
        fi
        # A failure after a long run is the app/session ending, not a launch
        # problem — don't relaunch the app behind the user's back.
        if (( SECONDS - started >= 10 )); then
            return 0
        fi
        echo "Launch attempt $attempt failed; retrying in 5s (tunnel may still be warming up)..."
        sleep 5
    done
    echo "Falling back to launch without --terminate-existing..."
    echo "If $bundle_id is already running, quit it first — stdio only attaches on a fresh launch."
    launch_console "$device_id" "$bundle_id"
}

if [[ $STREAM_IPHONE -eq 1 ]]; then
    if [[ -n "$IPHONE_UDID" ]]; then
        echo "📱 iPhone $IPHONE_UDID (idevicesyslog) → $IPHONE_LOG"
        syslog_args=(-u "$IPHONE_UDID")
        [[ -n "$PROCESS_FILTER" ]] && syslog_args+=(-p "$PROCESS_FILTER")
        idevicesyslog "${syslog_args[@]}" 2>&1 \
            | tee "$IPHONE_LOG" | sed 's/^/[iPhone] /' &
        PIDS="$PIDS $!"
    else
        echo "📱 $IPHONE_NAME ($IPHONE_COREDEVICE_ID) → $IPHONE_LOG"
        echo "   Not USB-visible; launching $IOS_BUNDLE_ID with console attached instead..."
        console_stream "$IPHONE_COREDEVICE_ID" "$IOS_BUNDLE_ID" 2>&1 \
            | tee "$IPHONE_LOG" | sed 's/^/[iPhone] /' &
        PIDS="$PIDS $!"
    fi
fi

if [[ $STREAM_WATCH -eq 1 ]]; then
    echo "⌚️ $WATCH_NAME ($WATCH_ID) → $WATCH_LOG"
    echo "   Launching $WATCH_BUNDLE_ID with console attached..."
    console_stream "$WATCH_ID" "$WATCH_BUNDLE_ID" 2>&1 \
        | tee "$WATCH_LOG" | sed 's/^/[Watch] /' &
    PIDS="$PIDS $!"
fi

echo "Press Ctrl-C to stop streaming."
echo ""
wait
