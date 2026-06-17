import EventKit

/// The shared field edits of an event update — title, description, location,
/// url, all-day flag, time zone and availability. Nil fields are left
/// untouched; fields named in `clearedFields` are cleared.
///
/// Decoded once from the method-channel arguments and shared by
/// `EventsService.updateEvent` and `EventsService.updateRecurring`, whose
/// remaining parameters are the ones that differ per operation. The Swift
/// counterpart of Android's `EventFieldPatch`.
struct EventFieldPatch {
  /// The three states of a reminders edit: leave the event's reminders
  /// untouched, replace the whole set, or remove them all. Mirrors the Dart
  /// `Patch<List<Duration>>` over the method channel.
  enum RemindersPatch {
    case unchanged
    case set([Int])  // minutes before start
    case clear
  }

  let title: String?
  let description: String?
  let location: String?
  let url: String?
  let isAllDay: Bool?
  let timeZone: String?
  let availability: String?
  let reminders: RemindersPatch
  let clearedFields: [String]

  /// Reads the patch fields from method-channel arguments.
  init(args: [String: Any]) {
    title = args["title"] as? String
    description = args["description"] as? String
    location = args["location"] as? String
    url = args["url"] as? String
    isAllDay = args["isAllDay"] as? Bool
    timeZone = args["timeZone"] as? String
    availability = args["availability"] as? String
    clearedFields = args["clearedFields"] as? [String] ?? []
    // A present `reminders` key replaces the set; the key named in
    // clearedFields clears it; neither leaves it unchanged.
    if let minutes = args["reminders"] as? [Int] {
      reminders = .set(minutes)
    } else if clearedFields.contains("reminders") {
      reminders = .clear
    } else {
      reminders = .unchanged
    }
  }

  /// Applies the patch to `event`, except the time zone — each write path
  /// applies it after its date changes (see `applyTimeZone(to:)`).
  func apply(to event: EKEvent) {
    if let title = title { event.title = title }
    if clearedFields.contains("description") {
      event.notes = nil
    } else if let description = description {
      event.notes = description
    }
    if clearedFields.contains("location") {
      event.location = nil
    } else if let location = location {
      event.location = location
    }
    if clearedFields.contains("url") {
      event.url = nil
    } else if let url = url {
      event.url = URL(string: url)
    }
    switch reminders {
    case .unchanged:
      break
    case .clear:
      event.alarms = nil
    case .set(let minutes):
      EventFieldPatch.applyReminders(minutes, to: event)
    }
    if let isAllDay = isAllDay { event.isAllDay = isAllDay }
    if let availability = availability {
      switch availability {
      case "free": event.availability = .free
      case "tentative": event.availability = .tentative
      case "unavailable": event.availability = .unavailable
      case "busy": event.availability = .busy
      default: break
      }
    }
  }

  /// Replaces `event.alarms` with relative-offset alarms built from `minutes`
  /// (whole minutes before start). An empty list clears the alarms. Shared by
  /// the update patch and `EventsService.createEvent` so the EKAlarm mapping
  /// lives in one place.
  static func applyReminders(_ minutes: [Int], to event: EKEvent) {
    if minutes.isEmpty {
      event.alarms = nil
      return
    }
    event.alarms = minutes.map { EKAlarm(relativeOffset: -Double($0) * 60) }
  }

  /// Normalizes the event's time zone: all-day events carry none; otherwise
  /// the patch's time zone applies when given. Call after `apply(to:)` and
  /// any date changes, since the all-day flag may have just changed.
  func applyTimeZone(to event: EKEvent) {
    if event.isAllDay {
      event.timeZone = nil
    } else if let identifier = timeZone {
      event.timeZone = TimeZone(identifier: identifier)
    }
  }
}
