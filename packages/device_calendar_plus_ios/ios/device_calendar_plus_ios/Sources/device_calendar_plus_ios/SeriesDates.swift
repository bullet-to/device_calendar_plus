import EventKit
import Foundation

/// The date arithmetic behind a series update: which zone frames a series'
/// calendar days, whether an anchor move clashes with the rule's pinned
/// days, and the start the update leaves the series with. Pure — the device
/// zone is passed in rather than read from `TimeZone.current`, so native
/// tests can drive the zones the integration harness can't set on iOS.
/// Android's counterpart is `SeriesDates.kt`.
enum SeriesDates {
  /// Whether moving the anchor from `reference` to `target` would change the
  /// day-spec that `rule` pins explicitly: the weekday for a BYDAY rule, the
  /// day-of-month for a BYMONTHDAY rule, or the month for a BYMONTH rule. When
  /// it would, an anchor shift alone can't say what the new pattern should be
  /// (see updateRecurring docs), so the caller must supply a new rule. Rules
  /// with no explicit anchor return false — they follow the anchor freely.
  /// Each date is read in its own frame: `reference` in the zone the series
  /// is stored in, `target` in the zone it has after the edit — they differ
  /// only when the edit toggles all-day. Android's counterpart is
  /// `dayMoveConflictsWithRule`.
  private static func dayMoveConflictsWithRule(
    rule: EKRecurrenceRule,
    reference: Date,
    referenceZone: TimeZone,
    target: Date,
    targetZone: TimeZone
  ) -> Bool {
    var referenceCalendar = Calendar(identifier: .gregorian)
    referenceCalendar.timeZone = referenceZone
    var targetCalendar = Calendar(identifier: .gregorian)
    targetCalendar.timeZone = targetZone
    func changed(_ unit: Calendar.Component) -> Bool {
      return referenceCalendar.component(unit, from: reference)
        != targetCalendar.component(unit, from: target)
    }
    if let days = rule.daysOfTheWeek, !days.isEmpty { return changed(.weekday) }
    if let dom = rule.daysOfTheMonth, !dom.isEmpty { return changed(.day) }
    if let months = rule.monthsOfTheYear, !months.isEmpty { return changed(.month) }
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
  private static func shiftStart(
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

  /// The start a series update leaves a series with: `base` (its current
  /// start) when nothing moves it. Android's counterpart is
  /// `resolveSeriesTimes`.
  ///
  /// `target`, when given, shifts the anchor first: `base` moves by the
  /// wall-clock delta from `reference` (the occurrence being edited, or the
  /// series anchor) to `target`. That fails with `invalidArguments` when the
  /// move would change a day `existingRule` pins explicitly and the caller
  /// didn't also change the rule (the move is ambiguous — see updateRecurring
  /// docs), and with `operationFailed` if the shift can't be computed.
  ///
  /// Two zones frame the series' calendar days. The stored frame is the
  /// series' stored zone (`deviceZone` when it has none — EventKit gives
  /// all-day events a nil zone). The edit frame is the device zone for an
  /// all-day result — EventKit floats an all-day start onto its local date,
  /// and the plugin passes all-day starts as local midnights — and the stored
  /// frame for a timed one. Reading a timed series stored in another zone
  /// (e.g. UTC) in its stored frame while toggling it all-day would snap the
  /// anchor to that zone's midnight, which floats onto the previous local day
  /// west of it: an extra occurrence off the rule's pinned weekday that also
  /// uses up one of its COUNT. Android's counterpart is `seriesTimeZone`,
  /// which frames all-day in UTC because the Calendar Provider stores
  /// all-day as UTC midnight.
  ///
  /// The shift and the new-rule walk run in the edit frame. Base and
  /// reference are the same wall-clock time of the one series, so reading
  /// them in the edit zone moves both alike and leaves the day delta intact
  /// (Android's `resolveSeriesTimes` does the same). The conflict check reads
  /// `reference` in the stored frame and `target` in the edit one.
  ///
  /// A new `rule` then walks the anchor onto the first day it generates: the
  /// rule may not generate the anchor's day (a Saturday series switched to
  /// Sundays), and EventKit would keep that day as an extra first occurrence
  /// (#140). A rule that generates nothing within five years of the anchor
  /// fails with `invalidArguments` rather than leaving that orphan behind.
  static func resolveSeriesStart(
    base: Date,
    storedZone: TimeZone?,
    existingRule: EKRecurrenceRule?,
    target: Date?,
    reference: Date,
    isAllDay: Bool,
    rule: EKRecurrenceRule?,
    changingRule: Bool,
    deviceZone: TimeZone
  ) -> Result<Date, CalendarError> {
    let storedFrame = storedZone ?? deviceZone
    let editFrame = isAllDay ? deviceZone : storedFrame
    var start = base

    if let target = target {
      if !changingRule,
         let existingRule = existingRule,
         dayMoveConflictsWithRule(
           rule: existingRule,
           reference: reference, referenceZone: storedFrame,
           target: target, targetZone: editFrame
         ) {
        return .failure(CalendarError(
          code: PlatformExceptionCodes.invalidArguments,
          message: "start moves this series to a different day, but its "
            + "recurrence rule pins specific days. Pass a recurrenceRule to "
            + "specify the new pattern."
        ))
      }

      guard let shifted = shiftStart(
        base, reference: reference, to: target,
        isAllDay: isAllDay, timeZone: editFrame
      ) else {
        return .failure(CalendarError(
          code: PlatformExceptionCodes.operationFailed,
          message: "Could not apply the new start to the event"
        ))
      }
      start = shifted
    }

    if let rule = rule {
      guard let anchored = RecurrenceAnchor.firstMatch(
        of: rule, onOrAfter: start, timeZone: editFrame
      ) else {
        return .failure(CalendarError(
          code: PlatformExceptionCodes.invalidArguments,
          message: "recurrenceRule generates no occurrences within five years of the anchor"
        ))
      }
      start = anchored
    }
    return .success(start)
  }
}
