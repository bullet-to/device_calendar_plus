import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockDeviceCalendarPlusPlatform extends DeviceCalendarPlusPlatform
    with MockPlatformInterfaceMixin {
  String? _platformVersion;

  void setPlatformVersion(String? version) {
    _platformVersion = version;
  }

  @override
  Future<String?> getPlatformVersion() async => _platformVersion;
}

void main() {
  late MockDeviceCalendarPlusPlatform mockPlatform;

  setUp(() {
    mockPlatform = MockDeviceCalendarPlusPlatform();
    DeviceCalendarPlusPlatform.instance = mockPlatform;
  });

  group('DeviceCalendar', () {
    test('getPlatformVersion returns platform version', () async {
      mockPlatform.setPlatformVersion('Test Platform 1.0');
      final result = await DeviceCalendar.getPlatformVersion();
      expect(result, 'Test Platform 1.0');
    });
  });
}
