import 'package:flutter_test/flutter_test.dart';
import 'package:device_calendar_plus_ios/device_calendar_plus_ios.dart';
import 'package:device_calendar_plus_ios/device_calendar_plus_ios_platform_interface.dart';
import 'package:device_calendar_plus_ios/device_calendar_plus_ios_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockDeviceCalendarPlusIosPlatform
    with MockPlatformInterfaceMixin
    implements DeviceCalendarPlusIosPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final DeviceCalendarPlusIosPlatform initialPlatform = DeviceCalendarPlusIosPlatform.instance;

  test('$MethodChannelDeviceCalendarPlusIos is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelDeviceCalendarPlusIos>());
  });

  test('getPlatformVersion', () async {
    DeviceCalendarPlusIos deviceCalendarPlusIosPlugin = DeviceCalendarPlusIos();
    MockDeviceCalendarPlusIosPlatform fakePlatform = MockDeviceCalendarPlusIosPlatform();
    DeviceCalendarPlusIosPlatform.instance = fakePlatform;

    expect(await deviceCalendarPlusIosPlugin.getPlatformVersion(), '42');
  });
}
