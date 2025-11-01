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
  });
}
