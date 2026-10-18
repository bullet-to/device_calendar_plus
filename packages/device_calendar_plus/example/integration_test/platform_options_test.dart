import 'dart:io' show Platform;

import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'series_fixtures.dart';

/// Integration tests for the platform-only options: the `android:` and `ios:`
/// parameters, each applied only on its own platform and ignored on the
/// other. The first event field is Android's `STATUS` (#70).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final plugin = DeviceCalendar.instance;

  String? calendarId;

  setUpAll(() async {
    await plugin.requestPermissions();
    calendarId = await plugin.createCalendar(
      name: 'Platform Options Test ${DateTime.now().millisecondsSinceEpoch}',
    );
  });

  tearDownAll(() async {
    if (calendarId != null) await plugin.deleteCalendar(calendarId!);
  });

  /// A one-off event an hour long, starting tomorrow at 10:00 local time.
  Future<String> createOneOff({EventOptionsAndroid? android}) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day + 1, 10);
    return plugin.createEvent(
      calendarId: requireCalendar(calendarId),
      title: 'Status one-off',
      startDate: start,
      endDate: start.add(const Duration(hours: 1)),
      android: android,
    );
  }

  /// A daily series of [count] occurrences with Android [status], seeded and
  /// listed as [seedSeries] does.
  Future<SeededSeries> seedStatusSeries(
    EventStatusAndroid status, {
    int count = 6,
  }) => seedSeries(
    plugin,
    calendarId,
    count: count,
    minOccurrences: count,
    create: (plugin, calendarId, {int count = 6}) async {
      final start = DateTime.now().add(const Duration(hours: 1));
      final eventId = await plugin.createEvent(
        calendarId: calendarId,
        title: 'Status series',
        startDate: start,
        endDate: start.add(const Duration(hours: 1)),
        recurrenceRule: DailyRecurrence(end: CountEnd(count)),
        timeZone: 'UTC',
        android: EventOptionsAndroid(status: status),
      );
      return (eventId: eventId, start: start);
    },
  );

  Future<List<EventStatus>> statusesOf(
    SeededSeries series,
    String eventId,
  ) async => (await occurrencesOf(
    plugin,
    requireCalendar(calendarId),
    eventId,
    series.start,
  )).map((e) => e.status).toList();

  group('Android event status (#70)', () {
    testWidgets('createEvent writes the status', (tester) async {
      final id = await createOneOff(
        android: const EventOptionsAndroid(
          status: EventStatusAndroid.tentative,
        ),
      );

      expect((await plugin.getEvent(id))!.status, EventStatus.tentative);
    });

    testWidgets('createEvent without one writes confirmed', (tester) async {
      final id = await createOneOff();

      expect((await plugin.getEvent(id))!.status, EventStatus.confirmed);
    });

    testWidgets('createEvent writes canceled, and the event is still listed', (
      tester,
    ) async {
      final id = await createOneOff(
        android: const EventOptionsAndroid(status: EventStatusAndroid.canceled),
      );

      final event = await plugin.getEvent(id);
      expect(event!.status, EventStatus.canceled);
      final listed = await plugin.listEvents(
        event.startDate,
        event.endDate,
        calendarIds: [requireCalendar(calendarId)],
      );
      expect(listed.map((e) => e.eventId), contains(id));
    });

    testWidgets('updateEvent changes the status', (tester) async {
      final id = await createOneOff();

      await plugin.updateEvent(
        instanceId: id,
        android: const EventUpdateOptionsAndroid(
          status: EventStatusAndroid.tentative,
        ),
      );

      expect((await plugin.getEvent(id))!.status, EventStatus.tentative);
    });

    testWidgets('updateEvent leaves the status alone when it is not passed', (
      tester,
    ) async {
      final id = await createOneOff(
        android: const EventOptionsAndroid(
          status: EventStatusAndroid.tentative,
        ),
      );

      await plugin.updateEvent(instanceId: id, title: 'Renamed');

      expect((await plugin.getEvent(id))!.status, EventStatus.tentative);
    });

    testWidgets('updateEvent on an occurrence sets its status alone', (
      tester,
    ) async {
      final series = await seedStatusSeries(EventStatusAndroid.tentative);
      final title =
          'Status occurrence ${DateTime.now().millisecondsSinceEpoch}';

      await plugin.updateEvent(
        instanceId: series.occurrences[2].instanceId,
        title: title,
        android: const EventUpdateOptionsAndroid(
          status: EventStatusAndroid.confirmed,
        ),
      );

      final detached = await eventsTitled(
        plugin,
        requireCalendar(calendarId),
        title,
        series.start,
      );
      expect(detached.single.status, EventStatus.confirmed);
      expect(
        await statusesOf(series, series.eventId),
        everyElement(EventStatus.tentative),
        reason: 'the rest of the series keeps its own status',
      );
    });

    testWidgets(
      'updateEvent on an occurrence without a status keeps the series status',
      (tester) async {
        final series = await seedStatusSeries(EventStatusAndroid.tentative);
        final title = 'Status kept ${DateTime.now().millisecondsSinceEpoch}';

        await plugin.updateEvent(
          instanceId: series.occurrences[2].instanceId,
          title: title,
        );

        final detached = await eventsTitled(
          plugin,
          requireCalendar(calendarId),
          title,
          series.start,
        );
        expect(detached.single.status, EventStatus.tentative);
      },
    );

    testWidgets(
      'updateEvent canceled on an occurrence removes it, as Android does',
      (tester) async {
        final series = await seedStatusSeries(EventStatusAndroid.confirmed);

        await plugin.updateEvent(
          instanceId: series.occurrences[2].instanceId,
          android: const EventUpdateOptionsAndroid(
            status: EventStatusAndroid.canceled,
          ),
        );

        final remaining = await occurrencesOf(
          plugin,
          requireCalendar(calendarId),
          series.eventId,
          series.start,
        );
        expect(startsOf(remaining), startsExcept(series.occurrences, {2}));
      },
    );

    testWidgets('updateRecurring allEvents sets the series status', (
      tester,
    ) async {
      final series = await seedStatusSeries(EventStatusAndroid.confirmed);

      await plugin.updateRecurring(
        series.eventId,
        EventSpan.allEvents,
        android: const EventUpdateOptionsAndroid(
          status: EventStatusAndroid.tentative,
        ),
      );

      expect(
        await statusesOf(series, series.eventId),
        everyElement(EventStatus.tentative),
      );
    });

    testWidgets(
      'updateRecurring allEvents canceled drops the series from listings, as '
      'Android does',
      (tester) async {
        final series = await seedStatusSeries(EventStatusAndroid.confirmed);

        await plugin.updateRecurring(
          series.eventId,
          EventSpan.allEvents,
          android: const EventUpdateOptionsAndroid(
            status: EventStatusAndroid.canceled,
          ),
        );

        expect(await statusesOf(series, series.eventId), isEmpty);
        expect(
          (await plugin.getEvent(series.eventId))!.status,
          EventStatus.canceled,
          reason: 'the series itself is still there, canceled',
        );
      },
    );

    testWidgets(
      'updateRecurring allEvents canceled keeps a detached occurrence status',
      (tester) async {
        final series = await seedStatusSeries(EventStatusAndroid.confirmed);
        final title = 'Status own ${DateTime.now().millisecondsSinceEpoch}';
        await plugin.updateEvent(
          instanceId: series.occurrences[2].instanceId,
          title: title,
          android: const EventUpdateOptionsAndroid(
            status: EventStatusAndroid.tentative,
          ),
        );

        await plugin.updateRecurring(
          series.eventId,
          EventSpan.allEvents,
          android: const EventUpdateOptionsAndroid(
            status: EventStatusAndroid.canceled,
          ),
        );

        final detached = await eventsTitled(
          plugin,
          requireCalendar(calendarId),
          title,
          series.start,
        );
        expect(
          detached.single.status,
          EventStatus.tentative,
          reason: 'the occurrence edited on its own keeps its own status',
        );
      },
    );

    testWidgets('updateRecurring thisAndFollowing sets the new series status', (
      tester,
    ) async {
      final series = await seedStatusSeries(EventStatusAndroid.tentative);

      final newId = await plugin.updateRecurring(
        series.occurrences[3].instanceId,
        EventSpan.thisAndFollowing,
        android: const EventUpdateOptionsAndroid(
          status: EventStatusAndroid.confirmed,
        ),
      );

      expect(newId, isNot(series.eventId), reason: 'the series must split');
      expect(await statusesOf(series, series.eventId), [
        for (var i = 0; i < 3; i++) EventStatus.tentative,
      ]);
      expect(await statusesOf(series, newId), [
        for (var i = 3; i < 6; i++) EventStatus.confirmed,
      ]);
    });

    testWidgets(
      'updateRecurring thisAndFollowing without a status carries the series one',
      (tester) async {
        final series = await seedStatusSeries(EventStatusAndroid.tentative);

        final newId = await plugin.updateRecurring(
          series.occurrences[3].instanceId,
          EventSpan.thisAndFollowing,
          title: 'Status split ${DateTime.now().millisecondsSinceEpoch}',
        );

        expect(await statusesOf(series, newId), [
          for (var i = 3; i < 6; i++) EventStatus.tentative,
        ]);
      },
    );

    testWidgets(
      'updateRecurring thisAndFollowing keeps a detached occurrence status',
      (tester) async {
        final series = await seedStatusSeries(EventStatusAndroid.confirmed);
        final title = 'Status carried ${DateTime.now().millisecondsSinceEpoch}';
        await plugin.updateEvent(
          instanceId: series.occurrences[4].instanceId,
          title: title,
          android: const EventUpdateOptionsAndroid(
            status: EventStatusAndroid.tentative,
          ),
        );

        await plugin.updateRecurring(
          series.occurrences[2].instanceId,
          EventSpan.thisAndFollowing,
          android: const EventUpdateOptionsAndroid(
            status: EventStatusAndroid.canceled,
          ),
        );

        final detached = await eventsTitled(
          plugin,
          requireCalendar(calendarId),
          title,
          series.start,
        );
        expect(
          detached.single.status,
          EventStatus.tentative,
          reason: 'the carried occurrence keeps its own status',
        );
      },
    );
  }, skip: !Platform.isAndroid);

  group('Android options on iOS', () {
    const android = EventUpdateOptionsAndroid(
      status: EventStatusAndroid.canceled,
    );

    testWidgets('createEvent ignores them', (tester) async {
      final baseline = await plugin.getEvent(await createOneOff());
      final id = await createOneOff(
        android: const EventOptionsAndroid(status: EventStatusAndroid.canceled),
      );

      final event = await plugin.getEvent(id);
      expect(event, isNotNull);
      expect(
        event!.status,
        baseline!.status,
        reason: 'the same as passing no options',
      );
    });

    testWidgets('updateEvent with only them changes nothing', (tester) async {
      final id = await createOneOff();
      final before = await plugin.getEvent(id);

      await plugin.updateEvent(instanceId: id, android: android);

      expect(await plugin.getEvent(id), before);
    });

    testWidgets('updateEvent applies the other fields alongside them', (
      tester,
    ) async {
      final id = await createOneOff();
      final before = await plugin.getEvent(id);

      await plugin.updateEvent(
        instanceId: id,
        title: 'Renamed on iOS',
        android: android,
      );

      final event = await plugin.getEvent(id);
      expect(event!.title, 'Renamed on iOS');
      expect(event.status, before!.status);
    });

    testWidgets('an occurrence edit with only them detaches nothing', (
      tester,
    ) async {
      final series = await seedSeries(
        plugin,
        calendarId,
        count: 4,
        minOccurrences: 4,
      );

      await plugin.updateEvent(
        instanceId: series.occurrences[1].instanceId,
        android: android,
      );

      expect(
        await occurrencesOf(
          plugin,
          requireCalendar(calendarId),
          series.eventId,
          series.start,
        ),
        series.occurrences,
      );
    });

    testWidgets(
      'updateRecurring thisAndFollowing with only them splits nothing',
      (tester) async {
        final series = await seedSeries(
          plugin,
          calendarId,
          count: 4,
          minOccurrences: 4,
        );

        final id = await plugin.updateRecurring(
          series.occurrences[2].instanceId,
          EventSpan.thisAndFollowing,
          android: android,
        );

        expect(id, series.eventId);
        expect(
          await occurrencesOf(
            plugin,
            requireCalendar(calendarId),
            series.eventId,
            series.start,
          ),
          series.occurrences,
        );
      },
    );
  }, skip: !Platform.isIOS);
}
