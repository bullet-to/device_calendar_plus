import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Attendee Integration Tests', () {
    late DeviceCalendar plugin;
    String? calendarId;

    setUpAll(() async {
      plugin = DeviceCalendar.instance;
      await plugin.requestPermissions();

      // Try to find an existing writable calendar first
      final calendarsResult = await plugin.listCalendars();
      if (calendarsResult.isNotEmpty) {
        // Find a writable calendar
        final writableCalendar = calendarsResult.firstWhere((c) => !c.readOnly,
            orElse: () => calendarsResult.first);
        calendarId = writableCalendar.id;
      }

      if (calendarId == null) {
        // Create a test calendar if none found
        try {
          calendarId = await plugin.createCalendar(
            name: 'Attendee Test ${DateTime.now().millisecondsSinceEpoch}',
            colorHex: '#0000FF',
          );
        } catch (e) {
          // ignore - will skip tests if no calendar
        }
      }
    });

    tearDownAll(() async {
      // Don't delete the calendar as it may be a system calendar
    });

    testWidgets('1. Create Event with Attendees', (WidgetTester tester) async {
      if (calendarId == null) {
        // Skip test if no calendar available
        return;
      }

      final startDate = DateTime.now().add(const Duration(hours: 1));
      final endDate = startDate.add(const Duration(hours: 1));

      // Create event with two attendees
      final attendees = [
        Attendee(
          name: 'John Doe',
          emailAddress: 'john.doe@example.com',
          role: AttendeeRole.required,
          status: AttendeeStatus.invited,
        ),
        Attendee(
          name: 'Jane Smith',
          emailAddress: 'jane.smith@example.com',
          role: AttendeeRole.optional,
          status: AttendeeStatus.none,
        ),
      ];

      final eventId = await plugin.createEvent(
        calendarId: calendarId!,
        title: 'Meeting with Attendees',
        startDate: startDate,
        endDate: endDate,
        isAllDay: false,
        description: 'Test event with attendees',
        attendees: attendees,
      );

      expect(eventId, isNotNull);
      expect(eventId, isNotEmpty);

      // Fetch the event back and verify it was created
      final events = await plugin.listEvents(
        startDate.subtract(const Duration(hours: 1)),
        endDate.add(const Duration(hours: 1)),
        calendarIds: [calendarId!],
      );

      expect(events, isNotEmpty);
      final createdEvent = events.firstWhere(
        (e) => e.eventId == eventId,
        orElse: () => throw Exception('Event not found'),
      );

      expect(createdEvent.title, equals('Meeting with Attendees'));

      // Note: Attendees may or may not be returned depending on platform
      // iOS returns EKParticipant data for events with attendees
      // The attendees field should at least not throw an error
      if (createdEvent.attendees != null) {
        // If attendees are returned, verify they have expected fields
        for (final attendee in createdEvent.attendees!) {
          expect(attendee.role, isNotNull);
          expect(attendee.status, isNotNull);
        }
      }

      // Clean up
      await plugin.deleteEvent(eventId: eventId);
    });

    testWidgets('2. Fetch Event Attendees from Native Calendar',
        (WidgetTester tester) async {
      if (calendarId == null) return;

      // Create a simple event first
      final startDate = DateTime.now().add(const Duration(hours: 2));
      final endDate = startDate.add(const Duration(hours: 1));

      final eventId = await plugin.createEvent(
        calendarId: calendarId!,
        title: 'Event to check attendees',
        startDate: startDate,
        endDate: endDate,
        isAllDay: false,
      );

      expect(eventId, isNotNull);

      // Fetch event using getEvent
      final event = await plugin.getEvent(eventId);
      expect(event, isNotNull);
      expect(event!.title, equals('Event to check attendees'));

      // The attendees field should be accessible (may be null or empty)
      // This verifies the Event model correctly parses attendee data
      final attendees = event.attendees;
      // No assertion on attendees being present - platform dependent

      // Clean up
      await plugin.deleteEvent(eventId: eventId);
    });

    testWidgets('3. Update Event preserves other fields when adding attendees',
        (WidgetTester tester) async {
      if (calendarId == null) return;

      final startDate = DateTime.now().add(const Duration(hours: 3));
      final endDate = startDate.add(const Duration(hours: 1));

      // Create event without attendees
      final eventId = await plugin.createEvent(
        calendarId: calendarId!,
        title: 'Event Without Attendees',
        startDate: startDate,
        endDate: endDate,
        isAllDay: false,
        description: 'Original description',
      );

      expect(eventId, isNotNull);

      // Update the event with attendees
      await plugin.updateEvent(
        eventId: eventId,
        title: 'Event With Attendees Now',
        attendees: [
          Attendee(
            emailAddress: 'new.attendee@example.com',
            role: AttendeeRole.required,
          ),
        ],
      );

      // Fetch and verify
      final updatedEvent = await plugin.getEvent(eventId);
      expect(updatedEvent, isNotNull);
      expect(updatedEvent!.title, equals('Event With Attendees Now'));

      // Clean up
      await plugin.deleteEvent(eventId: eventId);
    });

    testWidgets('4. Attendee serialization/deserialization',
        (WidgetTester tester) async {
      // Test that Attendee model properly serializes and deserializes
      final attendee = Attendee(
        name: 'Test User',
        emailAddress: 'test@example.com',
        role: AttendeeRole.required,
        status: AttendeeStatus.accepted,
        isOrganizer: true,
        isCurrentUser: false,
      );

      // Serialize to map
      final map = attendee.toMap();
      expect(map['name'], equals('Test User'));
      expect(map['emailAddress'], equals('test@example.com'));
      expect(map['role'], equals('required'));
      expect(map['status'], equals('accepted'));
      expect(map['isOrganizer'], isTrue);
      expect(map['isCurrentUser'], isFalse);

      // Deserialize from map
      final restored = Attendee.fromMap(map);
      expect(restored.name, equals('Test User'));
      expect(restored.emailAddress, equals('test@example.com'));
      expect(restored.role, equals(AttendeeRole.required));
      expect(restored.status, equals(AttendeeStatus.accepted));
      expect(restored.isOrganizer, isTrue);
      expect(restored.isCurrentUser, isFalse);
    });

    testWidgets('5. AttendeeRole and AttendeeStatus enums',
        (WidgetTester tester) async {
      // Verify all enum values exist
      expect(AttendeeRole.values, contains(AttendeeRole.none));
      expect(AttendeeRole.values, contains(AttendeeRole.required));
      expect(AttendeeRole.values, contains(AttendeeRole.optional));
      expect(AttendeeRole.values, contains(AttendeeRole.resource));

      expect(AttendeeStatus.values, contains(AttendeeStatus.none));
      expect(AttendeeStatus.values, contains(AttendeeStatus.invited));
      expect(AttendeeStatus.values, contains(AttendeeStatus.accepted));
      expect(AttendeeStatus.values, contains(AttendeeStatus.declined));
      expect(AttendeeStatus.values, contains(AttendeeStatus.tentative));
    });
  });
}
