#!/bin/bash

set -e

echo "🔍 Running dry-run for all packages..."
echo ""

# Dry run for platform interface
echo "📋 Checking device_calendar_plus_platform_interface..."
cd packages/device_calendar_plus_platform_interface
dart pub publish --dry-run
cd ../..
echo ""

# Dry run for Android
echo "📋 Checking device_calendar_plus_android..."
cd packages/device_calendar_plus_android
dart pub publish --dry-run
cd ../..
echo ""

# Dry run for iOS
echo "📋 Checking device_calendar_plus_ios..."
cd packages/device_calendar_plus_ios
dart pub publish --dry-run
cd ../..
echo ""

# Dry run for main package
echo "📋 Checking device_calendar_plus..."
cd packages/device_calendar_plus
dart pub publish --dry-run
cd ../..
echo ""

# Prompt for confirmation
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
read -p "Do you want to publish all packages to pub.dev? (y/N): " -n 1 -r
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Publication cancelled."
    exit 0
fi

echo ""
echo "📦 Publishing packages to pub.dev..."
echo ""

# Publish platform interface first (dependency for others)
echo "📦 Publishing device_calendar_plus_platform_interface..."
cd packages/device_calendar_plus_platform_interface
dart pub publish --force
cd ../..
echo ""

# Publish Android implementation
echo "📦 Publishing device_calendar_plus_android..."
cd packages/device_calendar_plus_android
dart pub publish --force
cd ../..
echo ""

# Publish iOS implementation
echo "📦 Publishing device_calendar_plus_ios..."
cd packages/device_calendar_plus_ios
dart pub publish --force
cd ../..
echo ""

# Publish main package last
echo "📦 Publishing device_calendar_plus..."
cd packages/device_calendar_plus
dart pub publish --force
cd ../..
echo ""

echo "✅ All packages published successfully!"

