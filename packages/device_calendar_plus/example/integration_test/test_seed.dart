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

/// What a sync adapter would find to upload for an event row: its `DELETED`
/// and `DIRTY` flags.
typedef SyncState = ({bool deleted, bool dirty});

/// A calendar a sync adapter owns, stood up for a test: inserted as that
/// adapter would, under an account of the example app's own type that no
/// adapter answers to (the emulator has no synced account, and a real
/// device's Google account must not receive test rows). Any account type but
/// local is "synced" to the provider, which is all its sync-adapter branches
/// turn on (#132). Registers the account first. Returns the calendar's ID;
/// the plugin's own `deleteCalendar` removes it, and [removeSyncedAccount]
/// the account.
Future<String> createSyncedCalendar(String name) async =>
    (await _channel.invokeMethod<String>('createSyncedCalendar', {'name': name}))!;

/// Removes the account [createSyncedCalendar] registered, and through the
/// provider's own account cleanup any calendar still under it. Returns
/// whether there was one to remove.
Future<bool> removeSyncedAccount() async =>
    (await _channel.invokeMethod<bool>('removeSyncedAccount'))!;

/// Puts [eventId] in the state a sync adapter leaves an event in once the
/// server has it: a `_sync_id` and `DIRTY` cleared. From here a plain write
/// is what the adapter uploads next, and a sync-adapter write is one the
/// server never hears of (#132). Returns the rows updated.
Future<int> markUploaded(String eventId) async =>
    (await _channel.invokeMethod<int>('markUploaded', {'eventId': eventId}))!;

/// Reads [eventId]'s `DELETED` and `DIRTY` flags straight from the Events
/// table — which, unlike the plugin's reads, still lists a tombstone — or
/// null when the row is gone altogether.
Future<SyncState?> readSyncState(String eventId) async {
  final row = await _channel.invokeMethod<Map<Object?, Object?>>(
      'readSyncState', {'eventId': eventId});
  if (row == null) return null;
  return (deleted: row['deleted'] as bool, dirty: row['dirty'] as bool);
}

/// The event ID of the exception row written against master [eventId] for
/// the occurrence at [instanceStart], or null when there is none. The plugin
/// returns no ID for a cancelled occurrence, so its row is found by the slot
/// it replaced.
Future<String?> exceptionIdOf(String eventId, DateTime instanceStart) =>
    _channel.invokeMethod<String>('exceptionIdOf', {
      'eventId': eventId,
      'instanceStart': instanceStart.millisecondsSinceEpoch,
    });

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
