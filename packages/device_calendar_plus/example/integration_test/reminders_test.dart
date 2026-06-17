import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Integration tests for relative event reminders (alarms).
///
/// These exercise the full create -> read -> update roundtrip on a real device
/// calendar. Reminders are minute-granular on both platforms, so the set read
/// back should match the minute values written, regardless of order.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final plugin = DeviceCalendar.instance;

  String? testCalendarId;

  setUpAll(() async {
    await plugin.requestPermissions();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    testCalendarId = await plugin.createCalendar(
      name: 'Reminder Test $timestamp',
    );
  });

  tearDownAll(() async {
    if (testCalendarId != null) {
      await plugin.deleteCalendar(testCalendarId!);
    }
  });

  /// Re-fetches the event and returns its reminders as a sorted minute set, so
  /// assertions don't depend on platform ordering.
  Future<Set<int>> reminderMinutes(String eventId) async {
    final event = await plugin.getEvent(eventId);
    final reminders = event?.reminders ?? const <Duration>[];
    return reminders.map((d) => d.inMinutes).toSet();
  }

  testWidgets('creates an event with reminders and reads them back',
      (tester) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 10, 0);
    final end = DateTime(now.year, now.month, now.day, 11, 0);

    final eventId = await plugin.createEvent(
      calendarId: testCalendarId!,
      title: 'Event with reminders',
      startDate: start,
      endDate: end,
      reminders: [const Duration(minutes: 15), const Duration(hours: 1)],
    );

    expect(await reminderMinutes(eventId), {15, 60});
  });

  testWidgets('creates an event without reminders (null reminders field)',
      (tester) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 12, 0);
    final end = DateTime(now.year, now.month, now.day, 13, 0);

    final eventId = await plugin.createEvent(
      calendarId: testCalendarId!,
      title: 'Event without reminders',
      startDate: start,
      endDate: end,
    );

    final event = await plugin.getEvent(eventId);
    expect(event?.reminders == null || event!.reminders!.isEmpty, isTrue);
  });

  testWidgets('updateEvent Patch.set replaces the whole reminder set',
      (tester) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 14, 0);
    final end = DateTime(now.year, now.month, now.day, 15, 0);

    final eventId = await plugin.createEvent(
      calendarId: testCalendarId!,
      title: 'Event to re-mind',
      startDate: start,
      endDate: end,
      reminders: [const Duration(minutes: 15), const Duration(hours: 1)],
    );

    await plugin.updateEvent(
      eventId: eventId,
      reminders: Patch.set([const Duration(minutes: 30)]),
    );

    expect(await reminderMinutes(eventId), {30});
  });

  testWidgets('updateEvent Patch.clear removes all reminders', (tester) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 16, 0);
    final end = DateTime(now.year, now.month, now.day, 17, 0);

    final eventId = await plugin.createEvent(
      calendarId: testCalendarId!,
      title: 'Event to clear',
      startDate: start,
      endDate: end,
      reminders: [const Duration(minutes: 10)],
    );

    await plugin.updateEvent(
      eventId: eventId,
      reminders: const Patch.clear(),
    );

    expect(await reminderMinutes(eventId), isEmpty);
  });
}
