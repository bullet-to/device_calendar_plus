import 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MethodChannelDeviceCalendarPlus', () {
    late MethodChannelDeviceCalendarPlus methodChannel;
    final log = <MethodCall>[];

    setUp(() {
      methodChannel = MethodChannelDeviceCalendarPlus();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        methodChannel.methodChannel,
        (call) async {
          log.add(call);
          switch (call.method) {
            case 'getPlatformVersion':
              return '42';
            default:
              return null;
          }
        },
      );
    });

    tearDown(log.clear);

    test('getPlatformVersion', () async {
      final version = await methodChannel.getPlatformVersion();
      expect(
        log,
        <Matcher>[isMethodCall('getPlatformVersion', arguments: null)],
      );
      expect(version, '42');
    });
  });
}
