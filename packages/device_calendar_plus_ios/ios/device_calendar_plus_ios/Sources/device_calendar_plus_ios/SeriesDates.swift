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
  /// Mirrors Android's MINUTES_PER_DAY — the whole-day duration checks on the
  /// two platforms must stay in lockstep.
  private static let minutesPerDay = 1440

  private static let secondsPerDay = 86_400

  /// `base` moved `days` calendar days, then set to the wall-clock time
  /// `secondsIntoDay` seconds after midnight (`nil` for the start of the
  /// day). The one piece of DST-safe arithmetic here: it counts calendar
  /// days and sets a wall-clock time, so a 23- or 25-hour day can't carry
  /// the result an hour off.
  private static func wallClock(
    _ base: Date,
    plusDays days: Int,
    secondsIntoDay: Int?,
    calendar: Calendar
  ) -> Date? {
    guard let shiftedDay = calendar.date(byAdding: .day, value: days, to: base) else {
      return nil
    }
    guard let seconds = secondsIntoDay else {
      return calendar.startOfDay(for: shiftedDay)
    }
    return calendar.date(
      bySettingHour: seconds / 3600,
      minute: seconds % 3600 / 60,
      second: seconds % 60,
      of: shiftedDay
    )
  }

  /// `date`'s wall-clock time in `calendar`, in seconds after midnight.
  private static func secondsIntoDay(_ date: Date, _ calendar: Calendar) -> Int {
    let tod = calendar.dateComponents([.hour, .minute, .second], from: date)
    return (tod.hour ?? 0) * 3600 + (tod.minute ?? 0) * 60 + (tod.second ?? 0)
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
    return wallClock(
      base,
      plusDays: dayDelta,
      secondsIntoDay: isAllDay ? nil : secondsIntoDay(target, calendar),
      calendar: calendar
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

  /// The end a series update leaves a series with, once its start moves to
  /// `newStart`: `durationMinutes` after it, or the current `start`–`end`
  /// span when no duration is given.
  ///
  /// `nil` when the update moves nothing: no start given (`startGiven`), no
  /// duration, and `newStart` still `start` (a rule that already fits its
  /// anchor resolves to the current start). The caller then skips the time
  /// rewrite, mirroring Android's `rewriteTimeColumns`.
  ///
  /// All-day spans are wall-clock spans in `deviceZone` (the all-day edit
  /// frame): whole calendar days plus a time of day. EventKit keeps an
  /// all-day event at local midnight, so a day carried as 86,400 seconds
  /// falls an hour short or long across a DST change, and the event loses
  /// or gains its last day (#195). A kept span is measured from `start`'s
  /// wall clock to `end`'s, so a timed event toggled all-day carries its
  /// span from the new day's midnight; one that runs backwards on the wall
  /// clock (a DST fall-back) clamps to zero length at `newStart`. Timed spans
  /// stay exact intervals.
  ///
  /// The duration half of Android's `resolveSeriesTimes`. Android adds exact
  /// milliseconds even for all-day series: its all-day rows are stored in
  /// UTC, which has no DST.
  ///
  /// An all-day end comes back in EventKit's stored form, the last second of
  /// the last day (`allDayStoredEnd`).
  ///
  /// Fails with `invalidArguments` when an all-day series is given a
  /// `durationMinutes` that isn't whole days, and with `operationFailed` if
  /// the calendar can't compute the date.
  static func resolveSeriesEnd(
    start: Date,
    end: Date,
    newStart: Date,
    startGiven: Bool,
    durationMinutes: Int?,
    isAllDay: Bool,
    deviceZone: TimeZone
  ) -> Result<Date?, CalendarError> {
    guard startGiven || durationMinutes != nil || newStart != start else {
      return .success(nil)
    }
    guard isAllDay else {
      let duration = durationMinutes.map { TimeInterval($0 * 60) }
        ?? end.timeIntervalSince(start)
      return .success(newStart.addingTimeInterval(duration))
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = deviceZone
    let spanSeconds: Int
    if let durationMinutes = durationMinutes {
      // All-day events have no time-of-day and only whole-day durations.
      // The Dart layer can only check this against fields in the same call;
      // the stored event's all-day state is enforced here.
      guard durationMinutes % minutesPerDay == 0 else {
        return .failure(CalendarError(
          code: PlatformExceptionCodes.invalidArguments,
          message: "All-day events require whole-day durations"
        ))
      }
      // End on the last day's 23:59:59, where EventKit keeps an all-day
      // event's end (see `allDayStoredEnd`): an exclusive midnight on an
      // existing all-day event reads as one more day.
      spanSeconds = max(0, durationMinutes * 60 - 1)
    } else {
      // A span that runs backwards on the wall clock (a DST fall-back) would
      // end before the new start, which EventKit won't save: clamp it.
      spanSeconds = max(0, wallClockSpan(from: start, to: end, calendar))
    }
    let endSeconds = secondsIntoDay(newStart, calendar) + spanSeconds
    guard let resolved = wallClock(
      newStart,
      plusDays: endSeconds / secondsPerDay,
      secondsIntoDay: endSeconds % secondsPerDay,
      calendar: calendar
    ) else {
      return .failure(CalendarError(
        code: PlatformExceptionCodes.operationFailed,
        message: "Could not apply the new end to the event"
      ))
    }
    return .success(resolved)
  }

  /// The end to write for an all-day event whose end is `end`, exclusive
  /// (the plugin's form: midnight after the last day). EventKit keeps an
  /// all-day event's end at the last second of its last day, and reads an
  /// exclusive midnight written onto an existing all-day event as one more
  /// day; the read path adds the second back. Timed ends pass through.
  static func allDayStoredEnd(_ end: Date, isAllDay: Bool) -> Date {
    return isAllDay ? end.addingTimeInterval(-1) : end
  }

  /// The wall-clock span from `start` to `end` in `calendar`, in seconds:
  /// whole calendar days at 86,400 each, plus the difference in time of day.
  /// Negative when `end`'s wall clock reads earlier than `start`'s (a short
  /// span across a DST fall-back).
  private static func wallClockSpan(from start: Date, to end: Date, _ calendar: Calendar) -> Int {
    let days = calendar.dateComponents(
      [.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)
    ).day ?? 0
    return days * secondsPerDay + secondsIntoDay(end, calendar) - secondsIntoDay(start, calendar)
  }
}
