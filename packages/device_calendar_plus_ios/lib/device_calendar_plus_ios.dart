
import 'device_calendar_plus_ios_platform_interface.dart';

class DeviceCalendarPlusIos {
  Future<String?> getPlatformVersion() {
    return DeviceCalendarPlusIosPlatform.instance.getPlatformVersion();
  }
}
