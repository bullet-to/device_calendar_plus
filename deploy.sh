#!/bin/bash

set -e

echo "Publishing device_calendar_plus packages to pub.dev..."
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

