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

    // A series the adapter has not uploaded yet has no `_sync_id`, and on a
    // synced calendar the plugin must not invent one. An exception inserted
    // against such a keyless master drops the master's occurrences from the
    // Instances cache until the adapter keys it — the whole series gone,
    // offline or with sync off (#163, the synced-calendar side of #153).
    // [detachedTitle] is the edited occurrence's title, or null for a delete.
    const editedTitle = 'Edited before upload #163';
    for (final (label, edit, detachedTitle) in [
      (
        'updateEvent',
        (DeviceCalendar plugin, SeededSeries series) => plugin.updateEvent(
            eventId: series.occurrences[4].instanceId, title: editedTitle),
        editedTitle,
      ),
      (
        'deleteEvent',
        (DeviceCalendar plugin, SeededSeries series) =>
            plugin.deleteEvent(eventId: series.occurrences[4].instanceId),
        null,
      ),
    ]) {
      test(
          '$label on one occurrence of a not-yet-uploaded series keeps the '
          'series listed, and the change shows once it is uploaded (#163)',
          () async {
        final series = await seedDailySeries(plugin, calendarId);
        expect((await readSyncIds(series.eventId))?.syncId, isNull,
            reason: 'the arrange must leave the master unkeyed, as before '
                'the adapter\'s first upload');

        await edit(plugin, series);

        // Until the upload the change is pending, not shown: the series
        // lists as it was, the changed slot included, and an edited
        // occurrence has no listing of its own yet.
        expect(
          startsOf(await occurrencesOf(
              plugin, calendarId!, series.eventId, series.start)),
          startsOf(series.occurrences),
          reason: 'the series must list as it was while the master awaits '
              'its first upload',
        );
        if (detachedTitle != null) {
          expect(
              await eventsTitled(
                  plugin, calendarId!, detachedTitle, series.start),
              isEmpty,
              reason: 'the edited occurrence must not be listed a second '
                  'time before the upload');
        }

        // The upload keys the master, the provider passes the key on to the
        // exception, and the series' next expansion pairs them.
        await markUploaded(series.eventId);
        await touchSeries(series.eventId);

        expect(
          startsOf(await occurrencesOf(
              plugin, calendarId!, series.eventId, series.start)),
          startsExcept(series.occurrences, {4}),
          reason: 'once uploaded, the series must skip the changed slot',
        );
        if (detachedTitle != null) {
          await expectDetachedOnce(plugin, calendarId!, detachedTitle,
              series.occurrences[4], series.start,
              reason: 'once uploaded, the edited occurrence must be listed '
                  'once, in its slot');
        }
      });
    }

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
        'updateRecurring(thisAndFollowing) carries a detached occurrence past '
        'the split to a fresh exception of the new series and tombstones the '
        'old one (#158)', () async {
      final series = await seedUploadedSeries(plugin, calendarId);
      final tag = DateTime.now().millisecondsSinceEpoch;
      final detachedTitle = 'Detached past update split #158 $tag';
      final exceptionId =
          await detachOccurrence(plugin, calendarId!, series, 5, detachedTitle);
      // The occurrence's own edits, each of which the copy must keep: the
      // plugin's writable fields, a color and a guest another app set.
      await plugin.updateEvent(
          eventId: exceptionId,
          description: Patch.set('Detached description $tag'),
          location: Patch.set('Detached location $tag'),
          availability: EventAvailability.free,
          reminders: Patch.set([const Duration(minutes: 20)]));
      await setEventColor(exceptionId, 0xFF00AA00);
      await addAttendee(exceptionId,
          email: 'guest-$tag@example.test', name: 'Detached guest');
      // Uploaded: its `_sync_id` is now the server's name for "occurrence 5
      // of the OLD series".
      await markUploaded(exceptionId);
      final newTitle = 'Synced tail #158 $tag';
      const shift = Duration(hours: 1);
      final newSlot = series.occurrences[5].startDate.add(shift);

      final newSeriesId = await plugin.updateRecurring(
          series.occurrences[3].instanceId, EventSpan.thisAndFollowing,
          title: newTitle, start: series.occurrences[3].startDate.add(shift));

      // Moving the uploaded row onto the new series does not change its
      // server identity: once the truncated old series is uploaded, the
      // server drops that instance as outside it and the adapter deletes
      // the row, edit and all (seen with Google's adapter on device).
      expect(await readSyncState(exceptionId), (deleted: true, dirty: true),
          reason: 'the old exception must be left as a tombstone for the '
              'adapter to upload, not moved onto the new series');
      final copyId = await exceptionIdOf(newSeriesId, newSlot);
      expect(copyId, isNotNull,
          reason: 'the occurrence must be written afresh as an exception of '
              'the new series, at its slot shifted with the split');
      expect(await readSyncIds(copyId!), (syncId: null, originalSyncId: null),
          reason: 'the copy must be new to the server, and the new series '
              'has no server key yet');
      expect(await readSyncState(copyId), (deleted: false, dirty: true),
          reason: 'the copy must be flagged for upload');
      final copy = await plugin.getEvent(copyId);
      expect(copy?.startDate, series.occurrences[5].startDate,
          reason: 'the copy must keep the occurrence\'s own time');
      expect(copy?.reminders, [const Duration(minutes: 20)],
          reason: 'the copy must keep the occurrence\'s own reminders');
      expect(copy?.description, 'Detached description $tag',
          reason: 'the copy must keep the occurrence\'s own description');
      expect(copy?.location, 'Detached location $tag',
          reason: 'the copy must keep the occurrence\'s own location');
      expect(copy?.availability, EventAvailability.free,
          reason: 'the copy must keep the occurrence\'s own availability');
      expect(copy?.colorHex, '#00AA00',
          reason: 'the copy must keep the occurrence\'s own color');
      expect(copy?.attendees?.map((a) => a.emailAddress),
          ['guest-$tag@example.test'],
          reason: 'the copy must keep the occurrence\'s own guests');

      // The provider pairs an exception with its slot by the master's server
      // key, which the new series gets only once its adapter uploads it, so
      // until then the pairing is pending. The upload keys the master, the
      // provider's own trigger passes the key on to the exception, and the
      // series' next expansion pairs them (see [touchSeries]).
      await markUploaded(newSeriesId);
      final newKey = (await readSyncIds(newSeriesId))!.syncId;
      expect((await readSyncIds(copyId))!.originalSyncId, newKey,
          reason: 'the copy must follow the new master\'s server key');
      await touchSeries(newSeriesId);

      expect(
        startsOf(await eventsTitled(
            plugin, calendarId!, newTitle, series.start)),
        startsExcept(series.occurrences, {0, 1, 2, 5})
            .map((s) => s + shift.inMilliseconds)
            .toList(),
        reason: 'the new series must skip the detached occurrence\'s slot',
      );
      await expectDetachedOnce(plugin, calendarId!, detachedTitle,
          series.occurrences[5], series.start,
          reason: 'the detached occurrence must survive the split');
    });

    test(
        'updateRecurring(thisAndFollowing) carries a deleted occurrence past '
        'the split to a cancelled exception of the new series and tombstones '
        'the old one (#158)', () async {
      // The split leaves the start where it is: a moved start brings a
      // deleted occurrence back, as on iOS, so nothing is carried then (see
      // recurrence_test.dart).
      final series = await seedUploadedSeries(plugin, calendarId);
      final tag = DateTime.now().millisecondsSinceEpoch;
      final slot = series.occurrences[5].startDate;
      await plugin.deleteEvent(eventId: series.occurrences[5].instanceId);
      final cancellationId = await exceptionIdOf(series.eventId, slot);
      expect(cancellationId, isNotNull,
          reason: 'the delete must be a cancelled exception row of the series');
      // Uploaded: its `_sync_id` is now the server's name for "occurrence 5
      // of the OLD series, cancelled".
      await markUploaded(cancellationId!);
      final newTitle = 'Synced tail past deleted #158 $tag';

      final newSeriesId = await plugin.updateRecurring(
          series.occurrences[3].instanceId, EventSpan.thisAndFollowing,
          title: newTitle);

      expect(await readSyncState(cancellationId), (deleted: true, dirty: true),
          reason: 'the old cancellation must be left as a tombstone for the '
              'adapter to upload');
      final copyId = await exceptionIdOf(newSeriesId, slot);
      expect(copyId, isNotNull,
          reason: 'the cancellation must be written afresh against the new '
              'series, at the same slot');
      expect(await readSyncState(copyId!), (deleted: false, dirty: true),
          reason: 'the copy must be flagged for upload');
      expect((await plugin.getEvent(copyId))?.status, EventStatus.canceled,
          reason: 'the copy must still cancel its slot');

      // As for a detached occurrence: the upload keys the new master, the
      // provider passes the key on to the copy, and the next expansion
      // pairs them.
      await markUploaded(newSeriesId);
      await touchSeries(newSeriesId);

      expect(
        startsOf(await eventsTitled(
            plugin, calendarId!, newTitle, series.start)),
        startsExcept(series.occurrences, {0, 1, 2, 5}),
        reason: 'the new series must keep the deleted slot deleted',
      );
    });
  }, skip: !Platform.isAndroid);
}
