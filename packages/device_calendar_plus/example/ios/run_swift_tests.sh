#!/bin/bash

# Swift Unit Test Runner for Device Calendar Plus
#
# The Swift tests for device_calendar_plus_ios live in this app's RunnerTests
# target, so running them needs the Xcode config that
# `flutter build ios --config-only` generates. That build also runs
# `pod install`, which rewrites Runner.xcodeproj and Runner.xcworkspace — churn
# that must never ride into a commit.
#
# So this script snapshots both paths before the build and puts them back on the
# way out, from a trap, so a failing test or a Ctrl-C cleans up just the same.
# Restoring rather than discarding means deliberate project edits of your own
# (adding a test file to the RunnerTests target, say) survive the run whether or
# not you have committed them yet.
#
# Usage:
#   ./run_swift_tests.sh                                    # first available iPhone simulator
#   ./run_swift_tests.sh 'platform=iOS Simulator,name=iPhone 17'

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

IOS_DIR="$(cd "$(dirname "$0")" && pwd)"
EXAMPLE_DIR="$(dirname "$IOS_DIR")"

# The two tracked paths `pod install` rewrites. (Podfile.lock and Pods/ are
# gitignored, so they need no protection.)
GENERATED=("Runner.xcodeproj" "Runner.xcworkspace")
SNAPSHOT_DIR=""

restore_generated() {
    if [ -z "$SNAPSHOT_DIR" ]; then
        return
    fi
    for path in "${GENERATED[@]}"; do
        rm -rf "${IOS_DIR:?}/$path"
        if [ -e "$SNAPSHOT_DIR/$path" ]; then
            cp -R "$SNAPSHOT_DIR/$path" "$IOS_DIR/$path"
        fi
    done
    rm -rf "$SNAPSHOT_DIR"
    SNAPSHOT_DIR=""
    echo -e "${CYAN}🧹 Restored Runner.xcodeproj and Runner.xcworkspace${NC}"
}

# EXIT covers a normal finish, a failing test under `set -e`, and (with the
# signal traps re-raising) an interrupt.
trap restore_generated EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Pick a destination: the caller's, or the first available iPhone simulator.
DESTINATION="${1:-}"
if [ -z "$DESTINATION" ]; then
    SIMULATOR=$(xcrun simctl list devices available \
        | sed -n 's/^ *\(iPhone [^(]*\)(.*/\1/p' \
        | sed 's/ *$//' \
        | head -1)
    if [ -z "$SIMULATOR" ]; then
        echo -e "${RED}❌ No available iPhone simulator found${NC}"
        echo ""
        echo "Install one via Xcode, or pass a destination explicitly:"
        echo "  ./run_swift_tests.sh 'platform=iOS Simulator,name=iPhone 17'"
        echo ""
        echo "List what you have with: xcrun simctl list devices available"
        exit 1
    fi
    DESTINATION="platform=iOS Simulator,name=$SIMULATOR"
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Device Calendar Plus - Swift Unit Tests${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${GREEN}✓${NC} Destination: ${YELLOW}$DESTINATION${NC}"
echo ""

SNAPSHOT_DIR="$(mktemp -d)"
for path in "${GENERATED[@]}"; do
    if [ -e "$IOS_DIR/$path" ]; then
        cp -R "$IOS_DIR/$path" "$SNAPSHOT_DIR/$path"
    fi
done

echo -e "${CYAN}🔧 Generating the Xcode config (this runs pod install)...${NC}"
(cd "$EXAMPLE_DIR" && flutter build ios --config-only --simulator)
echo ""

echo -e "${CYAN}🧪 Running RunnerTests...${NC}"
echo ""
EXIT_CODE=0
xcodebuild test \
    -workspace "$IOS_DIR/Runner.xcworkspace" \
    -scheme Runner \
    -destination "$DESTINATION" \
    -only-testing:RunnerTests || EXIT_CODE=$?

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✅ All Swift unit tests passed!${NC}"
else
    echo -e "${RED}❌ Some Swift unit tests failed${NC}"
    echo ""
    echo "If the destination was the problem, list your simulators with:"
    echo "  xcrun simctl list devices available"
fi
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

exit $EXIT_CODE
