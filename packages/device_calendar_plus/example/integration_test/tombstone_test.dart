import 'dart:io' show Platform;

import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'series_fixtures.dart';
import 'test_helpers.dart';
import 'test_seed.dart';

/// The arrange step the tombstone tests share, Android-only (#153): a daily
/// series keyed by editing one occurrence through the plugin, then deleted
/// by another app — the example app's seed channel issues a plain
/// (non-sync-adapter) delete of the master.
///
/// A plain delete of an event with a `_sync_id` — which a local series
/// carries once an occurrence has been edited (#153) — leaves the provider
/// a DELETED=1 tombstone rather than removing the row, and tombstones its
/// exceptions along with it. Instances queries skip it, so every read path
/// the plugin keys off the Events table must skip it too, and the plugin's
/// own delete (a sync adapter's) must still collect it.
///
/// Returns the series (its occurrences as listed before the tombstone), the
/// title the edited occurrence was detached under, and the exception row's
/// own event ID.
Future<({SeededSeries series, String detachedTitle, String exceptionId})>
    tombstoneSeries(DeviceCalendar plugin, String? calendarId) async {
  final series = await seedDailySeries(plugin, calendarId);
  final detachedTitle =
      'Detached before tombstone #153 ${DateTime.now().millisecondsSinceEpoch}';

  // Key the master: edit one occurrence through the plugin.
  final exceptionId =
      await detachOccurrence(plugin, calendarId!, series, 4, detachedTitle);

  final deleted = await deleteEventPlain(series.eventId);
  expect(deleted, 1, reason: 'the seed must find the master to delete');

  return (
    series: series,
    detachedTitle: detachedTitle,
    exceptionId: exceptionId,
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // A plain (non-sync-adapter) delete of a keyed series leaves the provider
  // a DELETED=1 tombstone rather than removing the row (#153). Instances
  // queries skip it, so every plugin path keyed off the Events table must
  // read it as gone — and the plugin's own delete must still collect it.
  // Android-only: iOS has no tombstones, so the group is skipped there
  // as one. Each test tombstones its own series through
  // [tombstoneSeries].
  group('Tombstoned series (#153)', () {
    late DeviceCalendar plugin;
    String? calendarId;

    setUpAll(() async {
      plugin = DeviceCalendar.instance;
      await plugin.requestPermissions();

      calendarId = await plugin.createCalendar(
        name: 'Tombstone Test ${DateTime.now().millisecondsSinceEpoch}',
        colorHex: '#FF00FF',
      );
    });

    tearDownAll(() async {
      if (calendarId != null) {
        await plugin.deleteCalendar(calendarId!);
      }
    });

    test('getEvent and listEvents read a tombstoned series as gone (#153)',
        () async {
      final t = await tombstoneSeries(plugin, calendarId);

      expect(await plugin.getEvent(t.series.eventId), isNull,
          reason: 'getEvent must not read a tombstone');
      expect(
        await occurrencesOf(
            plugin, calendarId!, t.series.eventId, t.series.start),
        isEmpty,
        reason: 'the tombstoned series must have no occurrences listed',
      );
      // The plain delete tombstones the exceptions along with the master,
      // so the detached occurrence drops out of the listing too.
      expect(
        await eventsTitled(
            plugin, calendarId!, t.detachedTitle, t.series.start),
        isEmpty,
        reason: 'the tombstoned series must list no detached occurrence',
      );
    });

    test(
        'updateEvent reports notFound on a tombstone, bare and instance ID '
        '(#153)', () async {
      final t = await tombstoneSeries(plugin, calendarId);

      await expectLater(
        plugin.updateEvent(eventId: t.series.eventId, title: 'Tombstone edit'),
        throwsNotFound,
        reason: 'updateEvent must not edit a tombstone',
      );
      await expectLater(
        plugin.updateEvent(
            eventId: t.series.occurrences[2].instanceId,
            title: 'Tombstone edit'),
        throwsNotFound,
        reason: 'updateEvent must not write an exception against a tombstone',
      );
    });

    test('updateRecurring reports notFound on a tombstone, both spans (#153)',
        () async {
      final t = await tombstoneSeries(plugin, calendarId);

      await expectLater(
        plugin.updateRecurring(t.series.eventId, EventSpan.allEvents,
            title: 'Tombstone edit'),
        throwsNotFound,
        reason: 'updateRecurring(allEvents) must not edit a tombstone',
      );
      await expectLater(
        plugin.updateRecurring(
            t.series.occurrences[2].instanceId, EventSpan.thisAndFollowing,
            title: 'Tombstone edit'),
        throwsNotFound,
        reason: 'updateRecurring(thisAndFollowing) must not split a tombstone',
      );
    });

    test(
        'deleteEvent and deleteRecurring on an occurrence of a tombstone '
        'report notFound (#153)', () async {
      final t = await tombstoneSeries(plugin, calendarId);

      await expectLater(
        plugin.deleteEvent(eventId: t.series.occurrences[2].instanceId),
        throwsNotFound,
        reason: 'deleteEvent must not cancel an occurrence of a tombstone',
      );
      await expectLater(
        plugin.deleteRecurring(
            t.series.occurrences[2].instanceId, EventSpan.thisAndFollowing),
        throwsNotFound,
        reason: 'deleteRecurring(thisAndFollowing) must not truncate a '
            'tombstone',
      );
    });

    test(
        'deleteEvent on the series ID collects the tombstone and its '
        'exception (#153)', () async {
      final t = await tombstoneSeries(plugin, calendarId);

      // The plugin deletes as a sync adapter, which is what collects it;
      // its `_ID = ? OR ORIGINAL_ID = ?` selection takes the tombstoned
      // exception along with the master. The seed's read of the Events row
      // does not filter DELETED=1, so a null there is the row physically
      // gone, not merely tombstoned.
      await plugin.deleteEvent(eventId: t.series.eventId);
      expect(
        await readSyncIds(t.series.eventId),
        isNull,
        reason: 'the tombstone must be physically gone after deleteEvent',
      );
      expect(
        await readSyncIds(t.exceptionId),
        isNull,
        reason: 'the tombstoned exception must be physically gone once the '
            'plugin has collected the series',
      );
    });
  }, skip: !Platform.isAndroid);
}
