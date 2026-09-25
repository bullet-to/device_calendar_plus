import 'dart:io' show Platform;

import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'series_fixtures.dart';
import 'test_seed.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // On a calendar a sync adapter owns, the provider tells the server about a
  // write only when a plain caller makes it: an edit marks the row DIRTY=1
  // and a delete leaves a DELETED=1, DIRTY=1 tombstone for the adapter to
  // upload and then collect. A write made *as* the sync adapter skips all of
  // that — the row is changed or removed locally and the server never hears
  // of it, so the next sync brings the event back (#132). Android-only:
  // iOS has no such distinction, so the group is skipped there as one. The
  // calendar is a faked synced one (see [createSyncedCalendar]); each test
  // seeds its own event and puts it in the adapter's "uploaded" state first,
  // since a row with no `_sync_id` is removed outright by any caller.
  group('Writes to a synced calendar (#132)', () {
    late DeviceCalendar plugin;
    String? calendarId;

    setUpAll(() async {
      plugin = DeviceCalendar.instance;
      await plugin.requestPermissions();

      calendarId = await createSyncedCalendar(
          'Synced Test ${DateTime.now().millisecondsSinceEpoch}');
    });

    tearDownAll(() async {
      if (calendarId != null) {
        await plugin.deleteCalendar(calendarId!);
      }
      await removeSyncedAccount();
    });

    test('deleteEvent leaves a tombstone for the adapter to upload', () async {
      final start = DateTime.now().add(const Duration(hours: 1));
      final eventId = await plugin.createEvent(
        calendarId: calendarId!,
        title: 'Synced delete #132',
        startDate: start,
        endDate: start.add(const Duration(hours: 1)),
      );
      expect(await markUploaded(eventId), 1,
          reason: 'the seed must find the event to mark uploaded');

      await plugin.deleteEvent(eventId: eventId);

      expect(await plugin.getEvent(eventId), isNull,
          reason: 'the deleted event must read as gone');
      final state = await readSyncState(eventId);
      expect(state, isNotNull,
          reason: 'the row must survive as a tombstone: removing it outright '
              'leaves the adapter nothing to tell the server, and the next '
              'sync brings the event back');
      expect(state, (deleted: true, dirty: true),
          reason: 'the tombstone must be flagged for upload');
    });

    test('deleteEvent on one occurrence writes a dirty cancellation (#161)',
        () async {
      final series = await seedDailySeries(plugin, calendarId);
      expect(await markUploaded(series.eventId), 1,
          reason: 'the seed must find the series to mark uploaded');
      final occurrence = series.occurrences[3];

      await plugin.deleteEvent(eventId: occurrence.instanceId);

      expect(
        startsOf(await occurrencesOf(
            plugin, calendarId!, series.eventId, series.start)),
        startsExcept(series.occurrences, {3}),
        reason: 'the occurrence must be gone from the listing',
      );
      final exceptionId =
          await exceptionIdOf(series.eventId, occurrence.startDate);
      expect(exceptionId, isNotNull,
          reason: 'the cancellation must be an exception row of the series');
      expect(await readSyncState(exceptionId!), (deleted: false, dirty: true),
          reason: 'the cancellation must be flagged for upload: written as '
              'the sync adapter it is never uploaded, and the next sync '
              'brings the occurrence back');
    });

    test('updateRecurring(allEvents) marks the series dirty for upload',
        () async {
      final series = await seedDailySeries(plugin, calendarId);
      expect(await markUploaded(series.eventId), 1,
          reason: 'the seed must find the series to mark uploaded');

      await plugin.updateRecurring(series.eventId, EventSpan.allEvents,
          title: 'Renamed synced series #132');

      expect((await plugin.getEvent(series.eventId))?.title,
          'Renamed synced series #132',
          reason: 'the rename must apply locally');
      expect(await readSyncState(series.eventId), (deleted: false, dirty: true),
          reason: 'the edit must be flagged for upload: written as the sync '
              'adapter it never reaches the server');
    });

    test(
        'deleteRecurring(thisAndFollowing) tombstones a detached occurrence '
        'past the split', () async {
      final series = await seedDailySeries(plugin, calendarId);
      final detachedTitle =
          'Detached past split #132 ${DateTime.now().millisecondsSinceEpoch}';
      final exceptionId =
          await detachOccurrence(plugin, calendarId!, series, 5, detachedTitle);
      expect(await markUploaded(exceptionId), 1,
          reason: 'the seed must find the detached occurrence to mark uploaded');

      await plugin.deleteRecurring(
          series.occurrences[3].instanceId, EventSpan.thisAndFollowing);

      expect(
        await eventsTitled(plugin, calendarId!, detachedTitle, series.start),
        isEmpty,
        reason: 'the detached occurrence must be gone from the listing',
      );
      expect(await readSyncState(exceptionId), (deleted: true, dirty: true),
          reason: 'the detached occurrence must survive as a tombstone for '
              'the adapter to upload, not be removed outright');
    });
  }, skip: !Platform.isAndroid);
}
