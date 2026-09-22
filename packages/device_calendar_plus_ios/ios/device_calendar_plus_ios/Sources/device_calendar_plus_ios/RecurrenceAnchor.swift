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
///
/// Covers the RRULE subset the plugin models: FREQ, BYDAY (with ordinals),
/// BYMONTHDAY, BYMONTH, and BYSETPOS on monthly and yearly rules. INTERVAL
/// and WKST don't affect which days a rule can generate from a given anchor
/// (the anchor itself fixes the interval's phase), and a BYSETPOS on a daily
/// or weekly rule is outside the modelled subset, so all three are ignored.
enum RecurrenceAnchor {
  /// Five years: enough for a rule pinned to 29 February.
  private static let maxLookaheadDays = 5 * 366

  /// The first instant on or after `from` whose calendar day (in `timeZone`)
  /// `rule` generates, at `from`'s wall-clock time. Parts the rule leaves
  /// implicit (no BYDAY, BYMONTHDAY or BYMONTH) come from `from` itself, as
  /// they would from the start date — so a rule that already fits its anchor
  /// returns `from` unchanged. Nil when the rule generates nothing within
  /// five years, so the caller can refuse rather than anchor the series
  /// off-rule.
  static func firstMatch(
    of rule: EKRecurrenceRule,
    onOrAfter from: Date,
    timeZone: TimeZone
  ) -> Date? {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let matcher = Matcher(
      rule: Rule(rule).impliedBy(anchor: from, calendar: calendar), calendar: calendar
    )
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

  /// The parts of an `EKRecurrenceRule` that decide which days it generates.
  private struct Rule {
    let frequency: EKRecurrenceFrequency
    var byDay: [ByDay]
    var byMonthDay: [Int]
    var byMonth: [Int]
    let bySetPos: [Int]

    /// The modelled parts of `rule`, as written.
    init(_ rule: EKRecurrenceRule) {
      frequency = rule.frequency
      byDay = (rule.daysOfTheWeek ?? []).map {
        ByDay(ordinal: $0.weekNumber, weekday: $0.dayOfTheWeek.rawValue)
      }
      byMonthDay = (rule.daysOfTheMonth ?? []).map { $0.intValue }
      byMonth = (rule.monthsOfTheYear ?? []).map { $0.intValue }
      bySetPos = (rule.setPositions ?? []).map { $0.intValue }
    }

    /// Fills in the parts the rule leaves implicit from `anchor`, as RFC
    /// 5545 fills them from DTSTART: a WEEKLY rule with no BYDAY runs on the
    /// anchor's weekday, a MONTHLY rule with neither BYDAY nor BYMONTHDAY on
    /// its day of the month, and a YEARLY rule likewise, in the anchor's
    /// month unless BYMONTH lists its own. The one YEARLY form left alone is
    /// BYDAY on its own, whose ordinals count within the year. A DAILY rule
    /// has nothing implicit: each of its parts only filters.
    func impliedBy(anchor: Date, calendar: Calendar) -> Rule {
      let weekday = calendar.component(.weekday, from: anchor)
      let dayOfMonth = [calendar.component(.day, from: anchor)]
      let month = [calendar.component(.month, from: anchor)]
      let ownDay = byDay.isEmpty && byMonthDay.isEmpty
      var implied = self
      switch frequency {
      case .daily:
        break
      case .weekly:
        if byDay.isEmpty { implied.byDay = [ByDay(ordinal: 0, weekday: weekday)] }
        // A WEEKLY rule ignores BYMONTHDAY.
        implied.byMonthDay = []
      case .monthly:
        if ownDay { implied.byMonthDay = dayOfMonth }
      case .yearly:
        if byMonth.isEmpty && byMonthDay.isEmpty && !byDay.isEmpty { break }
        if byMonth.isEmpty { implied.byMonth = month }
        if ownDay { implied.byMonthDay = dayOfMonth }
      @unknown default:
        break
      }
      return implied
    }
  }

  /// Decides whether a day is in the rule's set for the period containing
  /// it. A monthly or yearly period's set is built once and cached, since
  /// `firstMatch` visits its days in order; the rule must already have had
  /// its implicit parts filled in (`Rule.impliedBy`).
  private final class Matcher {
    private let calendar: Calendar
    private let frequency: EKRecurrenceFrequency
    private let byDay: [ByDay]
    private let byMonthDay: [Int]
    private let byMonth: [Int]
    private let bySetPos: [Int]
    private var cachedPeriod: Int?
    private var cachedDays: Set<Int> = []

    init(rule: Rule, calendar: Calendar) {
      self.calendar = calendar
      frequency = rule.frequency
      byDay = rule.byDay
      byMonthDay = rule.byMonthDay
      byMonth = rule.byMonth
      bySetPos = rule.bySetPos
    }

    func generates(_ day: Date) -> Bool {
      switch frequency {
      // Daily and weekly rules are decided a day at a time: whether a day is
      // in a weekly set doesn't depend on where the week starts.
      case .daily, .weekly:
        return dayPasses(day)
      case .monthly, .yearly:
        let period = periodKey(day)
        if period != cachedPeriod {
          cachedPeriod = period
          cachedDays = periodDays(day)
        }
        return cachedDays.contains(dayKey(day))
      @unknown default:
        return false
      }
    }

    /// BYSETPOS keeps only the listed positions of a month's or year's set
    /// (1-based; negative from the end).
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
      if frequency == .monthly {
        return calendar.component(.year, from: day) * 100 + calendar.component(.month, from: day)
      }
      return calendar.component(.year, from: day)
    }

    private func periodDays(_ day: Date) -> Set<Int> {
      if frequency == .monthly {
        return inByMonth(day) ? applySetPos(monthDays(day)) : []
      }
      return applySetPos(yearDays(day))
    }

    /// In a DAILY or WEEKLY rule every BYxxx part only filters (no ordinals
    /// apply).
    private func dayPasses(_ day: Date) -> Bool {
      guard inByMonth(day) else { return false }
      let dom = calendar.component(.day, from: day)
      let length = monthLength(of: day)
      if !byMonthDay.isEmpty && !matchesMonthDay(dom, monthLength: length) { return false }
      let weekday = calendar.component(.weekday, from: day)
      return byDay.isEmpty || byDay.contains { $0.weekday == weekday }
    }

    /// The days of `day`'s year the rule generates.
    private func yearDays(_ day: Date) -> Set<Int> {
      let year = calendar.component(.year, from: day)
      // BYDAY on its own (the one form `impliedBy` leaves without a
      // BYMONTH): ordinals count within the year ("the 20th Monday").
      // Otherwise they count within the month, and the yearly set is the
      // listed months' sets.
      if byMonth.isEmpty {
        guard let first = date(year: year, month: 1, day: 1) else { return [] }
        let yearLength = calendar.range(of: .day, in: .year, for: first)?.count ?? 365
        var days = Set<Int>()
        for doy in 1...yearLength {
          guard let current = calendar.date(byAdding: .day, value: doy - 1, to: first) else { break }
          if matchesByDay(current, nth: nthInPeriod(doy, periodLength: yearLength)) {
            days.insert(dayKey(current))
          }
        }
        return days
      }
      var days = Set<Int>()
      for month in byMonth where (1...12).contains(month) {
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
        let nth = nthInPeriod(dom, periodLength: length)
        // Per RFC 5545, BYDAY limits a BYMONTHDAY set and expands otherwise
        // (`impliedBy` guarantees one of the two is present).
        let included: Bool
        if !byMonthDay.isEmpty {
          included = matchesMonthDay(dom, monthLength: length)
            && (byDay.isEmpty || matchesByDay(current, nth: nth))
        } else {
          included = matchesByDay(current, nth: nth)
        }
        if included { days.insert(dayKey(current)) }
      }
      return days
    }

    /// The ordinal of the day at `position` (1-based) in a period of
    /// `periodLength` days: which length is passed decides whether "2MO"
    /// counts within the month or within the year.
    private func nthInPeriod(_ position: Int, periodLength: Int) -> Nth {
      return Nth(fromStart: (position - 1) / 7 + 1, fromEnd: -((periodLength - position) / 7 + 1))
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
