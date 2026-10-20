import 'dart:io';

import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Integration tests for attendee reading.
///
/// On Android the plugin writes attendees (`EventOptionsAndroid.attendees`),
/// so platform_options_test.dart's 'Android attendee writes (#71)' group is
/// the deterministic read and write coverage there. iOS can't write
/// attendees, so the field-type check below scans the existing events and
/// skips when none has attendees; to run it fully, add attendees to an event
/// in the native Calendar app first. Its `Event.organizer` check works the
/// same way and passes without checking anything until an event has guests:
/// invite someone to an event in the native Calendar app (e.g. on the
/// physical iPhone) to run it.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final plugin = DeviceCalendar.instance;

  String? testCalendarId;

  setUpAll(() async {
    await plugin.requestPermissions();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    testCalendarId = await plugin.createCalendar(
      name: 'Attendee Test $timestamp',
    );
  });

  tearDownAll(() async {
    if (testCalendarId != null) {
      await plugin.deleteCalendar(testCalendarId!);
    }
  });

  testWidgets('Event without attendees has null attendees field',
      (tester) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 10, 0);
    final end = DateTime(now.year, now.month, now.day, 11, 0);

    final eventId = await plugin.createEvent(
      calendarId: testCalendarId!,
      title: 'No Attendees Event',
      startDate: start,
      endDate: end,
    );

    final events = await plugin.listEvents(
      start.subtract(Duration(hours: 1)),
      end.add(Duration(hours: 1)),
      calendarIds: [testCalendarId!],
    );

    final event = events.firstWhere((e) => e.eventId == eventId);
    // Event created without attendees should have null or empty attendees
    expect(event.attendees == null || event.attendees!.isEmpty, isTrue);
    // ...and no organizer, on both platforms (#236).
    expect(event.organizer, isNull);
  });

  testWidgets('Attendees have correct field types when present',
      (tester) async {
    // Fetch all events from all calendars — look for any with attendees
    final now = DateTime.now();
    final events = await plugin.listEvents(
      now.subtract(Duration(days: 30)),
      now.add(Duration(days: 30)),
    );

    final eventsWithAttendees =
        events.where((e) => e.attendees != null && e.attendees!.isNotEmpty);

    if (eventsWithAttendees.isEmpty) {
      // No events with attendees found — skip gracefully
      // To test fully, add attendees to an event via native calendar app
      return;
    }

    for (final event in eventsWithAttendees.take(3)) {
      for (final attendee in event.attendees!) {
        // Verify types are correct
        expect(attendee.role, isA<AttendeeRole>());
        expect(attendee.status, isA<AttendeeStatus>());
        // Name or email should be present (at least one)
        expect(
          attendee.name != null || attendee.emailAddress != null,
          isTrue,
          reason: 'Attendee should have at least a name or email: $attendee',
        );
      }
      // The organizer, when there is one, carries a name or an email too.
      final organizer = event.organizer;
      if (organizer != null) {
        expect(
          organizer.name != null || organizer.emailAddress != null,
          isTrue,
          reason: 'Organizer should have at least a name or email: $organizer',
        );
      }
    }
  }, skip: !Platform.isIOS);
}
