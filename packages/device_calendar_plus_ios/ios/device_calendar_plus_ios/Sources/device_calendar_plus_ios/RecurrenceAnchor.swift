import EventKit
import Foundation

/// Picks the anchor (start) for a series whose recurrence rule is being
/// replaced.
///
/// RFC 5545 wants a series' start to be a day its rule generates, and both
/// iOS EventKit and Android's Calendar Provider treat one that isn't as an
/// extra first occurrence — the orphaned Saturday of #140. `firstMatch` walks
/// forward from the intended anchor to the first day the rule generates, so
/// the anchor of a series switched to a new pattern lands on that pattern.
/// Android's counterpart is `RecurrenceAnchor.kt`; the two must agree.
enum RecurrenceAnchor {
  /// Five years: enough for a rule pinned to 29 February.
  private static let maxLookaheadDays = 5 * 366

  /// The first instant on or after `from` whose calendar day (in `timeZone`)
  /// `rule` generates, at `from`'s wall-clock time. Parts the rule leaves
  /// implicit (no BYDAY, BYMONTHDAY or BYMONTH) come from `from` itself, as
  /// they would from the start date — so a rule that already fits its anchor
  /// returns `from` unchanged. Nil when the rule generates nothing within
  /// five years, in which case the caller leaves the anchor alone.
  static func firstMatch(
    of rule: EKRecurrenceRule,
    onOrAfter from: Date,
    timeZone: TimeZone
  ) -> Date? {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let matcher = Matcher(rule: rule, anchor: from, calendar: calendar)
    var day = from
    for _ in 0..<maxLookaheadDays {
      if matcher.generates(day) { return day }
      // Whole-day steps keep the wall-clock time across DST (mirrors
      // shiftStart).
      guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
      day = next
    }
    return nil
  }

  /// One BYDAY entry: `weekday` is a Gregorian weekday (1 = Sunday),
  /// `ordinal` 0 = every.
  private struct ByDay {
    let ordinal: Int
    let weekday: Int
  }

  /// A day's weekday ordinal within its period, counted from the start and
  /// the end.
  private struct Nth {
    let fromStart: Int
    let fromEnd: Int
  }

  /// Decides whether a day is in the rule's set for the period (week, month,
  /// year) containing it. The period's set is built once and cached, since
  /// `firstMatch` visits its days in order.
  private final class Matcher {
    private let calendar: Calendar
    private let frequency: EKRecurrenceFrequency
    private let byDay: [ByDay]
    private let byMonthDay: [Int]
    private let byMonth: [Int]
    private let bySetPos: [Int]
    private let weekStart: Int
    private let anchorWeekday: Int
    private let anchorDayOfMonth: Int
    private let anchorMonth: Int
    private var cachedPeriod: Int?
    private var cachedDays: Set<Int> = []

    init(rule: EKRecurrenceRule, anchor: Date, calendar: Calendar) {
      self.calendar = calendar
      frequency = rule.frequency
      byDay = (rule.daysOfTheWeek ?? []).map {
        ByDay(ordinal: $0.weekNumber, weekday: $0.dayOfTheWeek.rawValue)
      }
      byMonthDay = (rule.daysOfTheMonth ?? []).map { $0.intValue }
      byMonth = (rule.monthsOfTheYear ?? []).map { $0.intValue }
      bySetPos = (rule.setPositions ?? []).map { $0.intValue }
      // EventKit reports 0 for an unset WKST; RFC 5545 defaults to Monday.
      weekStart = rule.firstDayOfTheWeek == 0 ? 2 : rule.firstDayOfTheWeek
      anchorWeekday = calendar.component(.weekday, from: anchor)
      anchorDayOfMonth = calendar.component(.day, from: anchor)
      anchorMonth = calendar.component(.month, from: anchor)
    }

    func generates(_ day: Date) -> Bool {
      let period = periodKey(day)
      if period != cachedPeriod {
        cachedPeriod = period
        cachedDays = applySetPos(periodDays(day))
      }
      return cachedDays.contains(dayKey(day))
    }

    /// BYSETPOS keeps only the listed positions (1-based; negative from the end).
    private func applySetPos(_ days: Set<Int>) -> Set<Int> {
      if bySetPos.isEmpty { return days }
      let ordered = days.sorted()
      return Set(bySetPos.compactMap { pos -> Int? in
        let index = pos > 0 ? pos - 1 : ordered.count + pos
        return ordered.indices.contains(index) ? ordered[index] : nil
      })
    }

    private func dayKey(_ day: Date) -> Int {
      let year = calendar.component(.year, from: day)
      let dayOfYear = calendar.ordinality(of: .day, in: .year, for: day) ?? 0
      return year * 1000 + dayOfYear
    }

    private func periodKey(_ day: Date) -> Int {
      switch frequency {
      case .daily: return dayKey(day)
      case .weekly: return dayKey(weekStart(of: day))
      case .monthly:
        return calendar.component(.year, from: day) * 100 + calendar.component(.month, from: day)
      case .yearly: return calendar.component(.year, from: day)
      @unknown default: return dayKey(day)
      }
    }

    /// The first day of the week (per WKST) containing `day`, at its time.
    private func weekStart(of day: Date) -> Date {
      let back = (calendar.component(.weekday, from: day) - weekStart + 7) % 7
      return calendar.date(byAdding: .day, value: -back, to: day) ?? day
    }

    private func periodDays(_ day: Date) -> Set<Int> {
      switch frequency {
      case .daily: return passesDailyFilters(day) ? [dayKey(day)] : []
      case .weekly: return weekDays(day)
      case .monthly: return inByMonth(day) ? monthDays(day) : []
      case .yearly: return yearDays(day)
      @unknown default: return []
      }
    }

    /// In a DAILY rule every BYxxx part only filters (no ordinals apply).
    private func passesDailyFilters(_ day: Date) -> Bool {
      guard inByMonth(day) else { return false }
      let dom = calendar.component(.day, from: day)
      let length = monthLength(of: day)
      if !byMonthDay.isEmpty && !matchesMonthDay(dom, monthLength: length) { return false }
      let weekday = calendar.component(.weekday, from: day)
      return byDay.isEmpty || byDay.contains { $0.weekday == weekday }
    }

    private func weekDays(_ day: Date) -> Set<Int> {
      let weekdays = byDay.isEmpty ? Set([anchorWeekday]) : Set(byDay.map { $0.weekday })
      var days = Set<Int>()
      var current = weekStart(of: day)
      for _ in 0..<7 {
        if weekdays.contains(calendar.component(.weekday, from: current)) && inByMonth(current) {
          days.insert(dayKey(current))
        }
        guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
        current = next
      }
      return days
    }

    /// The days of `day`'s year the rule generates.
    private func yearDays(_ day: Date) -> Set<Int> {
      let year = calendar.component(.year, from: day)
      // BYDAY on its own: ordinals count within the year ("the 20th
      // Monday"). Once BYMONTH or BYMONTHDAY narrows the set, they count
      // within the month, and the yearly set is the listed months' sets.
      if byMonth.isEmpty && byMonthDay.isEmpty && !byDay.isEmpty {
        guard let first = date(year: year, month: 1, day: 1) else { return [] }
        let yearLength = calendar.range(of: .day, in: .year, for: first)?.count ?? 365
        var days = Set<Int>()
        for doy in 1...yearLength {
          guard let current = calendar.date(byAdding: .day, value: doy - 1, to: first) else { break }
          let nth = Nth(fromStart: (doy - 1) / 7 + 1, fromEnd: -((yearLength - doy) / 7 + 1))
          if matchesByDay(current, nth: nth) { days.insert(dayKey(current)) }
        }
        return days
      }
      let months = byMonth.isEmpty ? [anchorMonth] : byMonth
      var days = Set<Int>()
      for month in months where (1...12).contains(month) {
        guard let inMonth = date(year: year, month: month, day: 1) else { continue }
        days.formUnion(monthDays(inMonth))
      }
      return days
    }

    /// The days of `day`'s month the rule generates.
    private func monthDays(_ day: Date) -> Set<Int> {
      let year = calendar.component(.year, from: day)
      let month = calendar.component(.month, from: day)
      let length = monthLength(of: day)
      var days = Set<Int>()
      for dom in 1...length {
        guard let current = date(year: year, month: month, day: dom) else { continue }
        let nth = Nth(fromStart: (dom - 1) / 7 + 1, fromEnd: -((length - dom) / 7 + 1))
        // Per RFC 5545, BYDAY limits a BYMONTHDAY set and expands otherwise;
        // with neither, the anchor's own day-of-month.
        let included: Bool
        if !byMonthDay.isEmpty {
          included = matchesMonthDay(dom, monthLength: length)
            && (byDay.isEmpty || matchesByDay(current, nth: nth))
        } else if !byDay.isEmpty {
          included = matchesByDay(current, nth: nth)
        } else {
          included = dom == anchorDayOfMonth
        }
        if included { days.insert(dayKey(current)) }
      }
      return days
    }

    private func matchesMonthDay(_ dom: Int, monthLength: Int) -> Bool {
      return byMonthDay.contains { $0 == dom || ($0 < 0 && monthLength + 1 + $0 == dom) }
    }

    /// BYDAY membership: the weekday, and the ordinal when one is given.
    private func matchesByDay(_ day: Date, nth: Nth) -> Bool {
      let weekday = calendar.component(.weekday, from: day)
      return byDay.contains {
        $0.weekday == weekday
          && ($0.ordinal == 0 || $0.ordinal == nth.fromStart || $0.ordinal == nth.fromEnd)
      }
    }

    private func inByMonth(_ day: Date) -> Bool {
      return byMonth.isEmpty || byMonth.contains(calendar.component(.month, from: day))
    }

    private func monthLength(of day: Date) -> Int {
      return calendar.range(of: .day, in: .month, for: day)?.count ?? 31
    }

    /// Noon on the given date: only the day matters for set membership, and
    /// noon sidesteps DST transitions at midnight.
    private func date(year: Int, month: Int, day: Int) -> Date? {
      return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
    }
  }
}
