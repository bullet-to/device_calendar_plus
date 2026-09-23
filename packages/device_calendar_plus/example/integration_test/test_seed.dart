import 'package:flutter/services.dart' show MethodChannel;

/// The example app's test-only seed channel (Android: `TestSeedChannel.kt`),
/// which writes calendar provider state the plugin deliberately can't —
/// sync-adapter-owned columns, another app's plain delete, an older
/// version's keyless exception. One wrapper per method, so the tests never
/// see the channel name, a stringly-typed method or an untyped map.
const _channel = MethodChannel('to.bullet.device_calendar_plus_example/test');

/// The provider's own sync keys for an event row: `_sync_id` and
/// `original_sync_id`, each null on an unkeyed row.
typedef SyncIds = ({String? syncId, String? originalSyncId});

/// Stamps [color] on [eventId]'s `EVENT_COLOR` as a sync adapter would, the
/// way an external app assigns a custom event color. Returns the rows
/// updated.
Future<int> setEventColor(String eventId, int color) async =>
    (await _channel.invokeMethod<int>(
        'setEventColor', {'eventId': eventId, 'color': color}))!;

/// A plain (non-sync-adapter) delete of [eventId], the kind another app
/// issues: an event with a `_sync_id` is tombstoned (DELETED=1) rather than
/// removed. Returns the rows the provider reports touched.
Future<int> deleteEventPlain(String eventId) async =>
    (await _channel.invokeMethod<int>('deleteEventPlain', {'eventId': eventId}))!;

/// The write an older plugin version made for a per-occurrence edit: a
/// plain exception insert against a master with no `_sync_id`, leaving
/// #153's on-disk state. Returns the exception's event ID.
Future<String> insertKeylessException({
  required String eventId,
  required DateTime instanceStart,
  required DateTime instanceEnd,
  required String title,
}) async =>
    (await _channel.invokeMethod<String>('insertKeylessException', {
      'eventId': eventId,
      'instanceStart': instanceStart.millisecondsSinceEpoch,
      'instanceEnd': instanceEnd.millisecondsSinceEpoch,
      'title': title,
    }))!;

/// Reads [eventId]'s sync keys straight from the Events table, or null when
/// the row is missing.
Future<SyncIds?> readSyncIds(String eventId) async {
  final row = await _channel
      .invokeMethod<Map<Object?, Object?>>('readSyncIds', {'eventId': eventId});
  if (row == null) return null;
  return (
    syncId: row['syncId'] as String?,
    originalSyncId: row['originalSyncId'] as String?,
  );
}
