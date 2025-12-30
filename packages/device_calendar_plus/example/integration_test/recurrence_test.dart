import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Recurrence Integration Tests', () {
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
        // Verify we can use it (simulators sometimes return read-only defaults)
      }

      if (calendarId == null) {
        // Create a test calendar if none found
        try {
          calendarId = await plugin.createCalendar(
            name: 'Recurrence Test ${DateTime.now().millisecondsSinceEpoch}',
            colorHex: '#FF0000',
          );
        } catch (e) {
          print('Failed to create calendar: $e');
        }
      }
    });

    tearDownAll(() async {
      if (calendarId != null) {
        await plugin.deleteCalendar(calendarId!);
      }
    });

    testWidgets('1. Create Daily Recurring Event', (WidgetTester tester) async {
      if (calendarId == null) return;

      final startDate = DateTime.now();
      final endDate = startDate.add(const Duration(hours: 1));

      final recurrenceRule = RecurrenceRule(
        frequency: RecurrenceFrequency.daily,
        interval: 1,
        occurrences: 5,
      );

      final eventId = await plugin.createEvent(
        calendarId: calendarId!,
        title: 'Daily Event',
        startDate: startDate,
        endDate: endDate,
        isAllDay: false,
        recurrenceRule: recurrenceRule,
        timeZone: 'UTC',
      );

      expect(eventId, isNotNull);

      // Verify today
      final eventsToday = await plugin.listEvents(
        startDate.subtract(const Duration(hours: 1)),
        endDate.add(const Duration(hours: 1)),
        calendarIds: [calendarId!],
      );
      expect(eventsToday, isNotEmpty);
      expect(eventsToday.any((e) => e.eventId == eventId), isTrue);

      // Verify tomorrow
      final tomorrowStart = startDate.add(const Duration(days: 1));
      final tomorrowEnd = endDate.add(const Duration(days: 1));

      final eventsTomorrow = await plugin.listEvents(
        tomorrowStart.subtract(const Duration(hours: 1)),
        tomorrowEnd.add(const Duration(hours: 1)),
        calendarIds: [calendarId!],
      );

      expect(eventsTomorrow, isNotEmpty);
      expect(eventsTomorrow.any((e) => e.title == 'Daily Event'), isTrue);
    });

    testWidgets('2. Create Weekly Recurring Event',
        (WidgetTester tester) async {
      if (calendarId == null) return;

      final startDate = DateTime.now();
      final endDate = startDate.add(const Duration(hours: 1));

      final recurrenceRule = RecurrenceRule(
        frequency: RecurrenceFrequency.weekly,
        interval: 1,
      );

      final eventId = await plugin.createEvent(
        calendarId: calendarId!,
        title: 'Weekly Event',
        startDate: startDate,
        endDate: endDate,
        isAllDay: false,
        recurrenceRule: recurrenceRule,
        timeZone: 'UTC',
      );

      expect(eventId, isNotNull);

      // Verify next week
      final nextWeekStart = startDate.add(const Duration(days: 7));
      final nextWeekEnd = endDate.add(const Duration(days: 7));

      final eventsNextWeek = await plugin.listEvents(
        nextWeekStart.subtract(const Duration(hours: 1)),
        nextWeekEnd.add(const Duration(hours: 1)),
        calendarIds: [calendarId!],
      );

      expect(eventsNextWeek, isNotEmpty);
      expect(eventsNextWeek.any((e) => e.title == 'Weekly Event'), isTrue);
    });
  });
}
