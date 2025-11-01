import 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockDeviceCalendarPlusPlatform extends DeviceCalendarPlusPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<String?> getPlatformVersion() async => 'Mock Platform 1.0';
}

void main() {
  test('can set and get custom instance', () {
    final mock = MockDeviceCalendarPlusPlatform();
    DeviceCalendarPlusPlatform.instance = mock;
    expect(DeviceCalendarPlusPlatform.instance, mock);
  });

  test('getPlatformVersion returns expected value', () async {
    final mock = MockDeviceCalendarPlusPlatform();
    DeviceCalendarPlusPlatform.instance = mock;
    expect(await DeviceCalendarPlusPlatform.instance.getPlatformVersion(),
        'Mock Platform 1.0');
  });
}
