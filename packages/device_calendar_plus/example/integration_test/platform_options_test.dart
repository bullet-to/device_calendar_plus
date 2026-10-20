import 'dart:io' show Platform;

import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'series_fixtures.dart';

/// Integration tests for the platform-only options: the `android:` and `ios:`
/// parameters, each applied only on its own platform and ignored on the
/// other. The event fields are Android's `STATUS` (#70) and its attendee
/// writes (#71), read back through the shared `Event.attendees`.
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
      name: 'Platform Options Test ${DateTime.now().millisecondsSinceEpoch}',
    );
  });

  tearDownAll(() async {
    if (calendarId != null) await plugin.deleteCalendar(calendarId!);
  });

  /// A one-off event an hour long, starting tomorrow at 10:00 local time.
  Future<String> createOneOff({
    EventOptionsAndroid? android,
    List<Duration>? reminders,
  }) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day + 1, 10);
    return plugin.createEvent(
      calendarId: requireCalendar(calendarId),
      title: 'Options one-off',
      startDate: start,
      endDate: start.add(const Duration(hours: 1)),
      reminders: reminders,
      android: android,
    );
  }

  /// A daily series of [count] occurrences created with the Android
  /// options [android], seeded and listed as [seedSeries] does.
  Future<SeededSeries> seedOptionSeries(
    EventOptionsAndroid android, {
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
        title: 'Options series',
        startDate: start,
        endDate: start.add(const Duration(hours: 1)),
        recurrenceRule: DailyRecurrence(end: CountEnd(count)),
        timeZone: 'UTC',
        android: android,
      );
      return (eventId: eventId, start: start);
    },
  );

  /// A daily series of six occurrences with Android [status].
  Future<SeededSeries> seedStatusSeries(EventStatusAndroid status) =>
      seedOptionSeries(EventOptionsAndroid(status: status));

  /// A daily series of six occurrences with Android [attendees].
  Future<SeededSeries> seedAttendeeSeries(
          List<AttendeeWriteAndroid> attendees) =>
      seedOptionSeries(EventOptionsAndroid(attendees: attendees));

  /// The occurrences of [eventId] (by default [series] itself) listed from
  /// [series]' start.
  Future<List<Event>> seriesOccurrences(
    SeededSeries series, [
    String? eventId,
  ]) => occurrencesOf(
    plugin,
    requireCalendar(calendarId),
    eventId ?? series.eventId,
    series.start,
  );

  Future<List<EventStatus>> statusesOf(
    SeededSeries series,
    String eventId,
  ) async =>
      (await seriesOccurrences(series, eventId)).map((e) => e.status).toList();

  /// The events in [series]' window titled [title]: an occurrence detached
  /// under that title.
  Future<List<Event>> detachedTitled(SeededSeries series, String title) =>
      eventsTitled(plugin, requireCalendar(calendarId), title, series.start);

  const ada = AttendeeWriteAndroid(email: 'ada@example.com', name: 'Ada');
  const bob = AttendeeWriteAndroid(
    email: 'bob@example.com',
    name: 'Bob',
    type: AttendeeTypeAndroid.optional,
    status: AttendeeStatusAndroid.accepted,
  );
  const room = AttendeeWriteAndroid(
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

  /// [event]'s attendees, none read as an empty list.
  List<Attendee> attendeesOf(Event? event) => event?.attendees ?? const [];

  Future<List<Attendee>> attendeesOfEvent(String id) async =>
      attendeesOf(await plugin.getEvent(id));

  /// The attendees of each occurrence of [eventId] listed from [series]'
  /// start.
  Future<List<List<Attendee>>> occurrenceAttendees(
    SeededSeries series,
    String eventId,
  ) async =>
      (await seriesOccurrences(series, eventId)).map(attendeesOf).toList();

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

      final detached = await detachedTitled(series, title);
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

        final detached = await detachedTitled(series, title);
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

        final remaining = await seriesOccurrences(series);
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

        final detached = await detachedTitled(series, title);
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

        final newId = await plugin.updateRecurring(
          series.occurrences[2].instanceId,
          EventSpan.thisAndFollowing,
          android: const EventUpdateOptionsAndroid(
            status: EventStatusAndroid.canceled,
          ),
        );

        expect(newId, isNot(series.eventId), reason: 'the series must split');
        final detached = await detachedTitled(series, title);
        expect(
          detached.single.status,
          EventStatus.tentative,
          reason: 'the carried occurrence keeps its own status',
        );
      },
    );
  }, skip: !Platform.isAndroid);

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

    testWidgets('createEvent and updateEvent write reminders with them', (
      tester,
    ) async {
      // Reminders and attendees share one child-row batch: this pins its
      // back-references and op order when both kinds are in the same write.
      final id = await createOneOff(
        reminders: const [Duration(minutes: 15)],
        android: const EventOptionsAndroid(attendees: [ada, bob]),
      );

      var event = await plugin.getEvent(id);
      expect(event!.reminders, const [Duration(minutes: 15)]);
      expect(attendeesOf(event), unorderedEquals([adaRead, bobRead]));

      await plugin.updateEvent(
        instanceId: id,
        reminders: const Patch.set([Duration(minutes: 30)]),
        android: const EventUpdateOptionsAndroid(
          attendees: Patch.set([room]),
        ),
      );

      event = await plugin.getEvent(id);
      expect(event!.reminders, const [Duration(minutes: 30)]);
      expect(attendeesOf(event), [roomRead]);
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

  group('Android organizer reads (#236)', () {
    const owner = AttendeeWriteAndroid(
      email: 'owner@example.com',
      name: 'Owner',
      relationship: AttendeeRelationshipAndroid.organizer,
      status: AttendeeStatusAndroid.accepted,
    );
    const ownerRead = Organizer(
      name: 'Owner',
      emailAddress: 'owner@example.com',
    );

    testWidgets('the organizer row reads as the organizer, not an attendee', (
      tester,
    ) async {
      final id = await createOneOff(
        android: const EventOptionsAndroid(attendees: [owner, ada]),
      );

      final event = await plugin.getEvent(id);
      expect(event!.organizer, ownerRead);
      expect(attendeesOf(event), [adaRead]);
    });

    testWidgets(
      'without an organizer row it falls back to the ORGANIZER column',
      (tester) async {
        final id = await createOneOff(
          android: const EventOptionsAndroid(attendees: [ada]),
        );

        // The provider fills ORGANIZER in with the calendar's owner account,
        // which createCalendar sets to its account name.
        final calendar = (await plugin.listCalendars()).singleWhere(
          (c) => c.id == calendarId,
        );
        expect(
          (await plugin.getEvent(id))!.organizer,
          Organizer(emailAddress: calendar.accountName),
        );
      },
    );

    testWidgets('an event without attendee rows has no organizer', (
      tester,
    ) async {
      final id = await createOneOff();

      expect((await plugin.getEvent(id))!.organizer, isNull);
    });

    testWidgets('updateEvent clear keeps the organizer', (tester) async {
      final id = await createOneOff(
        android: const EventOptionsAndroid(attendees: [owner, ada]),
      );

      await plugin.updateEvent(
        instanceId: id,
        android: const EventUpdateOptionsAndroid(attendees: Patch.clear()),
      );

      final event = await plugin.getEvent(id);
      expect(event!.organizer, ownerRead);
      expect(attendeesOf(event), isEmpty);
    });

    testWidgets('updateEvent set keeps the organizer', (tester) async {
      final id = await createOneOff(
        android: const EventOptionsAndroid(attendees: [owner, ada]),
      );

      await plugin.updateEvent(
        instanceId: id,
        android: const EventUpdateOptionsAndroid(attendees: Patch.set([bob])),
      );

      final event = await plugin.getEvent(id);
      expect(event!.organizer, ownerRead);
      expect(attendeesOf(event), [bobRead]);
    });

    testWidgets('updateEvent set with an organizer replaces it', (
      tester,
    ) async {
      const newOwner = AttendeeWriteAndroid(
        email: 'new-owner@example.com',
        name: 'New Owner',
        relationship: AttendeeRelationshipAndroid.organizer,
        status: AttendeeStatusAndroid.accepted,
      );
      final id = await createOneOff(
        android: const EventOptionsAndroid(attendees: [owner, ada]),
      );

      await plugin.updateEvent(
        instanceId: id,
        android: const EventUpdateOptionsAndroid(
          attendees: Patch.set([newOwner, bob]),
        ),
      );

      final event = await plugin.getEvent(id);
      expect(
        event!.organizer,
        const Organizer(
          name: 'New Owner',
          emailAddress: 'new-owner@example.com',
        ),
      );
      expect(attendeesOf(event), [bobRead]);
    });

    testWidgets(
      'the owner account as an ordinary attendee is the organizer too',
      (tester) async {
        // Event.attendees leaves out only the organizer row, so the
        // ORGANIZER fallback can name someone who is also an attendee.
        final calendar = (await plugin.listCalendars()).singleWhere(
          (c) => c.id == calendarId,
        );
        final account = calendar.accountName!;
        final id = await createOneOff(
          android: EventOptionsAndroid(
            attendees: [AttendeeWriteAndroid(email: account)],
          ),
        );

        final event = await plugin.getEvent(id);
        expect(event!.organizer, Organizer(emailAddress: account));
        expect(
          attendeesOf(event).map((a) => a.emailAddress),
          [account],
        );
      },
    );

    testWidgets('listed occurrences of a series carry its organizer', (
      tester,
    ) async {
      final series = await seedAttendeeSeries([owner, ada]);

      expect(
        series.occurrences.map((e) => e.organizer),
        everyElement(ownerRead),
      );
    });
  }, skip: !Platform.isAndroid);

  group('Android options on iOS', () {
    // Each Android update field, applied one after another by every test
    // below: iOS ignores all of them the same way.
    const payloads = [
      EventUpdateOptionsAndroid(status: EventStatusAndroid.canceled),
      EventUpdateOptionsAndroid(attendees: Patch.set([ada])),
      EventUpdateOptionsAndroid(attendees: Patch.clear()),
    ];

    testWidgets('createEvent ignores them', (tester) async {
      final baseline = await plugin.getEvent(await createOneOff());
      final id = await createOneOff(
        android: const EventOptionsAndroid(
          status: EventStatusAndroid.canceled,
          attendees: [ada, bob],
        ),
      );

      final event = await plugin.getEvent(id);
      expect(event, isNotNull);
      expect(
        event!.status,
        baseline!.status,
        reason: 'the same as passing no options',
      );
      expect(
        attendeesOf(event),
        attendeesOf(baseline),
        reason: 'the same as passing no options',
      );
    });

    testWidgets('updateEvent with only them changes nothing', (tester) async {
      final id = await createOneOff();
      final before = await plugin.getEvent(id);

      for (final android in payloads) {
        await plugin.updateEvent(instanceId: id, android: android);
      }

      expect(await plugin.getEvent(id), before);
    });

    testWidgets('updateEvent applies the other fields alongside them', (
      tester,
    ) async {
      final id = await createOneOff();
      final before = await plugin.getEvent(id);

      for (final (i, android) in payloads.indexed) {
        await plugin.updateEvent(
          instanceId: id,
          title: 'Renamed on iOS $i',
          android: android,
        );
      }

      final event = await plugin.getEvent(id);
      expect(event!.title, 'Renamed on iOS ${payloads.length - 1}');
      expect(event.status, before!.status);
      expect(attendeesOf(event), attendeesOf(before));
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

      for (final android in payloads) {
        await plugin.updateEvent(
          instanceId: series.occurrences[1].instanceId,
          android: android,
        );
      }

      expect(await seriesOccurrences(series), series.occurrences);
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

        for (final android in payloads) {
          final id = await plugin.updateRecurring(
            series.occurrences[2].instanceId,
            EventSpan.thisAndFollowing,
            android: android,
          );
          expect(id, series.eventId);
        }

        expect(await seriesOccurrences(series), series.occurrences);
      },
    );
  }, skip: !Platform.isIOS);
}
