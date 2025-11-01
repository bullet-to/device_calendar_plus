import 'package:device_calendar_plus_ios/device_calendar_plus_ios.dart';
import 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeviceCalendarPlusIos', () {
    const kPlatformVersion = 'iOS 17.0';
    late DeviceCalendarPlusIos plugin;
    late List<MethodCall> log;

    setUp(() async {
      plugin = DeviceCalendarPlusIos();

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
      DeviceCalendarPlusIos.registerWith();
      expect(DeviceCalendarPlusPlatform.instance, isA<DeviceCalendarPlusIos>());
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
