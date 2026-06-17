import 'package:flutter/foundation.dart';

import 'attendee.dart';
import 'event_availability.dart';
import 'event_status.dart';
import 'recurrence_rule.dart';

/// Represents a calendar event.
class Event {
  /// Unique system identifier for this event.
  /// For recurring events, all instances share the same eventId.
  final String eventId;

  /// Identifies this specific occurrence; pass it to act on one occurrence of a
  /// recurring series.
  ///
  /// Equals [eventId] for non-recurring events. This is a plugin-derived,
  /// **unstable** ID: it becomes invalid when the occurrence's start date
  /// changes, so re-fetch events after edits.
  final String instanceId;

  /// ID of the calendar this event belongs to.
  final String calendarId;

  /// Title of the event.
  final String title;

  /// Description of the event.
  final String? description;

  /// Location of the event.
  final String? location;

  /// Start date and time of the event.
  ///
  /// For all-day events, treat this as a floating date (timezone-independent).
  final DateTime startDate;

  /// End date and time of the event.
  ///
  /// For all-day events, treat this as a floating date (timezone-independent).
  /// Uses half-open interval [start, end). (i.e. the event is up to, but not including, the end date.)
  final DateTime endDate;

  /// Whether this is an all-day event.
  final bool isAllDay;

  /// Availability status of the event.
  final EventAvailability availability;

  /// Status of the event.
  final EventStatus status;

  /// Timezone identifier for the event (e.g., "America/New_York").
  /// Null for all-day events (floating dates).
  final String? timeZone;

  /// Whether this is a recurring event.
  /// True for recurring events, false for one-time events.
  final bool isRecurring;

  /// Parsed recurrence rule for this event.
  ///
  /// Null if the event is not recurring, or if the platform RRULE uses
  /// features outside the supported subset (e.g. FREQ=MINUTELY).
  ///
  /// For full RRULE access, use [recurrenceRule?.rruleString] which preserves
  /// the original platform string.
  final RecurrenceRule? recurrenceRule;

  /// Attendees of this event (read-only).
  ///
  /// Null if the event has no attendees or attendees are not available.
  /// iOS and Android both support reading attendees but neither platform
  /// supports programmatic write via this plugin.
  final List<Attendee>? attendees;

  /// Relative-time reminders for this event, each a lead time **before** start
  /// (e.g. `Duration(minutes: 15)`). Null when there are none.
  ///
  /// Minute-granular: sub-minute durations round to the nearest minute, so
  /// `Duration(seconds: 90)` round-trips as `Duration(minutes: 2)`.
  final List<Duration>? reminders;

  /// Optional URL associated with this event — typically a meeting link, ticket
  /// page, or deep link. Visible in the native Calendar UI on iOS; round-trips
  /// through the plugin on Android.
  final String? url;

  Event({
    required this.eventId,
    required this.instanceId,
    required this.calendarId,
    required this.title,
    this.description,
    this.location,
    required this.startDate,
    required this.endDate,
    required this.isAllDay,
    required this.availability,
    required this.status,
    this.timeZone,
    required this.isRecurring,
    this.recurrenceRule,
    this.attendees,
    this.reminders,
    this.url,
  });

  /// Creates an Event from a map returned by the platform.
  factory Event.fromMap(Map<String, dynamic> map) {
    final rruleString = map['recurrenceRule'] as String?;
    final attendeesList = map['attendees'] as List<dynamic>?;
    final remindersList = map['reminders'] as List<dynamic>?;
    return Event(
      eventId: map['eventId'] as String,
      instanceId: map['instanceId'] as String,
      calendarId: map['calendarId'] as String,
      title: map['title'] as String,
      description: map['description'] as String?,
      location: map['location'] as String?,
      startDate: DateTime.fromMillisecondsSinceEpoch(map['startDate'] as int),
      endDate: DateTime.fromMillisecondsSinceEpoch(map['endDate'] as int),
      isAllDay: map['isAllDay'] as bool,
      availability: EventAvailability.fromName(map['availability'] as String),
      status: EventStatus.fromName(map['status'] as String),
      timeZone: map['timeZone'] as String?,
      isRecurring: map['isRecurring'] as bool? ?? false,
      recurrenceRule: rruleString != null
          ? RecurrenceRule.fromRruleString(rruleString)
          : null,
      attendees: attendeesList
          ?.map((a) => Attendee.fromMap(Map<String, dynamic>.from(a as Map)))
          .toList(),
      reminders: remindersList
          ?.map((m) => Duration(minutes: (m as num).toInt()))
          .toList(),
      url: map['url'] as String?,
    );
  }

  /// Converts this Event to a map for platform communication.
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'eventId': eventId,
      'instanceId': instanceId,
      'calendarId': calendarId,
      'title': title,
      'startDate': startDate.millisecondsSinceEpoch,
      'endDate': endDate.millisecondsSinceEpoch,
      'isAllDay': isAllDay,
      'availability': availability.name,
      'status': status.name,
      'isRecurring': isRecurring,
    };

    if (description != null) map['description'] = description;
    if (location != null) map['location'] = location;
    if (timeZone != null) map['timeZone'] = timeZone;
    if (url != null) map['url'] = url;
    if (recurrenceRule != null) {
      map['recurrenceRule'] = recurrenceRule!.rruleString;
    }
    if (attendees != null) {
      map['attendees'] = attendees!.map((a) => a.toMap()).toList();
    }
    if (reminders != null) {
      map['reminders'] =
          reminders!.map((d) => (d.inSeconds / 60).round()).toList();
    }

    return map;
  }

  @override
  String toString() {
    return 'Event(eventId: $eventId, instanceId: $instanceId, calendarId: $calendarId, title: $title, '
        'startDate: $startDate, endDate: $endDate, isAllDay: $isAllDay, url: $url)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Event &&
        other.eventId == eventId &&
        other.instanceId == instanceId &&
        other.calendarId == calendarId &&
        other.title == title &&
        other.description == description &&
        other.location == location &&
        other.startDate == startDate &&
        other.endDate == endDate &&
        other.isAllDay == isAllDay &&
        other.availability == availability &&
        other.status == status &&
        other.timeZone == timeZone &&
        other.isRecurring == isRecurring &&
        other.recurrenceRule == recurrenceRule &&
        listEquals(other.attendees, attendees) &&
        listEquals(other.reminders, reminders) &&
        other.url == url;
  }

  @override
  int get hashCode {
    return Object.hash(
      eventId,
      instanceId,
      calendarId,
      title,
      description,
      location,
      startDate,
      endDate,
      isAllDay,
      availability,
      status,
      timeZone,
      isRecurring,
      recurrenceRule,
      attendees != null ? Object.hashAll(attendees!) : null,
      reminders != null ? Object.hashAll(reminders!) : null,
      url,
    );
  }
}
