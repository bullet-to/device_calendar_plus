import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockDeviceCalendarPlusPlatform extends DeviceCalendarPlusPlatform
    with MockPlatformInterfaceMixin {
  String? _platformVersion;
  int? _permissionStatusCode = 4; // CalendarPermissionStatus.notDetermined
  List<Map<String, dynamic>> _calendars = [];
  PlatformException? _exceptionToThrow;

  void setPlatformVersion(String? version) {
    _platformVersion = version;
  }

  void setPermissionStatus(CalendarPermissionStatus status) {
    _permissionStatusCode = status.index;
  }

  void setCalendars(List<Map<String, dynamic>> calendars) {
    _calendars = calendars;
  }

  void throwException(PlatformException exception) {
    _exceptionToThrow = exception;
  }

  void clearException() {
    _exceptionToThrow = null;
  }

  @override
  Future<String?> getPlatformVersion() async => _platformVersion;

  @override
  Future<int?> requestPermissions() async {
    if (_exceptionToThrow != null) {
      throw _exceptionToThrow!;
    }
    return _permissionStatusCode;
  }

  @override
  Future<List<Map<String, dynamic>>> listCalendars() async {
    if (_exceptionToThrow != null) {
      throw _exceptionToThrow!;
    }
    return _calendars;
  }
}

void main() {
  late MockDeviceCalendarPlusPlatform mockPlatform;

  setUp(() {
    mockPlatform = MockDeviceCalendarPlusPlatform();
    DeviceCalendarPlusPlatform.instance = mockPlatform;
  });

  group('DeviceCalendarPlugin', () {
    group('getPlatformVersion', () {
      test('returns platform version from platform interface', () async {
        mockPlatform.setPlatformVersion('Test Platform 1.0');
        final result = await DeviceCalendarPlugin.getPlatformVersion();
        expect(result, 'Test Platform 1.0');
      });
    });

    group('requestPermissions', () {
      group('status conversion', () {
        test('converts status code to CalendarPermissionStatus', () async {
          mockPlatform.setPermissionStatus(CalendarPermissionStatus.granted);
          final result = await DeviceCalendarPlugin.requestPermissions();
          expect(result, CalendarPermissionStatus.granted);
        });
      });

      group('edge case handling', () {
        test('defaults to denied when status is null', () async {
          mockPlatform._permissionStatusCode = null;
          final result = await DeviceCalendarPlugin.requestPermissions();
          expect(result, CalendarPermissionStatus.denied);
        });

        test('defaults to denied when status is negative', () async {
          mockPlatform._permissionStatusCode = -1;
          final result = await DeviceCalendarPlugin.requestPermissions();
          expect(result, CalendarPermissionStatus.denied);
        });

        test('defaults to denied when status is out of range', () async {
          mockPlatform._permissionStatusCode = 999;
          final result = await DeviceCalendarPlugin.requestPermissions();
          expect(result, CalendarPermissionStatus.denied);
        });
      });

      group('error handling', () {
        test('throws DeviceCalendarException when permissions not declared',
            () async {
          mockPlatform.throwException(
            PlatformException(
              code: 'PERMISSIONS_NOT_DECLARED',
              message: 'Calendar permissions must be declared',
            ),
          );

          expect(
            () => DeviceCalendarPlugin.requestPermissions(),
            throwsA(
              isA<DeviceCalendarException>().having(
                (e) => e.errorCode,
                'errorCode',
                DeviceCalendarError.permissionsNotDeclared,
              ),
            ),
          );
        });

        test('rethrows other PlatformExceptions unchanged', () async {
          mockPlatform.throwException(
            PlatformException(
              code: 'SOME_OTHER_ERROR',
              message: 'Something went wrong',
            ),
          );

          expect(
            () => DeviceCalendarPlugin.requestPermissions(),
            throwsA(
              isA<PlatformException>().having(
                (e) => e.code,
                'code',
                'SOME_OTHER_ERROR',
              ),
            ),
          );
        });
      });
    });

    group('listCalendars', () {
      test('returns list of Calendar objects', () async {
        mockPlatform.setCalendars([
          {
            'id': '1',
            'name': 'Work',
            'colorHex': '#FF0000',
            'readOnly': false,
            'accountName': 'work@example.com',
            'accountType': 'com.google',
            'isPrimary': true,
            'hidden': false,
          },
          {
            'id': '2',
            'name': 'Personal',
            'readOnly': true,
            'isPrimary': false,
            'hidden': false,
          },
        ]);

        final calendars = await DeviceCalendarPlugin.listCalendars();

        expect(calendars, hasLength(2));
        expect(calendars[0].id, '1');
        expect(calendars[0].name, 'Work');
        expect(calendars[0].colorHex, '#FF0000');
        expect(calendars[0].readOnly, false);
        expect(calendars[0].isPrimary, true);
        expect(calendars[0].hidden, false);

        expect(calendars[1].id, '2');
        expect(calendars[1].name, 'Personal');
        expect(calendars[1].readOnly, true);
        expect(calendars[1].isPrimary, false);
      });

      test('throws DeviceCalendarException when permission denied', () async {
        mockPlatform.throwException(
          PlatformException(
            code: 'PERMISSION_DENIED',
            message: 'Calendar permission denied',
          ),
        );

        expect(
          () => DeviceCalendarPlugin.listCalendars(),
          throwsA(
            isA<DeviceCalendarException>().having(
              (e) => e.errorCode,
              'errorCode',
              DeviceCalendarError.permissionDenied,
            ),
          ),
        );
      });

      test('returns empty list when no calendars', () async {
        mockPlatform.setCalendars([]);
        final calendars = await DeviceCalendarPlugin.listCalendars();
        expect(calendars, isEmpty);
      });
    });
  });
}
