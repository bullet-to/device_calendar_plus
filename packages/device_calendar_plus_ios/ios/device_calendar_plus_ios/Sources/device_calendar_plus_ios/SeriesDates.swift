import EventKit
import Foundation

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
  /// - Unless `changingRule`, that move is first checked against
  ///   `existingRule`: `target`'s day, read in the edit frame, must be one
  ///   the rule generates (`RecurrenceAnchor.generates`, with the parts the
  ///   rule leaves implicit taken from `target`). Comparing the weekday, day
  ///   of month and month the rule pins instead let an ordinal BYDAY (`4TH`,
  ///   `-1FR`) or BYSETPOS series move onto a day it doesn't generate,
  ///   orphaning its first occurrence as in #140 (#189). A time-only move
  ///   always passes, and an all-day toggle onto a local day the rule
  ///   doesn't generate is refused like any other day move. Android's
  ///   counterpart is the check in `resolveTargetStart`.
  /// - A new `rule` then walks the anchor, in the edit frame, onto the first
  ///   day it generates (#140).
  ///
  /// Fails with `invalidArguments` when the move leaves the rule's days or the
  /// new rule generates nothing within five years of the anchor, and with
  /// `operationFailed` if the shift can't be computed.
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
         !RecurrenceAnchor.generates(existingRule, day: target, timeZone: editFrame) {
        return .failure(CalendarError(
          code: PlatformExceptionCodes.invalidArguments,
          message: "start moves this series onto a day its recurrence rule "
            + "doesn't generate. Pass a recurrenceRule to specify the new pattern."
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
