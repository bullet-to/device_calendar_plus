import EventKit
import Foundation

/// Pure date decisions for editing a recurring series. Android's counterpart
/// is `SeriesDates.kt`; the two must agree.
enum SeriesDates {
  /// Whether moving the anchor from `reference` to `target` would change a
  /// day-spec that `rule` pins explicitly: the weekday for BYDAY, the
  /// day-of-month for BYMONTHDAY, or the month for BYMONTH. Every pinned part
  /// is checked. When one would change, an anchor shift alone can't say what
  /// the new pattern should be (see updateRecurring docs), so the caller must
  /// supply a new rule. Rules with no explicit anchor return false — they
  /// follow the anchor freely.
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
    // Check every pinned part: a BYDAY rule can also pin BYMONTH or
    // BYMONTHDAY, and a move that keeps the weekday can still break those.
    let hasByDay = !(rule.daysOfTheWeek?.isEmpty ?? true)
    let hasByMonthDay = !(rule.daysOfTheMonth?.isEmpty ?? true)
    let hasByMonth = !(rule.monthsOfTheYear?.isEmpty ?? true)
    if hasByDay && changed(.weekday) { return true }
    if hasByMonthDay && changed(.day) { return true }
    if hasByMonth && changed(.month) { return true }
    return false
  }
}
