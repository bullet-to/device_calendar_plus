import 'event_availability.dart';
import 'event_status.dart';

/// Represents a calendar event.
class Event {
  /// Unique system identifier for this event.
  /// For recurring events, all instances share the same eventId.
  final String eventId;

  /// Instance identifier that uniquely identifies this specific event instance.
  ///
  /// **UNSTABLE ID:** This is a plugin-generated identifier, not a system ID.
  /// It is derived from the [eventId] and the event's start date.
  ///
  /// Use this with [DeviceCalendar.instance.getEvent] and [DeviceCalendar.instance.showEventModal]
  /// to fetch or display this specific event occurrence.
  ///
  /// For non-recurring events, this equals [eventId].
  /// For recurring events, this is a unique identifier for each occurrence.
  ///
  /// **Important:** This ID becomes invalid when the event's start date changes.
  /// You are responsible for keeping instanceId up to date by re-fetching events.
  ///
  /// Example scenario where instanceId becomes invalid:
  /// ```dart
  /// // 1. You fetch some events
  /// final events = await plugin.retrieveEvents(calendarId, ...);
  ///
  /// // 2. User opens native modal from one of the events and changes the start date
  /// await plugin.showEventModal(event.instanceId);
  /// // User changes date from Nov 5 to Nov 6 and saves
  ///
  /// // 3. Your stored instanceId is now invalid!
  /// // The savedInstanceId no longer points to any event
  ///
  /// // 4. You must re-fetch to get the updated instanceId
  /// final events = await plugin.retrieveEvents(calendarId, ...);
  /// ```
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
  });

  /// Creates an Event from a map returned by the platform.
  factory Event.fromMap(Map<String, dynamic> map) {
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

    return map;
  }

  @override
  String toString() {
    return 'Event(eventId: $eventId, instanceId: $instanceId, calendarId: $calendarId, title: $title, '
        'startDate: $startDate, endDate: $endDate, isAllDay: $isAllDay)';
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
        other.isRecurring == isRecurring;
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
    );
  }
}
