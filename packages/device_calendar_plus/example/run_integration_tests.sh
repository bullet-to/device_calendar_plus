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

# Check if device ID is provided
if [ -z "$1" ]; then
    select_device
else
    DEVICE_ID="$1"
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

cd "$(dirname "$0")"

echo "🚀 Running integration tests on $DEVICE_ID..."
echo ""

# Run all integration tests in a single app launch
if [ "$PLATFORM" == "android" ]; then
    # Use custom driver that grants permissions via adb
    if flutter drive \
        --driver=integration_test/integration_test_driver.dart \
        --target=integration_test/all_tests.dart \
        -d "$DEVICE_ID"; then
        EXIT_CODE=0
    else
        EXIT_CODE=1
    fi
else
    # iOS: Use regular flutter test
    if flutter test integration_test/all_tests.dart -d "$DEVICE_ID"; then
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

exit $EXIT_CODE

