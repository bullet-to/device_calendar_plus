import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'series_fixtures.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Recurrence Read Tests (#122)', () {
    late DeviceCalendar plugin;
    String? calendarId;

    setUpAll(() async {
      plugin = DeviceCalendar.instance;
      await plugin.requestPermissions();

      calendarId = await plugin.createCalendar(
        name: 'Recurrence Read Test ${DateTime.now().millisecondsSinceEpoch}',
        colorHex: '#3366FF',
      );
    });

    tearDownAll(() async {
      if (calendarId != null) {
        await plugin.deleteCalendar(calendarId!);
      }
    });

    // Android stores an all-day occurrence at UTC midnight and reports it at
    // local midnight; its instance ID carries the stored instant, and
    // getEvent must resolve that ID exactly as listEvents handed it out.
    test(
      'getEvent resolves an all-day recurring occurrence by instance ID',
      () async {
        expect(
          calendarId,
          isNotNull,
          reason: 'setUpAll must create a calendar',
        );
        final series = await createAllDayDailySeries(
          plugin,
          calendarId!,
          count: 4,
        );

        final occurrences = await occurrencesOf(
          plugin,
          calendarId!,
          series.eventId,
          series.start,
        );
        expect(
          occurrences.length,
          4,
          reason: 'the series must expand to every occurrence',
        );

        for (final occurrence in occurrences) {
          final fetched = await plugin.getEvent(occurrence.instanceId);
          expect(
            fetched,
            isNotNull,
            reason:
                'getEvent must resolve the instance ID listEvents '
                'returned (${occurrence.instanceId})',
          );
          expect(fetched!.instanceId, occurrence.instanceId);
          expect(fetched.isAllDay, isTrue);
          expect(fetched.startDate, occurrence.startDate);
          expect(fetched.endDate, occurrence.endDate);
        }
      },
    );

    test(
      'getEvent resolves a timed recurring occurrence by instance ID',
      () async {
        expect(
          calendarId,
          isNotNull,
          reason: 'setUpAll must create a calendar',
        );
        final series = await createDailySeries(plugin, calendarId!, count: 4);

        final occurrences = await occurrencesOf(
          plugin,
          calendarId!,
          series.eventId,
          series.start,
        );
        expect(
          occurrences.length,
          4,
          reason: 'the series must expand to every occurrence',
        );

        final target = occurrences[2];
        final fetched = await plugin.getEvent(target.instanceId);
        expect(
          fetched,
          isNotNull,
          reason: 'getEvent must resolve the instance ID listEvents returned',
        );
        expect(fetched!.instanceId, target.instanceId);
        expect(fetched.startDate, target.startDate);
        expect(fetched.endDate, target.endDate);
      },
    );

    // Android stores a recurring master as DTSTART + DURATION with no DTEND,
    // so the master's end must come from its duration.
    test('getEvent returns a timed master with its real end date', () async {
      expect(calendarId, isNotNull, reason: 'setUpAll must create a calendar');
      final series = await createDailySeries(plugin, calendarId!, count: 3);

      final master = await plugin.getEvent(series.eventId);
      expect(master, isNotNull);
      expect(master!.isRecurring, isTrue);
      expect(
        master.endDate.difference(master.startDate),
        const Duration(hours: 1),
        reason:
            'the master must carry the series duration, not a '
            'zero-length end',
      );
    });

    test(
      'getEvent returns an all-day master ending at the next local midnight',
      () async {
        expect(
          calendarId,
          isNotNull,
          reason: 'setUpAll must create a calendar',
        );
        final series = await createAllDayDailySeries(
          plugin,
          calendarId!,
          count: 3,
        );

        final master = await plugin.getEvent(series.eventId);
        expect(master, isNotNull);
        expect(master!.isAllDay, isTrue);
        expect(master.startDate, series.start);
        expect(
          master.endDate,
          series.end,
          reason:
              'an all-day master spans its day, ending at the next '
              'local midnight',
        );
      },
    );
  });
}
