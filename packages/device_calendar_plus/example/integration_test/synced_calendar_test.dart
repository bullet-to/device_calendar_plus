import 'dart:io' show Platform;

import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'series_fixtures.dart';
import 'test_helpers.dart';
import 'test_seed.dart';

/// The arrange step the synced-calendar tests share: a daily series with its
/// master in the adapter's "uploaded" state (see [markUploaded]). A row with
/// no `_sync_id` is removed outright by any caller and starts out DIRTY, so
/// only an uploaded row shows whether a write left the adapter something to
/// upload — a DELETED=1 tombstone or a fresh DIRTY=1.
Future<SeededSeries> seedUploadedSeries(
    DeviceCalendar plugin, String? calendarId) async {
  final series = await seedDailySeries(plugin, calendarId);
  await markUploaded(series.eventId);
  return series;
}

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
  // seeds its own event in the adapter's "uploaded" state (see
  // [seedUploadedSeries]).
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

    test('deleteEvent leaves a tombstone for the adapter to upload',
        () async {
      final start = DateTime.now().add(const Duration(hours: 1));
      final eventId = await plugin.createEvent(
        calendarId: calendarId!,
        title: 'Synced delete #132',
        startDate: start,
        endDate: start.add(const Duration(hours: 1)),
      );
      await markUploaded(eventId);

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

    test(
        'a repeat deleteEvent reports notFound while the tombstone awaits '
        'the adapter, as on iOS', () async {
      final start = DateTime.now().add(const Duration(hours: 1));
      final eventId = await plugin.createEvent(
        calendarId: calendarId!,
        title: 'Synced repeat delete #132',
        startDate: start,
        endDate: start.add(const Duration(hours: 1)),
      );
      await markUploaded(eventId);
      await plugin.deleteEvent(eventId: eventId);

      await expectLater(plugin.deleteEvent(eventId: eventId), throwsNotFound,
          reason: 'the event is already deleted as far as the caller can '
              'tell: getEvent reads it as gone, so deleteEvent must agree');
      expect(await readSyncState(eventId), (deleted: true, dirty: true),
          reason: 'the refused repeat must leave the tombstone for upload');
    });

    test('deleteEvent on one occurrence writes a dirty cancellation (#161)',
        () async {
      final series = await seedUploadedSeries(plugin, calendarId);
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
      final series = await seedUploadedSeries(plugin, calendarId);

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
        'deleteRecurring(thisAndFollowing) truncates the master as a plain '
        'caller and tombstones a detached occurrence past the split',
        () async {
      final series = await seedUploadedSeries(plugin, calendarId);
      final detachedTitle =
          'Detached past split #132 ${DateTime.now().millisecondsSinceEpoch}';
      final exceptionId =
          await detachOccurrence(plugin, calendarId!, series, 5, detachedTitle);
      // The exception uploaded so the delete tombstones rather than removes
      // it; the master again so that a DIRTY=1 on it afterwards is the
      // truncation's alone, not the detach's.
      await markUploaded(exceptionId);
      await markUploaded(series.eventId);

      await plugin.deleteRecurring(
          series.occurrences[3].instanceId, EventSpan.thisAndFollowing);

      // The truncation is a plain RRULE write on a synced calendar — the
      // premise the fix rests on is that the provider keeps it.
      expectMasterSplit(
        await occurrencesOf(plugin, calendarId!, series.eventId, series.start),
        before: series.occurrences[3].startDate,
        keeps: [
          series.occurrences[0].startDate,
          series.occurrences[1].startDate,
          series.occurrences[2].startDate,
        ],
      );
      expect(await readSyncState(series.eventId), (deleted: false, dirty: true),
          reason: 'the truncated master must be flagged for upload');
      expect(
        await eventsTitled(plugin, calendarId!, detachedTitle, series.start),
        isEmpty,
        reason: 'the detached occurrence must be gone from the listing',
      );
      expect(await readSyncState(exceptionId), (deleted: true, dirty: true),
          reason: 'the detached occurrence must survive as a tombstone for '
              'the adapter to upload, not be removed outright');
    });

    test(
        'updateRecurring(thisAndFollowing) truncates the master as a plain '
        'caller and marks it dirty for upload', () async {
      final series = await seedUploadedSeries(plugin, calendarId);
      const newTitle = 'Renamed synced tail #132';

      final newSeriesId = await plugin.updateRecurring(
          series.occurrences[3].instanceId, EventSpan.thisAndFollowing,
          title: newTitle);

      expectMasterSplit(
        await occurrencesOf(plugin, calendarId!, series.eventId, series.start),
        before: series.occurrences[3].startDate,
        keeps: [
          series.occurrences[0].startDate,
          series.occurrences[1].startDate,
          series.occurrences[2].startDate,
        ],
      );
      expect(await readSyncState(series.eventId), (deleted: false, dirty: true),
          reason: 'the truncated master must be flagged for upload: written '
              'as the sync adapter it never reaches the server');
      expect(
        startsOf(
            await occurrencesOf(plugin, calendarId!, newSeriesId, series.start)),
        startsOf(series.occurrences.skip(3)),
        reason: 'the new series must carry the occurrences from the split on',
      );
    });

    test(
        'updateRecurring(thisAndFollowing) re-parents a detached occurrence '
        'past the split onto the unsynced new series (#158)', () async {
      final series = await seedUploadedSeries(plugin, calendarId);
      final tag = DateTime.now().millisecondsSinceEpoch;
      final detachedTitle = 'Detached past update split #158 $tag';
      final exceptionId =
          await detachOccurrence(plugin, calendarId!, series, 5, detachedTitle);
      // Uploaded, so a DIRTY=1 afterwards is the re-parenting's alone.
      await markUploaded(exceptionId);
      final newTitle = 'Synced tail #158 $tag';

      final newSeriesId = await plugin.updateRecurring(
          series.occurrences[3].instanceId, EventSpan.thisAndFollowing,
          title: newTitle);

      expect(await readSyncState(exceptionId), (deleted: false, dirty: true),
          reason: 'the re-parented exception must be flagged for upload');
      expect((await readSyncIds(exceptionId))!.originalSyncId, isNull,
          reason: 'the exception must not stay keyed to the old series, and '
              'the new one has no server key yet');

      // The provider pairs an exception with its slot by the master's server
      // key, which the new series gets only once its adapter uploads it, so
      // until then the pairing is pending. The upload keys the master, the
      // provider's own trigger passes the key on to the exception, and the
      // series' next expansion pairs them. (The adapter's own writes bring
      // that expansion; here a no-change rewrite of the series stands in.)
      await markUploaded(newSeriesId);
      final newKey = (await readSyncIds(newSeriesId))!.syncId;
      expect((await readSyncIds(exceptionId))!.originalSyncId, newKey,
          reason: 'the exception must follow the new master\'s server key');
      await plugin.updateRecurring(newSeriesId, EventSpan.allEvents,
          start: series.occurrences[3].startDate);

      expect(
        startsOf(await eventsTitled(
            plugin, calendarId!, newTitle, series.start)),
        startsExcept(series.occurrences, {0, 1, 2, 5}),
        reason: 'the new series must skip the detached occurrence\'s slot',
      );
      await expectDetachedOnce(plugin, calendarId!, detachedTitle,
          series.occurrences[5], series.start,
          reason: 'the detached occurrence must survive the split');
    });
  }, skip: !Platform.isAndroid);
}
