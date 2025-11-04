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
NC='\033[0m' # No Color

# Check if device ID is provided
if [ -z "$1" ]; then
    echo -e "${RED}❌ Error: Device ID required${NC}"
    echo ""
    echo "Usage: $0 <device-id>"
    echo ""
    echo "Find device IDs with: flutter devices"
    echo ""
    echo "Examples:"
    echo "  $0 F0A86A59-EB1B-4AA2-B487-8D3AA46664D8  # iOS simulator"
    echo "  $0 emulator-5554                          # Android emulator"
    echo "  $0 booted                                 # Currently booted iOS simulator"
    exit 1
fi

DEVICE_ID="$1"

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

# Grant permissions based on platform
if [ "$PLATFORM" == "ios" ]; then
    echo "🍎 iOS detected"
    echo "📱 Granting calendar permissions via xcrun..."
    
    xcrun simctl privacy "$DEVICE_ID" grant calendar to.bullet.example
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} Calendar permissions granted"
    else
        echo -e "${YELLOW}⚠️  Warning: Could not grant permissions${NC}"
        echo "   The simulator may need to be booted first"
        echo "   Tests may prompt for permissions on first run"
    fi
    echo ""

elif [ "$PLATFORM" == "android" ]; then
    echo "🤖 Android detected"
    echo "  (Permissions will be granted automatically by test driver)"
    echo ""
fi

# Run the integration tests
echo "🚀 Running integration tests on $DEVICE_ID..."
echo ""

cd "$(dirname "$0")"

# Build test command based on platform
if [ "$PLATFORM" == "android" ]; then
    # Use custom driver that grants permissions via adb
    if flutter drive \
        --driver=integration_test/integration_test_driver.dart \
        --target=integration_test/device_calendar_test.dart \
        -d "$DEVICE_ID"; then
        EXIT_CODE=0
    else
        EXIT_CODE=1
    fi
else
    # iOS: Use regular flutter test
    if flutter test integration_test/device_calendar_test.dart -d "$DEVICE_ID"; then
        EXIT_CODE=0
    else
        EXIT_CODE=1
    fi
fi

echo ""
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

exit $EXIT_CODE

