// Platform-only options.
//
// Each class here carries fields only one platform can act on. They are
// passed through a method's `android:` or `ios:` parameter, apply only on
// that platform and are silently ignored on the other, so shared code can
// pass both.
//
// Fields expose their own platform's semantics and value sets directly. They
// are not mapped, normalised or reconciled with similar fields on the other
// platform: if the other platform later gets a similar feature, it gets its
// own type with its own semantics.
//
// Every options class is immutable, with optional named fields and value
// equality, so adding a field later is not a breaking change. The values they
// carry (such as AttendeeWriteAndroid) are immutable with value equality too.

import 'package:flutter/foundation.dart' show listEquals;

import 'patch.dart';

/// An Android event's `STATUS` column, as `CalendarContract.Events` defines
/// it: `STATUS_TENTATIVE`, `STATUS_CONFIRMED` and `STATUS_CANCELED`.
///
/// Android's own value set, not the shared `EventStatus`: it is written
/// straight to the column, with Android's semantics.
enum EventStatusAndroid {
  /// `CalendarContract.Events.STATUS_TENTATIVE`.
  tentative,

  /// `CalendarContract.Events.STATUS_CONFIRMED`.
  confirmed,

  /// `CalendarContract.Events.STATUS_CANCELED`.
  ///
  /// The Calendar Provider expands no occurrences for a cancelled series and
  /// reads a cancelled occurrence as a deleted one. So on a recurring event
  /// (`createEvent` with a rule, `updateRecurring`) its occurrences drop out
  /// of `listEvents`, leaving only occurrences edited on their own; on one
  /// occurrence (`updateEvent` with an instance ID) that occurrence drops
  /// out, as `deleteEvent` would remove it. A cancelled one-off event is
  /// still listed, and `getEvent` still finds a cancelled series by its ID.
  canceled,
}

/// An Android attendee's `ATTENDEE_TYPE`, as `CalendarContract.Attendees`
/// defines it.
///
/// Android's own value set, not the shared `AttendeeRole`: it is written
/// straight to the column, with Android's semantics.
enum AttendeeTypeAndroid {
  /// `CalendarContract.Attendees.TYPE_NONE`.
  none,

  /// `CalendarContract.Attendees.TYPE_REQUIRED`.
  required,

  /// `CalendarContract.Attendees.TYPE_OPTIONAL`.
  optional,

  /// `CalendarContract.Attendees.TYPE_RESOURCE`: a room or piece of
  /// equipment rather than a person.
  resource,
}

/// An Android attendee's `ATTENDEE_RELATIONSHIP`, as
/// `CalendarContract.Attendees` defines it.
///
/// Android's own value set, written straight to the column.
enum AttendeeRelationshipAndroid {
  /// `CalendarContract.Attendees.RELATIONSHIP_NONE`.
  none,

  /// `CalendarContract.Attendees.RELATIONSHIP_ATTENDEE`.
  attendee,

  /// `CalendarContract.Attendees.RELATIONSHIP_ORGANIZER`.
  ///
  /// The provider takes an organizer row's email as the event's
  /// `ORGANIZER`. The shared `Event.attendees` skips organizer rows, so an
  /// attendee written with this relationship isn't read back there.
  organizer,

  /// `CalendarContract.Attendees.RELATIONSHIP_PERFORMER`.
  performer,

  /// `CalendarContract.Attendees.RELATIONSHIP_SPEAKER`.
  speaker,
}

/// An Android attendee's `ATTENDEE_STATUS`, as `CalendarContract.Attendees`
/// defines it.
///
/// Android's own value set, not the shared `AttendeeStatus`: it is written
/// straight to the column, with Android's semantics.
enum AttendeeStatusAndroid {
  /// `CalendarContract.Attendees.ATTENDEE_STATUS_NONE`.
  none,

  /// `CalendarContract.Attendees.ATTENDEE_STATUS_ACCEPTED`.
  accepted,

  /// `CalendarContract.Attendees.ATTENDEE_STATUS_DECLINED`.
  declined,

  /// `CalendarContract.Attendees.ATTENDEE_STATUS_INVITED`.
  invited,

  /// `CalendarContract.Attendees.ATTENDEE_STATUS_TENTATIVE`.
  tentative,
}

/// One `CalendarContract.Attendees` row to write, Android only.
///
/// Write-only: an event's attendees are read back as the shared `Attendee`
/// through `Event.attendees`, on both platforms, with the shared role and
/// status values rather than these columns.
///
/// iOS EventKit can't add attendees to an event, so attendees are written
/// only through [EventOptionsAndroid.attendees] and
/// [EventUpdateOptionsAndroid.attendees]. Each field is the Attendees
/// column of the same name, with Android's own semantics.
///
/// **Synced calendars send real invitations.** On a Google or Exchange
/// calendar the account's sync adapter uploads these rows, and the server
/// may email an invitation (or a cancellation, when a row is removed) to
/// every [email]. It may also rewrite the rows on the next sync: fill in a
/// [name], change a [status] as people respond, or drop an address it
/// can't resolve. On a local calendar the rows stay as written and nobody
/// is contacted.
class AttendeeWriteAndroid {
  /// Creates an attendee row to write.
  const AttendeeWriteAndroid({
    required this.email,
    this.name,
    this.type = AttendeeTypeAndroid.required,
    this.relationship = AttendeeRelationshipAndroid.attendee,
    this.status = AttendeeStatusAndroid.invited,
  });

  /// The attendee's `ATTENDEE_EMAIL`. Must not be blank.
  ///
  /// On a synced calendar the server may email an invitation to it.
  final String email;

  /// The attendee's `ATTENDEE_NAME`, or `null` to write none. A synced
  /// calendar's server may fill one in from the address.
  final String? name;

  /// The attendee's `ATTENDEE_TYPE`. Defaults to
  /// [AttendeeTypeAndroid.required], what Android's own calendar app writes
  /// for a guest.
  final AttendeeTypeAndroid type;

  /// The attendee's `ATTENDEE_RELATIONSHIP`. Defaults to
  /// [AttendeeRelationshipAndroid.attendee]. See
  /// [AttendeeRelationshipAndroid.organizer] for how an organizer row is
  /// treated.
  final AttendeeRelationshipAndroid relationship;

  /// The attendee's `ATTENDEE_STATUS`. Defaults to
  /// [AttendeeStatusAndroid.invited], a guest who hasn't answered yet. On a
  /// synced calendar the server changes it as the attendee responds.
  final AttendeeStatusAndroid status;

  @override
  bool operator ==(Object other) =>
      other is AttendeeWriteAndroid &&
      other.email == email &&
      other.name == name &&
      other.type == type &&
      other.relationship == relationship &&
      other.status == status;

  @override
  int get hashCode => Object.hash(email, name, type, relationship, status);

  @override
  String toString() => 'AttendeeWriteAndroid(email: $email, name: $name, '
      'type: $type, relationship: $relationship, status: $status)';
}

/// Android-only options for `createEvent`.
///
/// Applies only on Android; ignored on iOS.
class EventOptionsAndroid {
  /// Creates Android-only options for a new event.
  const EventOptionsAndroid({this.status, this.attendees});

  /// The new event's `CalendarContract.Events.STATUS`.
  ///
  /// Android only, with Android's own `STATUS` semantics. When `null` the
  /// event is written as [EventStatusAndroid.confirmed], as it always has
  /// been. On a synced calendar (Google, Exchange…) the account's server may
  /// overwrite it on the next sync.
  final EventStatusAndroid? status;

  /// The new event's `CalendarContract.Attendees` rows, one per entry, or
  /// `null` (or empty) to write none.
  ///
  /// Android only: iOS EventKit can't add attendees. Written with the event
  /// in one transaction. **On a synced calendar the server may email each
  /// address an invitation**, and may rewrite the rows (see
  /// [AttendeeWriteAndroid]).
  final List<AttendeeWriteAndroid>? attendees;

  @override
  bool operator ==(Object other) =>
      other is EventOptionsAndroid &&
      other.status == status &&
      listEquals(other.attendees, attendees);

  @override
  int get hashCode => Object.hash(
        status,
        attendees == null ? null : Object.hashAll(attendees!),
      );

  @override
  String toString() =>
      'EventOptionsAndroid(status: $status, attendees: $attendees)';
}

/// Android-only options for `updateEvent` and `updateRecurring`.
///
/// Applies only on Android; ignored on iOS. A `null` field leaves the event's
/// value unchanged. A field Android lets you remove takes a `Patch`, as
/// `updateEvent`'s description does: [attendees].
class EventUpdateOptionsAndroid {
  /// Creates Android-only options for an event update.
  const EventUpdateOptionsAndroid({this.status, this.attendees});

  /// The event's new `CalendarContract.Events.STATUS`, or `null` to leave
  /// it unchanged.
  ///
  /// Android only, with Android's own `STATUS` semantics. There is no clear:
  /// Android's Calendar Provider can't write a `NULL` status to an existing
  /// event (it throws on one), so a status, once set, can only be changed.
  /// On a synced calendar (Google, Exchange…) the account's server may
  /// overwrite it on the next sync.
  ///
  /// On one occurrence of a series (`updateEvent` with an instance ID) it
  /// applies to that occurrence alone; an occurrence edited without it keeps
  /// the series' status. On `updateRecurring` it applies to the scope:
  /// the whole series for `allEvents`, the new series for
  /// `thisAndFollowing`. Occurrences edited on their own keep their own
  /// status either way. [EventStatusAndroid.canceled] takes a series or an
  /// occurrence out of listings (see there).
  final EventStatusAndroid? status;

  /// The event's new `CalendarContract.Attendees` rows: `null` leaves them
  /// unchanged, [Patch.set] replaces them with the list, [Patch.clear]
  /// removes them.
  ///
  /// Android only: iOS EventKit can't add or remove attendees. A set or a
  /// clear replaces every attendee row except the organizer's
  /// (`RELATIONSHIP_ORGANIZER`), which the shared `Event.attendees` doesn't
  /// read either: the event keeps its organizer. A set whose list holds an
  /// [AttendeeRelationshipAndroid.organizer] entry replaces the organizer
  /// row too. An empty set removes the same rows as a clear (though the two
  /// patches aren't equal). **On a synced calendar the server may email
  /// each new address an invitation, and each removed one a cancellation**,
  /// and may rewrite the rows (see [AttendeeWriteAndroid]).
  ///
  /// On one occurrence of a series (`updateEvent` with an instance ID) it
  /// applies to that occurrence alone; an occurrence edited without it keeps
  /// the series' attendees. On `updateRecurring` it applies to the scope:
  /// the whole series for `allEvents`, the new series for
  /// `thisAndFollowing`, which otherwise carries the original's attendees.
  /// Occurrences edited on their own keep their own attendees either way.
  final Patch<List<AttendeeWriteAndroid>>? attendees;

  /// Whether no field is set, so the options change nothing.
  bool get isEmpty => status == null && attendees == null;

  @override
  bool operator ==(Object other) =>
      other is EventUpdateOptionsAndroid &&
      other.status == status &&
      other.attendees == attendees;

  @override
  int get hashCode => Object.hash(status, attendees);

  @override
  String toString() =>
      'EventUpdateOptionsAndroid(status: $status, attendees: $attendees)';
}

/// Android-only options for `createCalendar`.
///
/// Applies only on Android; ignored on iOS. Picks the account the calendar is
/// created under. Only the local account type (`ACCOUNT_TYPE_LOCAL`, the
/// default) accepts new calendars from a third-party app; any other
/// [accountType] is refused with `DeviceCalendarError.readOnly`, matching
/// what `CalendarSource.supportsCalendarCreation` reports for it. Other
/// account types belong to their sync adapters, which can wipe a calendar
/// they didn't create.
///
/// ```dart
/// await plugin.createCalendar(
///   name: 'My Calendar',
///   android: const CalendarOptionsAndroid(accountName: 'MyApp'),
/// );
/// ```
class CalendarOptionsAndroid {
  /// Creates Android-only options for a new calendar.
  const CalendarOptionsAndroid({this.accountName, this.accountType});

  /// The account name for the calendar.
  ///
  /// Calendars with the same account name are grouped together in the
  /// device's calendar app. Defaults to `"local"`.
  final String? accountName;

  /// The account type for the calendar.
  ///
  /// Use values from `CalendarSource.accountType`. Only
  /// `ACCOUNT_TYPE_LOCAL` (`"LOCAL"`, the default) is accepted; a
  /// sync-adapter type such as `"com.google"` throws
  /// `DeviceCalendarError.readOnly`.
  final String? accountType;

  @override
  bool operator ==(Object other) =>
      other is CalendarOptionsAndroid &&
      other.accountName == accountName &&
      other.accountType == accountType;

  @override
  int get hashCode => Object.hash(accountName, accountType);

  @override
  String toString() => 'CalendarOptionsAndroid(accountName: $accountName, '
      'accountType: $accountType)';
}

/// iOS-only options for `createCalendar`.
///
/// Applies only on iOS; ignored on Android. Picks the source (account) the
/// calendar is created under. Without a [sourceId] the calendar goes under
/// iCloud when the device has it, otherwise the local source. Only those two
/// accept new calendars from a third-party app; any other source (Google,
/// Exchange, subscribed…) is refused with `DeviceCalendarError.readOnly`,
/// matching what `CalendarSource.supportsCalendarCreation` reports for it.
///
/// ```dart
/// final sources = await plugin.listSources();
/// final icloud = sources.firstWhere((s) => s.accountName == 'iCloud');
///
/// await plugin.createCalendar(
///   name: 'Work Calendar',
///   ios: CalendarOptionsIos(sourceId: icloud.id),
/// );
/// ```
class CalendarOptionsIos {
  /// Creates iOS-only options for a new calendar.
  const CalendarOptionsIos({this.sourceId});

  /// The source to create the calendar under: a `CalendarSource.id`, which
  /// is `EKSource.sourceIdentifier`.
  final String? sourceId;

  @override
  bool operator ==(Object other) =>
      other is CalendarOptionsIos && other.sourceId == sourceId;

  @override
  int get hashCode => sourceId.hashCode;

  @override
  String toString() => 'CalendarOptionsIos(sourceId: $sourceId)';
}
