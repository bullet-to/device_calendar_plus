import 'dart:io' show Platform;

import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final plugin = DeviceCalendar.instance;

  final createdCalendarIds = <String>[];

  setUpAll(() async {
    await plugin.requestPermissions();
  });

  tearDownAll(() async {
    for (final id in createdCalendarIds) {
      try {
        await plugin.deleteCalendar(id);
      } catch (_) {}
    }
  });

  testWidgets('listSources returns non-empty list', (tester) async {
    final sources = await plugin.listSources();

    expect(sources, isNotEmpty);
    for (final source in sources) {
      expect(source.id, isNotEmpty);
      expect(source.accountName, isNotEmpty);
      expect(source.accountType, isNotEmpty);
      expect(source.type, isA<CalendarSourceType>());
    }
  });

  testWidgets('listSources includes local or calDav source', (tester) async {
    final sources = await plugin.listSources();

    final hasLocalOrCalDav = sources.any(
      (s) =>
          s.type == CalendarSourceType.local ||
          s.type == CalendarSourceType.calDav,
    );

    expect(hasLocalOrCalDav, isTrue,
        reason: 'Expected at least one local or calDav source');
  });

  testWidgets('createCalendar without source uses default fallback',
      (tester) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final calendarId = await plugin.createCalendar(
      name: 'Source Test Default $timestamp',
    );
    createdCalendarIds.add(calendarId);

    expect(calendarId, isNotEmpty);

    final calendars = await plugin.listCalendars();
    final created = calendars.firstWhere((c) => c.id == calendarId);
    expect(created.name, contains('Source Test Default'));
  });

  testWidgets(
    'iOS: createCalendar with explicit sourceId',
    (tester) async {
      final sources = await plugin.listSources();

      // Find a writable source (local or calDav)
      final source = sources.firstWhere(
        (s) =>
            s.type == CalendarSourceType.local ||
            s.type == CalendarSourceType.calDav,
      );

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final calendarId = await plugin.createCalendar(
        name: 'Source Test iOS $timestamp',
        platformOptions: CreateCalendarOptionsIos(sourceId: source.id),
      );
      createdCalendarIds.add(calendarId);

      expect(calendarId, isNotEmpty);

      final calendars = await plugin.listCalendars();
      final created = calendars.firstWhere((c) => c.id == calendarId);
      expect(created.accountName, equals(source.accountName));
    },
    skip: !Platform.isIOS,
  );

  testWidgets(
    'Android: createCalendar with explicit accountType',
    (tester) async {
      final sources = await plugin.listSources();

      final source = sources.firstWhere(
        (s) => s.type == CalendarSourceType.local,
      );

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final calendarId = await plugin.createCalendar(
        name: 'Source Test Android $timestamp',
        platformOptions: CreateCalendarOptionsAndroid(
          accountName: source.accountName,
          accountType: source.accountType,
        ),
      );
      createdCalendarIds.add(calendarId);

      expect(calendarId, isNotEmpty);

      final calendars = await plugin.listCalendars();
      final created = calendars.firstWhere((c) => c.id == calendarId);
      expect(created.accountName, equals(source.accountName));
    },
    skip: !Platform.isAndroid,
  );
}
