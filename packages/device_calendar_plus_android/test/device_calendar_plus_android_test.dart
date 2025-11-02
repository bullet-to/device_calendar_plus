import 'package:device_calendar_plus_android/device_calendar_plus_android.dart';
import 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeviceCalendarPlusAndroid', () {
    const kPlatformVersion = 'Android 13';
    late DeviceCalendarPlusAndroid plugin;
    late List<MethodCall> log;

    setUp(() async {
      plugin = DeviceCalendarPlusAndroid();

      log = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(plugin.methodChannel, (methodCall) async {
        log.add(methodCall);
        switch (methodCall.method) {
          case 'getPlatformVersion':
            return kPlatformVersion;
          case 'requestPermissions':
            return 0; // CalendarPermissionStatus.granted
          default:
            return null;
        }
      });
    });

    test('can be registered', () {
      DeviceCalendarPlusAndroid.registerWith();
      expect(DeviceCalendarPlusPlatform.instance,
          isA<DeviceCalendarPlusAndroid>());
    });

    test('getPlatformVersion returns correct version', () async {
      final version = await plugin.getPlatformVersion();
      expect(
        log,
        <Matcher>[isMethodCall('getPlatformVersion', arguments: null)],
      );
      expect(version, equals(kPlatformVersion));
    });

    test('requestPermissions returns granted status', () async {
      final status = await plugin.requestPermissions();
      expect(
        log,
        <Matcher>[isMethodCall('requestPermissions', arguments: null)],
      );
      expect(status, equals(0)); // CalendarPermissionStatus.granted
    });
  });
}
