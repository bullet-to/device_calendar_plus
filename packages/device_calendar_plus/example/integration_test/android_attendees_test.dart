import 'dart:io' show Platform;

import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'series_fixtures.dart';

/// Integration tests for Android-only attendee writes:
/// `EventOptionsAndroid.attendees` and `EventUpdateOptionsAndroid.attendees`
/// (#71), read back through the shared `Event.attendees`.
///
/// SAFETY: a synced calendar's server can email an invitation to every
/// attendee written. These tests write only `@example.com` addresses, and
/// only to the local calendar they create themselves, never to an existing
/// or synced one.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final plugin = DeviceCalendar.instance;

  String? calendarId;

  setUpAll(() async {
    await plugin.requestPermissions();
    calendarId = await plugin.createCalendar(
      name: 'Attendee Write Test ${DateTime.now().millisecondsSinceEpoch}',
    );
  });

  tearDownAll(() async {
    if (calendarId != null) await plugin.deleteCalendar(calendarId!);
  });

  const ada = AttendeeAndroid(email: 'ada@example.com', name: 'Ada');
  const bob = AttendeeAndroid(
    email: 'bob@example.com',
    name: 'Bob',
    type: AttendeeTypeAndroid.optional,
    status: AttendeeStatusAndroid.accepted,
  );
  const room = AttendeeAndroid(
    email: 'room@example.com',
    type: AttendeeTypeAndroid.resource,
    relationship: AttendeeRelationshipAndroid.none,
    status: AttendeeStatusAndroid.tentative,
  );

  // How each attendee above reads back through the shared Attendee.
  const adaRead = Attendee(
    name: 'Ada',
    emailAddress: 'ada@example.com',
    role: AttendeeRole.required,
    status: AttendeeStatus.pending,
  );
  const bobRead = Attendee(
    name: 'Bob',
    emailAddress: 'bob@example.com',
    role: AttendeeRole.optional,
    status: AttendeeStatus.accepted,
  );
  const roomRead = Attendee(
    emailAddress: 'room@example.com',
    role: AttendeeRole.nonParticipant,
    status: AttendeeStatus.tentative,
  );

  /// A one-off event an hour long, starting tomorrow at 10:00 local time.
  Future<String> createOneOff({EventOptionsAndroid? android}) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day + 1, 10);
    return plugin.createEvent(
      calendarId: requireCalendar(calendarId),
      title: 'Attendee one-off',
      startDate: start,
      endDate: start.add(const Duration(hours: 1)),
      android: android,
    );
  }

  /// [event]'s attendees, none read as an empty list.
  List<Attendee> attendeesOf(Event? event) => event?.attendees ?? const [];

  Future<List<Attendee>> attendeesOfEvent(String id) async =>
      attendeesOf(await plugin.getEvent(id));

  /// A daily series of six occurrences with [attendees], seeded and listed
  /// as [seedSeries] does.
  Future<SeededSeries> seedAttendeeSeries(List<AttendeeAndroid> attendees) =>
      seedSeries(
        plugin,
        calendarId,
        count: 6,
        minOccurrences: 6,
        create: (plugin, calendarId, {int count = 6}) async {
          final start = DateTime.now().add(const Duration(hours: 1));
          final eventId = await plugin.createEvent(
            calendarId: calendarId,
            title: 'Attendee series',
            startDate: start,
            endDate: start.add(const Duration(hours: 1)),
            recurrenceRule: DailyRecurrence(end: CountEnd(count)),
            timeZone: 'UTC',
            android: EventOptionsAndroid(attendees: attendees),
          );
          return (eventId: eventId, start: start);
        },
      );

  /// The attendees of each occurrence of [eventId] listed from [series]'
  /// start.
  Future<List<List<Attendee>>> occurrenceAttendees(
    SeededSeries series,
    String eventId,
  ) async =>
      (await occurrencesOf(
        plugin,
        requireCalendar(calendarId),
        eventId,
        series.start,
      ))
          .map(attendeesOf)
          .toList();

  /// The events in [series]' window titled [title]: an occurrence detached
  /// under that title.
  Future<List<Event>> detachedTitled(SeededSeries series, String title) =>
      eventsTitled(plugin, requireCalendar(calendarId), title, series.start);

  group('Android attendee writes (#71)', () {
    testWidgets('createEvent writes the attendees', (tester) async {
      final id = await createOneOff(
        android: const EventOptionsAndroid(attendees: [ada, bob, room]),
      );

      expect(
        await attendeesOfEvent(id),
        unorderedEquals([adaRead, bobRead, roomRead]),
      );
    });

    testWidgets('createEvent without attendees writes none', (tester) async {
      final id = await createOneOff();

      expect(await attendeesOfEvent(id), isEmpty);
    });

    testWidgets('updateEvent set replaces the attendees', (tester) async {
      final id = await createOneOff(
        android: const EventOptionsAndroid(attendees: [ada, bob]),
      );

      await plugin.updateEvent(
        instanceId: id,
        android: const EventUpdateOptionsAndroid(
          attendees: Patch.set([room]),
        ),
      );

      expect(await attendeesOfEvent(id), [roomRead]);
    });

    testWidgets('updateEvent clear removes the attendees', (tester) async {
      final id = await createOneOff(
        android: const EventOptionsAndroid(attendees: [ada, bob]),
      );

      await plugin.updateEvent(
        instanceId: id,
        android: const EventUpdateOptionsAndroid(attendees: Patch.clear()),
      );

      expect(await attendeesOfEvent(id), isEmpty);
    });

    testWidgets('updateEvent leaves the attendees alone when not passed', (
      tester,
    ) async {
      final id = await createOneOff(
        android: const EventOptionsAndroid(attendees: [ada, bob]),
      );

      await plugin.updateEvent(instanceId: id, title: 'Renamed');

      final event = await plugin.getEvent(id);
      expect(event!.title, 'Renamed');
      expect(attendeesOf(event), unorderedEquals([adaRead, bobRead]));
    });

    testWidgets('updateEvent set applies alongside other fields', (
      tester,
    ) async {
      final id = await createOneOff();

      await plugin.updateEvent(
        instanceId: id,
        title: 'Renamed with guests',
        android: const EventUpdateOptionsAndroid(attendees: Patch.set([ada])),
      );

      final event = await plugin.getEvent(id);
      expect(event!.title, 'Renamed with guests');
      expect(attendeesOf(event), [adaRead]);
    });

    testWidgets('updateEvent on an occurrence sets its attendees alone', (
      tester,
    ) async {
      final series = await seedAttendeeSeries([ada]);
      final title =
          'Attendee occurrence ${DateTime.now().millisecondsSinceEpoch}';

      await plugin.updateEvent(
        instanceId: series.occurrences[2].instanceId,
        title: title,
        android: const EventUpdateOptionsAndroid(
          attendees: Patch.set([bob]),
        ),
      );

      final detached = await detachedTitled(series, title);
      expect(attendeesOf(detached.single), [bobRead]);
      expect(
        await occurrenceAttendees(series, series.eventId),
        everyElement([adaRead]),
        reason: 'the rest of the series keeps its own attendees',
      );
    });

    testWidgets(
      'updateEvent on an occurrence without attendees keeps the series ones',
      (tester) async {
        final series = await seedAttendeeSeries([ada, bob]);
        final title =
            'Attendees kept ${DateTime.now().millisecondsSinceEpoch}';

        await plugin.updateEvent(
          instanceId: series.occurrences[2].instanceId,
          title: title,
        );

        final detached = await detachedTitled(series, title);
        expect(
          attendeesOf(detached.single),
          unorderedEquals([adaRead, bobRead]),
        );
      },
    );

    testWidgets('updateEvent clear on an occurrence clears it alone', (
      tester,
    ) async {
      final series = await seedAttendeeSeries([ada]);
      final title =
          'Attendees cleared ${DateTime.now().millisecondsSinceEpoch}';

      await plugin.updateEvent(
        instanceId: series.occurrences[2].instanceId,
        title: title,
        android: const EventUpdateOptionsAndroid(attendees: Patch.clear()),
      );

      final detached = await detachedTitled(series, title);
      expect(attendeesOf(detached.single), isEmpty);
      expect(
        await occurrenceAttendees(series, series.eventId),
        everyElement([adaRead]),
      );
    });

    testWidgets('updateRecurring allEvents sets the series attendees', (
      tester,
    ) async {
      final series = await seedAttendeeSeries([ada]);

      await plugin.updateRecurring(
        series.eventId,
        EventSpan.allEvents,
        android: const EventUpdateOptionsAndroid(
          attendees: Patch.set([bob, room]),
        ),
      );

      final occurrences = await occurrenceAttendees(series, series.eventId);
      expect(occurrences, hasLength(6));
      for (final attendees in occurrences) {
        expect(attendees, unorderedEquals([bobRead, roomRead]));
      }
    });

    testWidgets(
      'updateRecurring allEvents keeps a detached occurrence attendees',
      (tester) async {
        final series = await seedAttendeeSeries([ada]);
        final title = 'Attendees own ${DateTime.now().millisecondsSinceEpoch}';
        await plugin.updateEvent(
          instanceId: series.occurrences[2].instanceId,
          title: title,
          android: const EventUpdateOptionsAndroid(
            attendees: Patch.set([room]),
          ),
        );

        await plugin.updateRecurring(
          series.eventId,
          EventSpan.allEvents,
          android: const EventUpdateOptionsAndroid(attendees: Patch.clear()),
        );

        expect(
          await occurrenceAttendees(series, series.eventId),
          everyElement(isEmpty),
        );
        final detached = await detachedTitled(series, title);
        expect(
          attendeesOf(detached.single),
          [roomRead],
          reason: 'the occurrence edited on its own keeps its own attendees',
        );
      },
    );

    testWidgets(
      'updateRecurring thisAndFollowing without attendees carries the series '
      'ones',
      (tester) async {
        final series = await seedAttendeeSeries([ada, bob]);

        final newId = await plugin.updateRecurring(
          series.occurrences[3].instanceId,
          EventSpan.thisAndFollowing,
          title: 'Attendee split ${DateTime.now().millisecondsSinceEpoch}',
        );

        expect(newId, isNot(series.eventId), reason: 'the series must split');
        final carried = await occurrenceAttendees(series, newId);
        expect(carried, hasLength(3));
        for (final attendees in carried) {
          expect(attendees, unorderedEquals([adaRead, bobRead]));
        }
      },
    );

    testWidgets(
      'updateRecurring thisAndFollowing sets the new series attendees',
      (tester) async {
        final series = await seedAttendeeSeries([ada]);

        final newId = await plugin.updateRecurring(
          series.occurrences[3].instanceId,
          EventSpan.thisAndFollowing,
          android: const EventUpdateOptionsAndroid(
            attendees: Patch.set([bob]),
          ),
        );

        expect(newId, isNot(series.eventId), reason: 'the series must split');
        expect(await occurrenceAttendees(series, series.eventId), [
          for (var i = 0; i < 3; i++) [adaRead],
        ]);
        expect(await occurrenceAttendees(series, newId), [
          for (var i = 3; i < 6; i++) [bobRead],
        ]);
      },
    );

    testWidgets(
      'updateRecurring thisAndFollowing clear leaves the new series none',
      (tester) async {
        final series = await seedAttendeeSeries([ada]);

        final newId = await plugin.updateRecurring(
          series.occurrences[3].instanceId,
          EventSpan.thisAndFollowing,
          android: const EventUpdateOptionsAndroid(attendees: Patch.clear()),
        );

        expect(newId, isNot(series.eventId), reason: 'the series must split');
        expect(
          await occurrenceAttendees(series, newId),
          [for (var i = 3; i < 6; i++) isEmpty],
        );
        expect(
          await occurrenceAttendees(series, series.eventId),
          everyElement([adaRead]),
          reason: 'the original series keeps its own',
        );
      },
    );

    testWidgets(
      'updateRecurring thisAndFollowing keeps a carried occurrence attendees',
      (tester) async {
        final series = await seedAttendeeSeries([ada]);
        final title =
            'Attendees carried ${DateTime.now().millisecondsSinceEpoch}';
        await plugin.updateEvent(
          instanceId: series.occurrences[4].instanceId,
          title: title,
          android: const EventUpdateOptionsAndroid(
            attendees: Patch.set([room]),
          ),
        );

        final newId = await plugin.updateRecurring(
          series.occurrences[2].instanceId,
          EventSpan.thisAndFollowing,
          android: const EventUpdateOptionsAndroid(
            attendees: Patch.set([bob]),
          ),
        );

        expect(newId, isNot(series.eventId), reason: 'the series must split');
        final detached = await detachedTitled(series, title);
        expect(
          attendeesOf(detached.single),
          [roomRead],
          reason: 'the carried occurrence keeps its own attendees',
        );
      },
    );
  }, skip: !Platform.isAndroid);

  group('Android attendees on iOS', () {
    const android = EventUpdateOptionsAndroid(attendees: Patch.set([ada]));

    testWidgets('createEvent ignores them', (tester) async {
      final id = await createOneOff(
        android: const EventOptionsAndroid(attendees: [ada, bob]),
      );

      expect(await attendeesOfEvent(id), isEmpty);
    });

    testWidgets('updateEvent with only them changes nothing', (tester) async {
      final id = await createOneOff();
      final before = await plugin.getEvent(id);

      await plugin.updateEvent(instanceId: id, android: android);

      expect(await plugin.getEvent(id), before);
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
          android: const EventUpdateOptionsAndroid(attendees: Patch.clear()),
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
