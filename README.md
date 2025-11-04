# device_calendar_plus

A modern, federated Flutter plugin for reading and writing device calendar events on Android and iOS.

> **Note:** This is the developer/contributor documentation. For plugin usage and API documentation, see the [device_calendar_plus package README](packages/device_calendar_plus/README.md).

## 🏗️ Architecture

This is a **federated plugin** following Flutter's federated plugin architecture:

```
device_calendar_plus/
├── packages/
│   ├── device_calendar_plus/              # Main package (public API)
│   ├── device_calendar_plus_platform_interface/  # Platform interface
│   ├── device_calendar_plus_android/      # Android implementation
│   └── device_calendar_plus_ios/          # iOS implementation
└── example/                                # Example app & integration tests
```

### Package Structure

- **`device_calendar_plus`**: The main package that app developers depend on. Contains the public Dart API and exports platform interface types.

- **`device_calendar_plus_platform_interface`**: Defines the interface that platform implementations must follow. Contains method signatures and data contracts.

- **`device_calendar_plus_android`**: Android-specific implementation using Kotlin and the Android Calendar Provider API.

- **`device_calendar_plus_ios`**: iOS-specific implementation using Swift and EventKit.

- **`example/`**: Example app demonstrating plugin usage, also contains integration tests.

## 🚀 Getting Started

### Prerequisites

- Flutter SDK (latest stable)
- For iOS development: Xcode 15+
- For Android development: Android Studio with Android SDK 24+

**Optional (but recommended):**
- [Very Good CLI](https://pub.dev/packages/very_good_cli): `dart pub global activate very_good_cli` - Makes running tests faster with optimized configuration

### Setup

1. Clone the repository:
```bash
git clone https://github.com/yourusername/device_calendar_plus.git
cd device_calendar_plus
```

2. Install dependencies:
```bash
flutter pub get
```

This project uses Dart workspaces, so a single `flutter pub get` at the root will install dependencies for all packages.


## 🧪 Testing

### Unit Tests

Run all unit tests across all packages using Very Good CLI (recommended):

```bash
very_good test --recursive
```

This will run tests in all `/packages/*/test/` directories with optimized configuration.

### Integration Tests

Integration tests are located in `example/integration_test/` and test the plugin against real platform APIs.

#### Running on a Device/Emulator

From the example directory:

```bash
cd example
./run_integration_tests.sh <device-id>
```

Get the device ID from:
```bash
flutter devices
```

#### Platform-Specific Notes

**iOS:**
- Requires a simulator or physical device
- Calendar permissions will be requested during tests
- Tests create temporary calendars that are cleaned up

**Android:**
- Requires an emulator or physical device with API 24+
- Calendar permissions will be requested during tests
- Tests create temporary calendars that are cleaned up

## 🤝 Contributing

Contributions are welcome! Please:

1. Open an issue first for major changes
2. Write tests for new features
3. Update documentation
4. Follow the existing code style
5. Ensure all tests pass before submitting PR

### Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add support for recurring events
fix: correct timezone handling for all-day events
docs: update API documentation
test: add integration tests for event creation
refactor: simplify permission handling
```

## 📄 License

MIT © 2025 Bullet

See [LICENSE](LICENSE) for details.

---

**Maintained by [Bullet](https://bullet.to)** — a cross-platform task + notes + calendar app built with Flutter.

