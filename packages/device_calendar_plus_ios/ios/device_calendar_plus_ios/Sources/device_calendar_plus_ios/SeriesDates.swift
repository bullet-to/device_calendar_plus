import EventKit
import Foundation

/// What a series edit does to its recurrence rule: keep the one it has
/// (`nil` when the event doesn't recur), replace it, or clear it. Android's
/// counterpart is `SeriesRuleEdit` in `SeriesDates.kt`.
enum SeriesRuleEdit {
  case keep(EKRecurrenceRule?)
  case replace(EKRecurrenceRule)
  case clear
}

/// The date arithmetic behind a series update: which zone frames a series'
/// calendar days, whether an anchor move lands on a day the rule generates,
/// and the start the update leaves the series with. Pure — the device
/// zone is passed in rather than read from `TimeZone.current`, so native
/// tests can drive the zones the integration harness can't set on iOS.
/// Android's counterpart is `SeriesDates.kt`.
enum SeriesDates {
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

  /// Whether a start move leaves `rule`'s days: either move lands on another
  /// day, read in `timeZone` (the edit frame), that the rule doesn't
  /// generate (`RecurrenceAnchor.generates`). `reference` to `target`
  /// guards the caller's intent; `reference` is read in `referenceZone`,
  /// the stored frame, so an all-day toggle onto another local day is a day
  /// move. `base` to `shifted` guards against the #140 orphan. Android's
  /// counterpart is `leavesRule` in `SeriesDates.kt`.
  private static func leavesRule(
    _ rule: EKRecurrenceRule,
    reference: Date,
    referenceZone: TimeZone,
    base: Date,
    target: Date,
    shifted: Date,
    timeZone: TimeZone
  ) -> Bool {
    func movesOffRule(from: Date, fromZone: TimeZone, to: Date) -> Bool {
      return !sameCalendarDay(from, fromZone, to, timeZone)
        && !RecurrenceAnchor.generates(rule, day: to, timeZone: timeZone)
    }
    // Both checks are needed, even though they repeat each other when the
    // reference is the base. On a {Mon,Tue,Fri} series starting Monday,
    // moving Friday to Saturday shifts the start to Tuesday, which the rule
    // generates: only the first check refuses it. Moving Monday to Tuesday
    // shifts a Friday start to Saturday: only the second does (#140).
    return movesOffRule(from: reference, fromZone: referenceZone, to: target)
      || movesOffRule(from: base, fromZone: timeZone, to: shifted)
  }

  /// Whether `rule` pins the days it falls on (BYDAY, BYMONTHDAY, BYMONTH or
  /// BYSETPOS) rather than taking them from its start. Android's
  /// counterpart is `RruleString.pinsDays`.
  private static func pinsDays(_ rule: EKRecurrenceRule) -> Bool {
    return !(rule.daysOfTheWeek ?? []).isEmpty
      || !(rule.daysOfTheMonth ?? []).isEmpty
      || !(rule.monthsOfTheYear ?? []).isEmpty
      || !(rule.setPositions ?? []).isEmpty
  }

  /// Whether `a` read in `aZone` falls on the same calendar date as `b` in `bZone`.
  private static func sameCalendarDay(
    _ a: Date, _ aZone: TimeZone, _ b: Date, _ bZone: TimeZone
  ) -> Bool {
    var aCalendar = Calendar(identifier: .gregorian)
    aCalendar.timeZone = aZone
    var bCalendar = Calendar(identifier: .gregorian)
    bCalendar.timeZone = bZone
    return aCalendar.dateComponents([.year, .month, .day], from: a)
      == bCalendar.dateComponents([.year, .month, .day], from: b)
  }

  /// The start a series update leaves a series with: `base` (its current
  /// start) when nothing moves it. Android's counterpart is
  /// `resolveSeriesTimes`.
  ///
  /// Frames: stored = `storedZone ?? deviceZone`; edit = `deviceZone` when
  /// `isAllDay`, else stored. All-day edits run locally because EventKit
  /// floats an all-day start onto its local date.
  ///
  /// - `target` shifts `base` by the wall-clock delta from `reference` (the
  ///   occurrence being edited, or the series anchor) to `target`, in the
  ///   edit frame. `base` and `reference` were written in the stored frame,
  ///   so reading them in the edit frame is only safe because they are the
  ///   same instant, or occurrences of one series at the same wall-clock
  ///   time: the wrong zone puts both on the same wrong day and the error
  ///   cancels out of the day delta (unless a DST change between them
  ///   carries just one across the other zone's midnight). Keep that
  ///   invariant, or read them in the stored frame, when changing either
  ///   input.
  /// - The new start must be a day the series' rule generates, or EventKit
  ///   shows it as an extra first occurrence (#140, #189). `ruleEdit`
  ///   decides how: a kept rule must generate the days the move lands on
  ///   (`leavesRule`); a replacing rule walks the shifted start, in the edit
  ///   frame, onto the first day it generates; a cleared rule needs
  ///   neither. A time-only move leaves a start the kept rule doesn't
  ///   generate (one anchored off its rule by another app, or in another
  ///   zone) where it is. A `splitsSeries` (thisAndFollowing) move onto
  ///   another day is also refused while the kept rule pins days (#194).
  ///
  /// Fails with `invalidArguments` when a start move lands on a day the kept
  /// rule doesn't generate or the new rule generates nothing within five
  /// years of the anchor, and with `operationFailed` if the shift can't be
  /// computed.
  static func resolveSeriesStart(
    base: Date,
    storedZone: TimeZone?,
    target: Date?,
    reference: Date,
    isAllDay: Bool,
    ruleEdit: SeriesRuleEdit,
    splitsSeries: Bool,
    deviceZone: TimeZone
  ) -> Result<Date, CalendarError> {
    let storedFrame = storedZone ?? deviceZone
    let editFrame = isAllDay ? deviceZone : storedFrame
    var start = base

    if let target = target {
      guard let shifted = shiftStart(
        base, reference: reference, to: target,
        isAllDay: isAllDay, timeZone: editFrame
      ) else {
        return .failure(CalendarError(
          code: PlatformExceptionCodes.operationFailed,
          message: "Could not apply the new start to the event"
        ))
      }

      if case .keep(let keptRule?) = ruleEdit {
        // EventKit can't split a series whose rule pins days at an
        // occurrence moved to another day: `.futureEvents` detaches it
        // instead (#194). Refused on both platforms until it can.
        if splitsSeries, pinsDays(keptRule),
           !sameCalendarDay(reference, storedFrame, target, editFrame) {
          return .failure(CalendarError(
            code: PlatformExceptionCodes.invalidArguments,
            message: "start moves a thisAndFollowing split onto another day, but "
              + "the series' recurrence rule pins specific days. Pass a "
              + "recurrenceRule to specify the new pattern."
          ))
        }
        if leavesRule(
          keptRule, reference: reference, referenceZone: storedFrame,
          base: base, target: target, shifted: shifted, timeZone: editFrame
        ) {
          return .failure(CalendarError(
            code: PlatformExceptionCodes.invalidArguments,
            message: "start moves this series onto a day its recurrence rule "
              + "doesn't generate. Pass a recurrenceRule to specify the new pattern."
          ))
        }
      }
      start = shifted
    }

    if case .replace(let rule) = ruleEdit {
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
