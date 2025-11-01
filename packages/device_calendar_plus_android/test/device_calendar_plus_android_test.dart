import 'package:flutter_test/flutter_test.dart';
import 'package:device_calendar_plus_android/device_calendar_plus_android.dart';
import 'package:device_calendar_plus_android/device_calendar_plus_android_platform_interface.dart';
import 'package:device_calendar_plus_android/device_calendar_plus_android_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockDeviceCalendarPlusAndroidPlatform
    with MockPlatformInterfaceMixin
    implements DeviceCalendarPlusAndroidPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final DeviceCalendarPlusAndroidPlatform initialPlatform = DeviceCalendarPlusAndroidPlatform.instance;

  test('$MethodChannelDeviceCalendarPlusAndroid is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelDeviceCalendarPlusAndroid>());
  });

  test('getPlatformVersion', () async {
    DeviceCalendarPlusAndroid deviceCalendarPlusAndroidPlugin = DeviceCalendarPlusAndroid();
    MockDeviceCalendarPlusAndroidPlatform fakePlatform = MockDeviceCalendarPlusAndroidPlatform();
    DeviceCalendarPlusAndroidPlatform.instance = fakePlatform;

    expect(await deviceCalendarPlusAndroidPlugin.getPlatformVersion(), '42');
  });
}
