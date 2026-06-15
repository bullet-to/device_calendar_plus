#!/bin/bash

# Integration Test Runner for Device Calendar Plus
# This script automatically grants calendar permissions and runs integration tests
# on iOS simulators or Android emulators.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Headless qemu instances left over from a killed `flutter test` driver hold the
# AVD lock and make the next visible `emulator -avd` launch fail with
# "Running multiple emulators with the same AVD". Sweep them up before doing
# anything else. Only targets -headless qemu processes and orphaned helpers
# (PPID=1) so the visible emulator the user just booted is left alone.
kill_zombie_headless_emulators() {
    local headless_pids
    headless_pids=$(pgrep -f "qemu-system-.*-headless.*-avd" 2>/dev/null || true)
    if [ -z "$headless_pids" ]; then
        return 0
    fi

    echo -e "${YELLOW}⚠️  Found headless emulator(s) from a previous run — cleaning up${NC}"
    for pid in $headless_pids; do
        echo "   killing headless qemu (pid $pid)"
        kill "$pid" 2>/dev/null || true
    done
    sleep 2

    ps -axo pid=,ppid=,command= \
        | awk '$2 == 1 && /Library\/Android\/sdk\/emulator\/(crashpad_handler|netsimd)/ { print $1 }' \
        | xargs kill 2>/dev/null || true
}

kill_zombie_headless_emulators

# Re-grant calendar permissions. Idempotent — pm grant on an already-granted
# perm is a no-op, and pm grant on an uninstalled app silently errors. Both
# pm grant (runtime layer) and appops set (system-policy layer) are issued
# because the runtime grant is wiped on reinstall but appops set survives —
# belt and braces.
grant_android_calendar_permissions() {
    adb -s "$DEVICE_ID" shell pm grant to.bullet.example android.permission.READ_CALENDAR 2>/dev/null || true
    adb -s "$DEVICE_ID" shell pm grant to.bullet.example android.permission.WRITE_CALENDAR 2>/dev/null || true
    adb -s "$DEVICE_ID" shell appops set to.bullet.example READ_CALENDAR allow 2>/dev/null || true
    adb -s "$DEVICE_ID" shell appops set to.bullet.example WRITE_CALENDAR allow 2>/dev/null || true
}

# Function to select device interactively
select_device() {
    echo -e "${BLUE}📱 Fetching devices:${NC}"
    echo "" 
    
    # Get device list, skip header line
    DEVICES=$(flutter devices 2>/dev/null | grep -E '•|−' | grep -v "No devices")
    
    if [ -z "$DEVICES" ]; then
        echo -e "${RED}❌ No devices found${NC}"
        echo ""
        echo "Make sure you have:"
        echo "  • An iOS simulator running (open Simulator.app)"
        echo "  • An Android emulator running"
        echo "  • A physical device connected"
        exit 1
    fi
    
    # Store devices in array
    declare -a DEVICE_IDS
    declare -a DEVICE_NAMES
    INDEX=1
    
    while IFS= read -r line; do
        # Extract device name (before the first •) and trim whitespace
        NAME=$(echo "$line" | sed 's/ *•.*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        # Extract device ID (between first and second •) and trim whitespace
        ID=$(echo "$line" | sed 's/[^•]*• //' | sed 's/ •.*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        if [ -n "$ID" ]; then
            DEVICE_IDS+=("$ID")
            DEVICE_NAMES+=("$NAME")
            echo -e "  ${CYAN}[$INDEX]${NC} $NAME"
            echo -e "      ${YELLOW}$ID${NC}"
            echo ""
            ((INDEX++))
        fi
    done <<< "$DEVICES"
    
    if [ ${#DEVICE_IDS[@]} -eq 0 ]; then
        echo -e "${RED}❌ Could not parse device list${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Select a device [1-$((INDEX-1))]:${NC} "
    read -r SELECTION
    
    # Validate selection
    if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || [ "$SELECTION" -lt 1 ] || [ "$SELECTION" -gt $((INDEX-1)) ]; then
        echo -e "${RED}❌ Invalid selection${NC}"
        exit 1
    fi
    
    DEVICE_ID="${DEVICE_IDS[$((SELECTION-1))]}"
    echo ""
    echo -e "${GREEN}✓${NC} Selected: ${DEVICE_NAMES[$((SELECTION-1))]}"
}

# Parse arguments
SKIP_TZ=false
DEVICE_ID=""
for arg in "$@"; do
    if [ "$arg" == "--no-tz" ]; then
        SKIP_TZ=true
    elif [ -z "$DEVICE_ID" ]; then
        DEVICE_ID="$arg"
    fi
done

if [ -z "$DEVICE_ID" ]; then
    select_device
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Device Calendar Plus - Integration Tests${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Detect platform
if [[ "$DEVICE_ID" == *"emulator"* ]] || flutter devices | grep "$DEVICE_ID" | grep -q "android"; then
    PLATFORM="android"
elif flutter devices | grep "$DEVICE_ID" | grep -q "ios"; then
    PLATFORM="ios"
else
    echo -e "${RED}❌ Could not detect platform for device: $DEVICE_ID${NC}"
    echo ""
    echo "Run 'flutter devices' to see available devices"
    exit 1
fi

echo -e "${GREEN}✓${NC} Device ID: ${YELLOW}$DEVICE_ID${NC}"
echo -e "${GREEN}✓${NC} Platform: ${YELLOW}$PLATFORM${NC}"
echo ""

# Detect Android emulators so the suite can skip tests that only fail on the
# emulator's Calendar Provider (e.g. recurrence exception inserts that wipe the
# master's instances). Physical devices and iOS run the full suite.
DART_DEFINES=""
if [ "$PLATFORM" == "android" ]; then
    QEMU=$(adb -s "$DEVICE_ID" shell getprop ro.boot.qemu 2>/dev/null | tr -d '\r')
    if [ "$QEMU" == "1" ] || [[ "$DEVICE_ID" == emulator-* ]]; then
        DART_DEFINES="--dart-define=DC_ANDROID_EMULATOR=true"
        echo -e "${YELLOW}⚠️  Android emulator detected — emulator-only flaky tests will be skipped${NC}"
        echo ""
    fi
fi

# A simulator's UDID appears in `simctl list devices`; a physical device's does
# not. Used to decide whether we can auto-grant (simctl is simulator-only) and
# whether the simctl cleanup at the end applies.
IOS_IS_SIMULATOR=false
if [ "$PLATFORM" == "ios" ] && xcrun simctl list devices 2>/dev/null | grep -q "$DEVICE_ID"; then
    IOS_IS_SIMULATOR=true
fi

# Grant permissions based on platform
if [ "$PLATFORM" == "ios" ]; then
    echo "🍎 iOS detected"

    if [ "$IOS_IS_SIMULATOR" == true ]; then
        echo "📱 Granting calendar permissions via xcrun..."
        # `|| true`: a transient grant failure must not abort the run under `set -e`.
        if xcrun simctl privacy "$DEVICE_ID" grant calendar to.bullet.example; then
            echo -e "${GREEN}✓${NC} Calendar permissions granted"
        else
            echo -e "${YELLOW}⚠️  Warning: Could not grant permissions${NC}"
            echo "   The simulator may need to be booted first"
            echo "   Tests may prompt for permissions on first run"
        fi
    else
        # Physical device: simctl can't touch its TCC database, so there's no way
        # to pre-grant from the CLI. The first run prompts on-device; tap Allow
        # once and the grant persists across reinstalls for this bundle id.
        echo -e "${YELLOW}📱 Physical device detected — calendar permission cannot be auto-granted${NC}"
        echo -e "${YELLOW}   👉 Watch the device and tap \"Allow\" on the calendar prompt the first time.${NC}"
        echo -e "${YELLOW}   (Once granted it persists for to.bullet.example, so later runs won't prompt.)${NC}"
    fi
    echo ""

elif [ "$PLATFORM" == "android" ]; then
    echo "🤖 Android detected"

    # pm grant only works once the app is installed. If it isn't installed
    # yet, do a build+install pass first so we can grant before the test run.
    if ! adb -s "$DEVICE_ID" shell pm list packages 2>/dev/null | grep -q 'to.bullet.example'; then
        echo "📦 App not installed — building and installing first..."
        (cd "$(dirname "$0")" && flutter build apk --debug -t integration_test/all_tests.dart)
        adb -s "$DEVICE_ID" install build/app/outputs/flutter-apk/app-debug.apk
        echo ""
    fi

    echo "📱 Granting calendar permissions via adb..."
    grant_android_calendar_permissions
    echo -e "${GREEN}✓${NC} Calendar permissions granted"
    echo ""
fi

cd "$(dirname "$0")"

# Heartbeat: when stdout isn't a TTY (Claude Code background tasks, CI logs,
# anything piped), background a 10s ping so the captured stream stays alive
# while flutter test buffers its own output. Without this, the Gradle build
# and quiet emulator-launch stretches look like a stall and the runner gets
# killed mid-run. Interactive shells get a TTY and skip this entirely.
if [ ! -t 1 ]; then
    HEARTBEAT_START=$(date +%s)
    (
        while sleep 10; do
            echo "[heartbeat $(($(date +%s)-HEARTBEAT_START))s @ $(date +%H:%M:%S)] integration tests running on $DEVICE_ID"
        done
    ) &
    HEARTBEAT_PID=$!
    trap 'kill $HEARTBEAT_PID 2>/dev/null' EXIT
fi

echo "🚀 Running integration tests on $DEVICE_ID..."
echo ""

# Run all integration tests in a single app launch.
# `flutter test` is used for both platforms: it self-terminates with a real
# exit code, unlike `flutter drive`, which hangs on teardown.
#
# Android quirk: `flutter test` does its own `adb install` before launching,
# which wipes runtime permissions granted with `pm grant`. There's no hook
# between install and launch, so we tail-grant in a tight loop in the
# background — every 0.5s for the lifetime of `flutter test` — which catches
# the post-install moment within sub-second latency, before the app's first
# permission check.
run_tests() {
    if [ "$PLATFORM" == "android" ]; then
        (
            while true; do
                grant_android_calendar_permissions
                sleep 0.5
            done
        ) &
        local grant_pid=$!
        flutter test integration_test/all_tests.dart -d "$DEVICE_ID" $DART_DEFINES
        local result=$?
        kill "$grant_pid" 2>/dev/null || true
        wait "$grant_pid" 2>/dev/null || true
        return $result
    fi
    flutter test integration_test/all_tests.dart -d "$DEVICE_ID" $DART_DEFINES
}

# Timezones to cycle through on Android (covers positive, negative, and zero offsets).
# All-day event boundary logic depends on correct UTC date extraction regardless of offset.
ANDROID_TIMEZONES=("America/Los_Angeles" "UTC" "Australia/Sydney")

if [ "$PLATFORM" == "android" ] && [ "$SKIP_TZ" == false ]; then
    # Save original timezone
    ORIGINAL_TZ=$(adb -s "$DEVICE_ID" shell getprop persist.sys.timezone | tr -d '\r')
    EXIT_CODE=0

    for TZ in "${ANDROID_TIMEZONES[@]}"; do
        echo -e "${CYAN}🕐 Setting timezone: $TZ${NC}"
        adb -s "$DEVICE_ID" shell "service call alarm 3 s16 $TZ" > /dev/null 2>&1
        sleep 1

        if ! run_tests; then
            echo -e "${RED}❌ Tests failed at timezone: $TZ${NC}"
            EXIT_CODE=1
            break
        fi
        echo -e "${GREEN}✓ Passed at $TZ${NC}"
        echo ""
    done

    # Restore original timezone
    echo -e "${CYAN}🕐 Restoring timezone: $ORIGINAL_TZ${NC}"
    adb -s "$DEVICE_ID" shell "service call alarm 3 s16 $ORIGINAL_TZ" > /dev/null 2>&1
else
    # iOS: run once (timezone issues are Android-specific)
    if run_tests; then
        EXIT_CODE=0
    else
        EXIT_CODE=1
    fi
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✅ All integration tests passed!${NC}"
else
    echo -e "${RED}❌ Some tests failed${NC}"

    if [ "$PLATFORM" == "ios" ]; then
        echo ""
        echo "If tests failed due to permissions:"
        echo "  1. Ensure the simulator is booted before running the script"
        echo "  2. Try: xcrun simctl privacy $DEVICE_ID reset calendar"
        echo "  3. Then run the script again"
    fi
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Device cleanup: uninstall the app so accumulated state (calendar
# provider DB, stale permissions, zombie Dart VM service ports) doesn't
# leak into the next run. The pre-install step at the top of the script
# will reinstall and re-grant permissions on the next invocation.
if [ "$PLATFORM" == "android" ]; then
    echo -e "${CYAN}🧹 Uninstalling app from $DEVICE_ID${NC}"
    adb -s "$DEVICE_ID" uninstall to.bullet.example > /dev/null 2>&1 || true
elif [ "$PLATFORM" == "ios" ] && [ "$IOS_IS_SIMULATOR" == true ]; then
    echo -e "${CYAN}🧹 Uninstalling app from $DEVICE_ID${NC}"
    xcrun simctl uninstall "$DEVICE_ID" to.bullet.example > /dev/null 2>&1 || true
elif [ "$PLATFORM" == "ios" ]; then
    # Physical device: keep the app installed so the on-device calendar grant
    # persists and later runs don't prompt again.
    echo -e "${CYAN}🧹 Leaving app installed on physical device (preserves the permission grant)${NC}"
fi

exit $EXIT_CODE

