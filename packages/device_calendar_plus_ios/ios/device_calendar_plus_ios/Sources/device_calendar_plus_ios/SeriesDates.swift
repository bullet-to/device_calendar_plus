import EventKit
import Foundation

/// Pure date decisions for editing a recurring series. Android's counterpart
/// is `SeriesDates.kt`; the two must agree.
enum SeriesDates {
  /// Whether moving the anchor from `reference` to `target` would change a
  /// day-spec that `rule` pins explicitly: the weekday for BYDAY, the
  /// day-of-month for BYMONTHDAY, or the month for BYMONTH. Every pinned part
  /// is checked: a BYDAY rule can also pin BYMONTH or BYMONTHDAY, and a move
  /// that keeps the weekday can still break those. When one would change, an
  /// anchor shift alone can't say what the new pattern should be (see
  /// updateRecurring docs), so the caller must supply a new rule. Rules with
  /// no explicit anchor return false — they follow the anchor freely.
  static func dayMoveConflictsWithRule(
    rule: EKRecurrenceRule,
    reference: Date,
    target: Date,
    timeZone: TimeZone
  ) -> Bool {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    func changed(_ unit: Calendar.Component) -> Bool {
      return calendar.component(unit, from: reference)
        != calendar.component(unit, from: target)
    }
    let hasByDay = !(rule.daysOfTheWeek?.isEmpty ?? true)
    let hasByMonthDay = !(rule.daysOfTheMonth?.isEmpty ?? true)
    let hasByMonth = !(rule.monthsOfTheYear?.isEmpty ?? true)
    if hasByDay && changed(.weekday) { return true }
    if hasByMonthDay && changed(.day) { return true }
    if hasByMonth && changed(.month) { return true }
    return false
  }

  /// Translates `base` by the wall-clock delta from `reference` to `target`,
  /// computed in `timeZone`: shifts by the whole-day difference and sets the
  /// time-of-day to `target`'s. DST-safe — it counts calendar days and sets a
  /// wall-clock time rather than adding a raw interval. For all-day events the
  /// day shifts but the time-of-day is left at the start of day.
  ///
  /// This is the anchor-shift that lets a single `updateRecurring` move both
  /// the time and the day of a series (issue #103). Android's counterpart is
  /// `SplitShift.slot`.
  static func shiftStart(
    _ base: Date,
    reference: Date,
    to target: Date,
    isAllDay: Bool,
    timeZone: TimeZone
  ) -> Date? {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let refDay = calendar.startOfDay(for: reference)
    let targetDay = calendar.startOfDay(for: target)
    let dayDelta = calendar.dateComponents([.day], from: refDay, to: targetDay).day ?? 0
    guard let shiftedDay = calendar.date(byAdding: .day, value: dayDelta, to: base) else {
      return nil
    }
    if isAllDay {
      return calendar.startOfDay(for: shiftedDay)
    }
    let tod = calendar.dateComponents([.hour, .minute, .second], from: target)
    return calendar.date(
      bySettingHour: tod.hour ?? 0,
      minute: tod.minute ?? 0,
      second: tod.second ?? 0,
      of: shiftedDay
    )
  }
}
