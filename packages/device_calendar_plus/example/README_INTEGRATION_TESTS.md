# Integration Tests

This directory contains integration tests for the Device Calendar Plus plugin.

## Running Integration Tests

### Quick Start

Use the provided script to automatically handle permissions and run tests:

```bash
./run_integration_tests.sh <device-id>
```

**Note:** The script handles everything automatically - no manual permission granting needed!

### Find Device IDs

List available devices:
```bash
flutter devices
```

Example output:
```
iPhone 16 (mobile) • F0A86A59-EB1B-4AA2-B487-8D3AA46664D8 • ios
sdk gphone64 arm64 (mobile) • emulator-5554 • android
```

### Examples

```bash
# Run on iOS simulator
./run_integration_tests.sh F0A86A59-EB1B-4AA2-B487-8D3AA46664D8

# Run on Android emulator
./run_integration_tests.sh emulator-5554

# Run on booted iOS simulator
./run_integration_tests.sh booted
```

**Note:** The script is recommended as it handles platform detection and permission granting automatically.