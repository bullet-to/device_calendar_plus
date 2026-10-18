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
// Every class is immutable, with optional named fields and value equality, so
// adding a field later is not a breaking change.

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

/// Android-only options for `createEvent`.
///
/// Applies only on Android; ignored on iOS.
class EventOptionsAndroid {
  /// Creates Android-only options for a new event.
  const EventOptionsAndroid({this.status});

  /// The new event's `CalendarContract.Events.STATUS`.
  ///
  /// Android only, with Android's own `STATUS` semantics. When `null` the
  /// event is written as [EventStatusAndroid.confirmed], as it always has
  /// been. On a synced calendar (Google, Exchange…) the account's server may
  /// overwrite it on the next sync.
  final EventStatusAndroid? status;

  @override
  bool operator ==(Object other) =>
      other is EventOptionsAndroid && other.status == status;

  @override
  int get hashCode => status.hashCode;

  @override
  String toString() => 'EventOptionsAndroid(status: $status)';
}

/// Android-only options for `updateEvent` and `updateRecurring`.
///
/// Applies only on Android; ignored on iOS. A `null` field leaves the event's
/// value unchanged. A field Android lets you remove would take a `Patch`, as
/// `updateEvent`'s description does.
class EventUpdateOptionsAndroid {
  /// Creates Android-only options for an event update.
  const EventUpdateOptionsAndroid({this.status});

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

  /// Whether no field is set, so the options change nothing.
  bool get isEmpty => status == null;

  @override
  bool operator ==(Object other) =>
      other is EventUpdateOptionsAndroid && other.status == status;

  @override
  int get hashCode => status.hashCode;

  @override
  String toString() => 'EventUpdateOptionsAndroid(status: $status)';
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
