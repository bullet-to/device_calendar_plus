
import 'device_calendar_plus_android_platform_interface.dart';

class DeviceCalendarPlusAndroid {
  Future<String?> getPlatformVersion() {
    return DeviceCalendarPlusAndroidPlatform.instance.getPlatformVersion();
  }
}
