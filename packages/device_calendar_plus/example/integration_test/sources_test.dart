import 'dart:io' show Platform;

import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Mirrors the native iOS no-source fallback: of the sources that support
/// creation, prefer calDav (iCloud), otherwise the first one (local). Other
/// calDav sources (e.g. Google) don't allow programmatic calendar creation.
CalendarSource expectedIosDefaultSource(List<CalendarSource> sources) {
  final creatable = sources.where((s) => s.supportsCalendarCreation);
  return creatable.firstWhere(
    (s) => s.type == CalendarSourceType.calDav,
    orElse: () => creatable.first,
  );
}

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

    if (Platform.isIOS) {
      // The fallback and listSources share one rule, so the calendar lands
      // under the source listSources says it would.
      final expected = expectedIosDefaultSource(await plugin.listSources());
      expect(created.accountName, equals(expected.accountName));
    }
  });

  testWidgets(
    'iOS: createCalendar with explicit sourceId',
    (tester) async {
      final sources = await plugin.listSources();

      final source = sources.firstWhere((s) => s.supportsCalendarCreation);

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final calendarId = await plugin.createCalendar(
        name: 'Source Test iOS $timestamp',
        ios: CalendarOptionsIos(sourceId: source.id),
        // Ignored on iOS: the calendar still lands under the iOS source.
        android: const CalendarOptionsAndroid(
          accountName: 'ignored',
          accountType: 'com.google',
        ),
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
        android: CalendarOptionsAndroid(
          accountName: source.accountName,
          accountType: source.accountType,
        ),
        // Ignored on Android: the calendar still lands under the account.
        ios: const CalendarOptionsIos(sourceId: 'ignored'),
      );
      createdCalendarIds.add(calendarId);

      expect(calendarId, isNotEmpty);

      final calendars = await plugin.listCalendars();
      final created = calendars.firstWhere((c) => c.id == calendarId);
      expect(created.accountName, equals(source.accountName));
    },
    skip: !Platform.isAndroid,
  );

  // Regression (#126): listSources reports every non-local account as
  // supportsCalendarCreation=false, but createCalendar used to insert a
  // phantom calendar under it anyway — one the account's real sync adapter
  // can wipe at any time. iOS already pre-rejects such sources with readOnly.
  testWidgets(
    'Android: createCalendar under a non-local account type throws readOnly',
    (tester) async {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      try {
        final calendarId = await plugin.createCalendar(
          name: 'Phantom $timestamp',
          android: const CalendarOptionsAndroid(
            accountName: 'someone@example.com',
            accountType: 'com.google',
          ),
        );
        createdCalendarIds.add(calendarId);
        fail('Expected readOnly, but a calendar was created: $calendarId');
      } on DeviceCalendarException catch (e) {
        expect(e.errorCode, DeviceCalendarError.readOnly);
      }
    },
    skip: !Platform.isAndroid,
  );
}
