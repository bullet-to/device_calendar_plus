/// Days of the week for recurrence rules.
enum DayOfWeek {
  monday,
  tuesday,
  wednesday,
  thursday,
  friday,
  saturday,
  sunday;

  /// Converts to RRULE BYDAY format (MO, TU, WE, TH, FR, SA, SU).
  String toRruleDay() {
    return switch (this) {
      DayOfWeek.monday => 'MO',
      DayOfWeek.tuesday => 'TU',
      DayOfWeek.wednesday => 'WE',
      DayOfWeek.thursday => 'TH',
      DayOfWeek.friday => 'FR',
      DayOfWeek.saturday => 'SA',
      DayOfWeek.sunday => 'SU',
    };
  }

  /// Parses a BYDAY code to [DayOfWeek]. Returns null if unrecognized.
  static DayOfWeek? fromRruleDay(String day) {
    return switch (day.toUpperCase()) {
      'MO' => DayOfWeek.monday,
      'TU' => DayOfWeek.tuesday,
      'WE' => DayOfWeek.wednesday,
      'TH' => DayOfWeek.thursday,
      'FR' => DayOfWeek.friday,
      'SA' => DayOfWeek.saturday,
      'SU' => DayOfWeek.sunday,
      _ => null,
    };
  }
}

/// End condition for a recurrence rule.
///
/// Either the recurrence ends after a number of occurrences ([CountEnd]),
/// or on a specific date ([UntilEnd]). These are mutually exclusive per RFC 5545.
sealed class RecurrenceEnd {
  const RecurrenceEnd();
}

/// Recurrence ends after [count] occurrences.
class CountEnd extends RecurrenceEnd {
  final int count;

  const CountEnd(this.count) : assert(count >= 1, 'Count must be at least 1');

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is CountEnd && other.count == count;

  @override
  int get hashCode => count.hashCode;

  @override
  String toString() => 'CountEnd($count)';
}

/// Recurrence ends on or before [until] (inclusive / closed interval).
///
/// This differs from [Event.endDate] which uses an open interval.
/// The [until] value should be in UTC.
class UntilEnd extends RecurrenceEnd {
  final DateTime until;

  const UntilEnd(this.until);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is UntilEnd && other.until == until;

  @override
  int get hashCode => until.hashCode;

  @override
  String toString() => 'UntilEnd($until)';
}

/// Recurrence rule for calendar events (RFC 5545 RRULE subset).
///
/// This models the cross-platform subset of RRULE that both iOS (EKRecurrenceRule)
/// and Android (CalendarContract) support reliably.
///
/// For full RRULE access (e.g. BYHOUR on Android), use [rruleString].
sealed class RecurrenceRule {
  /// Interval between recurrences. Defaults to 1.
  ///
  /// For example, `interval: 2` with [WeeklyRecurrence] means every 2 weeks.
  final int interval;

  /// Optional end condition (count or until date). Null means recurs forever.
  final RecurrenceEnd? end;

  /// Stored raw RRULE string when parsed from a platform event.
  final String? _rawRrule;

  const RecurrenceRule({this.interval = 1, this.end, String? rawRrule})
      : _rawRrule = rawRrule,
        assert(interval >= 1, 'Interval must be at least 1');

  /// The raw RRULE string.
  ///
  /// When parsed from a platform event, this is the original string as returned
  /// by the platform. On Android this is the exact CalendarContract string
  /// (full fidelity). On iOS this is reconstructed from EKRecurrenceRule
  /// (may lose properties like BYHOUR that EventKit doesn't model).
  ///
  /// When constructed in Dart, this is generated from [toRruleString].
  ///
  /// Use this if you need RRULE properties beyond what the typed model exposes.
  String get rruleString => _rawRrule ?? toRruleString();

  /// Serializes this rule to an RRULE string (without the "RRULE:" prefix).
  String toRruleString();

  /// Parses an RRULE string into a typed [RecurrenceRule].
  ///
  /// Accepts strings with or without the "RRULE:" prefix.
  /// Returns null if the string is unparseable or uses an unsupported frequency.
  static RecurrenceRule? fromRruleString(String rrule) {
    return _RruleParser.parse(rrule);
  }

  /// Builds the common RRULE parts (end condition).
  String _endParts() {
    if (end == null) return '';
    return switch (end!) {
      CountEnd(:final count) => ';COUNT=$count',
      UntilEnd(:final until) => ';UNTIL=${_formatRruleDate(until)}',
    };
  }

  /// Formats a DateTime as an RRULE date string.
  ///
  /// If the time is midnight (00:00:00), emits date-only: `YYYYMMDD`.
  /// Otherwise emits date-time in UTC: `YYYYMMDDTHHMMSSZ`.
  static String _formatRruleDate(DateTime dt) {
    final utc = dt.toUtc();
    final date =
        '${utc.year.toString().padLeft(4, '0')}${utc.month.toString().padLeft(2, '0')}${utc.day.toString().padLeft(2, '0')}';
    if (utc.hour == 0 && utc.minute == 0 && utc.second == 0) {
      return date;
    }
    return '${date}T${utc.hour.toString().padLeft(2, '0')}${utc.minute.toString().padLeft(2, '0')}${utc.second.toString().padLeft(2, '0')}Z';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RecurrenceRule &&
        other.runtimeType == runtimeType &&
        other.interval == interval &&
        other.end == end;
  }

  @override
  int get hashCode => Object.hash(runtimeType, interval, end);
}

/// Event repeats every N days.
class DailyRecurrence extends RecurrenceRule {
  const DailyRecurrence({super.interval, super.end, super.rawRrule});

  @override
  String toRruleString() {
    final buf = StringBuffer('FREQ=DAILY');
    if (interval > 1) buf.write(';INTERVAL=$interval');
    buf.write(_endParts());
    return buf.toString();
  }

  @override
  String toString() => 'DailyRecurrence(interval: $interval, end: $end)';
}

/// Event repeats every N weeks, optionally on specific days.
class WeeklyRecurrence extends RecurrenceRule {
  /// Days of the week on which the event recurs.
  ///
  /// If null, defaults to the day of the event's start date (platform behavior).
  final List<DayOfWeek>? daysOfWeek;

  /// The day the week starts on (WKST).
  ///
  /// Affects how BYDAY is calculated for weekly recurrences.
  /// Defaults to Monday per RFC 5545 when null.
  ///
  /// **Note:** iOS can read this from events but cannot set it when creating
  /// events (EKRecurrenceRule does not expose it in its initializer).
  /// The value still round-trips via [rruleString].
  final DayOfWeek? wkst;

  const WeeklyRecurrence({
    this.daysOfWeek,
    this.wkst,
    super.interval,
    super.end,
    super.rawRrule,
  });

  @override
  String toRruleString() {
    final buf = StringBuffer('FREQ=WEEKLY');
    if (interval > 1) buf.write(';INTERVAL=$interval');
    if (daysOfWeek != null && daysOfWeek!.isNotEmpty) {
      buf.write(';BYDAY=${daysOfWeek!.map((d) => d.toRruleDay()).join(',')}');
    }
    buf.write(_endParts());
    if (wkst != null) buf.write(';WKST=${wkst!.toRruleDay()}');
    return buf.toString();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WeeklyRecurrence &&
        other.interval == interval &&
        other.end == end &&
        other.wkst == wkst &&
        _listEquals(other.daysOfWeek, daysOfWeek);
  }

  @override
  int get hashCode => Object.hash(
        super.hashCode,
        wkst,
        daysOfWeek != null ? Object.hashAll(daysOfWeek!) : null,
      );

  @override
  String toString() =>
      'WeeklyRecurrence(interval: $interval, daysOfWeek: $daysOfWeek, wkst: $wkst, end: $end)';
}

/// Event repeats every N months.
///
/// ```dart
/// MonthlyRecurrence.byDayOfMonth()                        // same day as event start
/// MonthlyRecurrence.byDayOfMonth(daysOfMonth: [1, 15])    // 1st and 15th
/// MonthlyRecurrence.byWeekday(daysOfWeek: [               // 2nd Tuesday
///   RecurrenceDay(DayOfWeek.tuesday, position: 2),
/// ])
/// ```
sealed class MonthlyRecurrence extends RecurrenceRule {
  /// Filters the result set to specific positions (BYSETPOS).
  ///
  /// Used to select specific occurrences from the set generated by BYDAY
  /// or BYMONTHDAY. For example, "last weekday of the month":
  /// ```dart
  /// MonthlyRecurrence.byWeekday(
  ///   daysOfWeek: [
  ///     RecurrenceDay(DayOfWeek.monday),
  ///     RecurrenceDay(DayOfWeek.tuesday),
  ///     RecurrenceDay(DayOfWeek.wednesday),
  ///     RecurrenceDay(DayOfWeek.thursday),
  ///     RecurrenceDay(DayOfWeek.friday),
  ///   ],
  ///   setPositions: [-1],
  /// )
  /// ```
  ///
  /// Positive values count from the start, negative from the end.
  /// Range: -366 to 366 (non-zero).
  final List<int>? setPositions;

  const MonthlyRecurrence._({
    this.setPositions,
    super.interval,
    super.end,
    super.rawRrule,
  });

  /// Creates a monthly recurrence on specific days of the month (BYMONTHDAY).
  ///
  /// If [daysOfMonth] is null, the event recurs on the same day as the start date.
  factory MonthlyRecurrence.byDayOfMonth({
    List<int>? daysOfMonth,
    List<int>? setPositions,
    int interval,
    RecurrenceEnd? end,
    String? rawRrule,
  }) = MonthlyByDate;

  /// Creates a monthly recurrence on specific weekdays (BYDAY).
  ///
  /// Use [RecurrenceDay] with [position] for patterns like "2nd Tuesday"
  /// or without for "every Tuesday in the month".
  factory MonthlyRecurrence.byWeekday({
    required List<RecurrenceDay> daysOfWeek,
    List<int>? setPositions,
    int interval,
    RecurrenceEnd? end,
    String? rawRrule,
  }) = MonthlyByWeekday;

  /// Serializes BYSETPOS to RRULE format.
  String _setPosParts() {
    if (setPositions == null || setPositions!.isEmpty) return '';
    return ';BYSETPOS=${setPositions!.join(',')}';
  }
}

/// Monthly recurrence on specific days of the month (BYMONTHDAY).
class MonthlyByDate extends MonthlyRecurrence {
  /// Days of the month (1-31) on which the event recurs.
  ///
  /// If null, the event recurs on the same day as the start date.
  final List<int>? daysOfMonth;

  MonthlyByDate({
    this.daysOfMonth,
    super.setPositions,
    super.interval,
    super.end,
    super.rawRrule,
  })  : assert(
          daysOfMonth == null || daysOfMonth.every((d) => d >= 1 && d <= 31),
          'daysOfMonth values must be between 1 and 31',
        ),
        super._();

  @override
  String toRruleString() {
    final buf = StringBuffer('FREQ=MONTHLY');
    if (interval > 1) buf.write(';INTERVAL=$interval');
    if (daysOfMonth != null && daysOfMonth!.isNotEmpty) {
      buf.write(';BYMONTHDAY=${daysOfMonth!.join(',')}');
    }
    buf.write(_setPosParts());
    buf.write(_endParts());
    return buf.toString();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MonthlyByDate &&
        other.interval == interval &&
        other.end == end &&
        _listEquals(other.daysOfMonth, daysOfMonth) &&
        _listEquals(other.setPositions, setPositions);
  }

  @override
  int get hashCode => Object.hash(
        super.hashCode,
        daysOfMonth != null ? Object.hashAll(daysOfMonth!) : null,
        setPositions != null ? Object.hashAll(setPositions!) : null,
      );

  @override
  String toString() =>
      'MonthlyByDate(interval: $interval, daysOfMonth: $daysOfMonth, setPositions: $setPositions, end: $end)';
}

/// Monthly recurrence on specific weekdays (BYDAY).
class MonthlyByWeekday extends MonthlyRecurrence {
  /// Day-of-week rules, optionally with position (e.g., 2nd Tuesday, last Friday).
  final List<RecurrenceDay> daysOfWeek;

  const MonthlyByWeekday({
    required this.daysOfWeek,
    super.setPositions,
    super.interval,
    super.end,
    super.rawRrule,
  }) : super._();

  @override
  String toRruleString() {
    final buf = StringBuffer('FREQ=MONTHLY');
    if (interval > 1) buf.write(';INTERVAL=$interval');
    if (daysOfWeek.isNotEmpty) {
      buf.write(';BYDAY=${daysOfWeek.map((d) => d.toRruleByDay()).join(',')}');
    }
    buf.write(_setPosParts());
    buf.write(_endParts());
    return buf.toString();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MonthlyByWeekday &&
        other.interval == interval &&
        other.end == end &&
        _listEquals(other.daysOfWeek, daysOfWeek) &&
        _listEquals(other.setPositions, setPositions);
  }

  @override
  int get hashCode => Object.hash(
        super.hashCode,
        Object.hashAll(daysOfWeek),
        setPositions != null ? Object.hashAll(setPositions!) : null,
      );

  @override
  String toString() =>
      'MonthlyByWeekday(interval: $interval, daysOfWeek: $daysOfWeek, setPositions: $setPositions, end: $end)';
}

/// Event repeats every N years.
///
/// ```dart
/// YearlyRecurrence.byDayOfMonth()                                    // same date as event start
/// YearlyRecurrence.byDayOfMonth(months: [12], daysOfMonth: [25])     // Christmas
/// YearlyRecurrence.byDayOfMonth(months: [6, 12], daysOfMonth: [15])  // 15th of June and December
/// YearlyRecurrence.byWeekday(                                        // last Monday of May
///   months: [5],
///   daysOfWeek: [RecurrenceDay(DayOfWeek.monday, position: -1)],
/// )
/// ```
sealed class YearlyRecurrence extends RecurrenceRule {
  /// Filters the result set to specific positions (BYSETPOS).
  ///
  /// See [MonthlyRecurrence.setPositions] for details.
  final List<int>? setPositions;

  const YearlyRecurrence._({
    this.setPositions,
    super.interval,
    super.end,
    super.rawRrule,
  });

  /// Creates a yearly recurrence on specific months and days of month (BYMONTH + BYMONTHDAY).
  ///
  /// If both are null, the event recurs on the same date as the start date.
  factory YearlyRecurrence.byDayOfMonth({
    List<int>? months,
    List<int>? daysOfMonth,
    List<int>? setPositions,
    int interval,
    RecurrenceEnd? end,
    String? rawRrule,
  }) = YearlyByDate;

  /// Creates a yearly recurrence on specific weekdays within months (BYMONTH + BYDAY).
  ///
  /// Use [RecurrenceDay] with [position] for patterns like "last Monday of May".
  factory YearlyRecurrence.byWeekday({
    List<int>? months,
    required List<RecurrenceDay> daysOfWeek,
    List<int>? setPositions,
    int interval,
    RecurrenceEnd? end,
    String? rawRrule,
  }) = YearlyByWeekday;

  /// Serializes BYSETPOS to RRULE format.
  String _setPosParts() {
    if (setPositions == null || setPositions!.isEmpty) return '';
    return ';BYSETPOS=${setPositions!.join(',')}';
  }
}

/// Yearly recurrence on specific months and days of month (BYMONTH + BYMONTHDAY).
class YearlyByDate extends YearlyRecurrence {
  /// Months of the year (1-12). If null, uses the event's start date month.
  final List<int>? months;

  /// Days of the month (1-31). If null, uses the event's start date day.
  final List<int>? daysOfMonth;

  YearlyByDate({
    this.months,
    this.daysOfMonth,
    super.setPositions,
    super.interval,
    super.end,
    super.rawRrule,
  })  : assert(
          months == null || months.every((m) => m >= 1 && m <= 12),
          'months values must be between 1 and 12',
        ),
        assert(
          daysOfMonth == null || daysOfMonth.every((d) => d >= 1 && d <= 31),
          'daysOfMonth values must be between 1 and 31',
        ),
        super._();

  @override
  String toRruleString() {
    final buf = StringBuffer('FREQ=YEARLY');
    if (interval > 1) buf.write(';INTERVAL=$interval');
    if (months != null && months!.isNotEmpty) {
      buf.write(';BYMONTH=${months!.join(',')}');
    }
    if (daysOfMonth != null && daysOfMonth!.isNotEmpty) {
      buf.write(';BYMONTHDAY=${daysOfMonth!.join(',')}');
    }
    buf.write(_setPosParts());
    buf.write(_endParts());
    return buf.toString();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is YearlyByDate &&
        other.interval == interval &&
        other.end == end &&
        _listEquals(other.months, months) &&
        _listEquals(other.daysOfMonth, daysOfMonth) &&
        _listEquals(other.setPositions, setPositions);
  }

  @override
  int get hashCode => Object.hash(
        super.hashCode,
        months != null ? Object.hashAll(months!) : null,
        daysOfMonth != null ? Object.hashAll(daysOfMonth!) : null,
        setPositions != null ? Object.hashAll(setPositions!) : null,
      );

  @override
  String toString() =>
      'YearlyByDate(interval: $interval, months: $months, daysOfMonth: $daysOfMonth, setPositions: $setPositions, end: $end)';
}

/// Yearly recurrence on specific weekdays within months (BYMONTH + BYDAY).
class YearlyByWeekday extends YearlyRecurrence {
  /// Months of the year (1-12). If null, uses the event's start date month.
  final List<int>? months;

  /// Day-of-week rules, optionally with position (e.g., last Monday of May).
  final List<RecurrenceDay> daysOfWeek;

  YearlyByWeekday({
    this.months,
    required this.daysOfWeek,
    super.setPositions,
    super.interval,
    super.end,
    super.rawRrule,
  })  : assert(
          months == null || months.every((m) => m >= 1 && m <= 12),
          'months values must be between 1 and 12',
        ),
        super._();

  @override
  String toRruleString() {
    final buf = StringBuffer('FREQ=YEARLY');
    if (interval > 1) buf.write(';INTERVAL=$interval');
    if (months != null && months!.isNotEmpty) {
      buf.write(';BYMONTH=${months!.join(',')}');
    }
    if (daysOfWeek.isNotEmpty) {
      buf.write(';BYDAY=${daysOfWeek.map((d) => d.toRruleByDay()).join(',')}');
    }
    buf.write(_setPosParts());
    buf.write(_endParts());
    return buf.toString();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is YearlyByWeekday &&
        other.interval == interval &&
        other.end == end &&
        _listEquals(other.months, months) &&
        _listEquals(other.daysOfWeek, daysOfWeek) &&
        _listEquals(other.setPositions, setPositions);
  }

  @override
  int get hashCode => Object.hash(
        super.hashCode,
        months != null ? Object.hashAll(months!) : null,
        Object.hashAll(daysOfWeek),
        setPositions != null ? Object.hashAll(setPositions!) : null,
      );

  @override
  String toString() =>
      'YearlyByWeekday(interval: $interval, months: $months, daysOfWeek: $daysOfWeek, setPositions: $setPositions, end: $end)';
}

/// A day of the week with an optional position for recurring events.
///
/// Used in [MonthlyRecurrence] and [YearlyRecurrence] to express BYDAY patterns.
///
/// Without [position]: "every Tuesday" (`BYDAY=TU`).
/// With [position]: "2nd Tuesday" (`BYDAY=2TU`) or "last Friday" (`BYDAY=-1FR`).
///
/// Maps to RFC 5545 BYDAY and iOS `EKRecurrenceDayOfWeek`.
class RecurrenceDay {
  /// The day of the week.
  final DayOfWeek day;

  /// Which occurrence of this weekday within the recurrence period.
  ///
  /// The scope depends on the frequency:
  /// - For [MonthlyRecurrence]: Nth occurrence within the **month**
  ///   (e.g., `position: 2` = 2nd Tuesday of the month).
  /// - For [YearlyRecurrence]: Nth occurrence within the **year**
  ///   (e.g., `position: 2` = 2nd Tuesday of the year).
  ///
  /// Positive values count from the start (1 = first, 2 = second, etc.).
  /// Negative values count from the end (-1 = last, -2 = second-to-last).
  /// Null means every occurrence of the day in the period.
  ///
  /// Range: -53 to 53 (non-zero).
  final int? position;

  const RecurrenceDay(this.day, {this.position})
      : assert(
          position == null ||
              (position >= -53 && position <= 53 && position != 0),
          'position must be between -53 and 53 (non-zero)',
        );

  /// Serializes to RRULE BYDAY format (e.g., `TU`, `2TU`, `-1FR`).
  String toRruleByDay() =>
      position != null ? '$position${day.toRruleDay()}' : day.toRruleDay();

  /// Parses a BYDAY value, with or without numeric prefix.
  /// Returns null if the format is invalid.
  static RecurrenceDay? fromRruleByDay(String byDay) {
    final trimmed = byDay.trim().toUpperCase();

    // Try positional format first (e.g., 2TU, -1FR)
    final match = RegExp(r'^(-?\d+)([A-Z]{2})$').firstMatch(trimmed);
    if (match != null) {
      final pos = int.tryParse(match.group(1)!);
      final day = DayOfWeek.fromRruleDay(match.group(2)!);
      if (pos == null || pos == 0 || day == null) return null;
      return RecurrenceDay(day, position: pos);
    }

    // Plain day code (e.g., TU)
    final day = DayOfWeek.fromRruleDay(trimmed);
    if (day == null) return null;
    return RecurrenceDay(day);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecurrenceDay && other.day == day && other.position == position;

  @override
  int get hashCode => Object.hash(day, position);

  @override
  String toString() => position != null
      ? 'RecurrenceDay($day, position: $position)'
      : 'RecurrenceDay($day)';
}

// -- Private helpers --

bool _listEquals<T>(List<T>? a, List<T>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class _RruleParser {
  static RecurrenceRule? parse(String rrule) {
    try {
      final ruleString =
          rrule.startsWith('RRULE:') ? rrule.substring(6) : rrule;
      final parts = ruleString.split(';');
      final params = <String, String>{};

      for (final part in parts) {
        final idx = part.indexOf('=');
        if (idx > 0) {
          params[part.substring(0, idx).toUpperCase()] =
              part.substring(idx + 1);
        }
      }

      final freqStr = params['FREQ']?.toUpperCase();
      if (freqStr == null) return null;

      final interval = int.tryParse(params['INTERVAL'] ?? '1') ?? 1;

      // Parse end condition
      RecurrenceEnd? end;
      final countStr = params['COUNT'];
      final untilStr = params['UNTIL'];
      if (countStr != null) {
        final count = int.tryParse(countStr);
        if (count != null && count >= 1) end = CountEnd(count);
      } else if (untilStr != null) {
        final dt = _parseRruleDate(untilStr);
        if (dt != null) end = UntilEnd(dt);
      }

      return switch (freqStr) {
        'DAILY' => DailyRecurrence(
            interval: interval,
            end: end,
            rawRrule: rrule,
          ),
        'WEEKLY' => WeeklyRecurrence(
            interval: interval,
            daysOfWeek: _parseDaysOfWeek(params['BYDAY']),
            wkst: params['WKST'] != null
                ? DayOfWeek.fromRruleDay(params['WKST']!)
                : null,
            end: end,
            rawRrule: rrule,
          ),
        'MONTHLY' => _parseMonthly(params, interval, end, rrule),
        'YEARLY' => _parseYearly(params, interval, end, rrule),
        _ => null, // Unsupported frequency (MINUTELY, HOURLY, etc.)
      };
    } catch (_) {
      return null;
    }
  }

  static List<DayOfWeek>? _parseDaysOfWeek(String? byDay) {
    if (byDay == null || byDay.isEmpty) return null;
    final days = byDay
        .split(',')
        .map((d) => DayOfWeek.fromRruleDay(d.trim()))
        .whereType<DayOfWeek>()
        .toList();
    return days.isEmpty ? null : days;
  }

  static List<RecurrenceDay>? _parseRecurrenceDays(String? byDay) {
    if (byDay == null || byDay.isEmpty) return null;
    final days = byDay
        .split(',')
        .map((d) => RecurrenceDay.fromRruleByDay(d.trim()))
        .whereType<RecurrenceDay>()
        .toList();
    return days.isEmpty ? null : days;
  }

  static List<int>? _parseDaysOfMonth(String? byMonthDay) {
    if (byMonthDay == null || byMonthDay.isEmpty) return null;
    final days = byMonthDay
        .split(',')
        .map((d) => int.tryParse(d.trim()))
        .whereType<int>()
        .toList();
    return days.isEmpty ? null : days;
  }

  static MonthlyRecurrence _parseMonthly(
    Map<String, String> params,
    int interval,
    RecurrenceEnd? end,
    String rrule,
  ) {
    final setPositions = _parseIntList(params['BYSETPOS']);
    final byDay = _parseRecurrenceDays(params['BYDAY']);
    if (byDay != null) {
      return MonthlyRecurrence.byWeekday(
        daysOfWeek: byDay,
        setPositions: setPositions,
        interval: interval,
        end: end,
        rawRrule: rrule,
      );
    }
    return MonthlyRecurrence.byDayOfMonth(
      daysOfMonth: _parseDaysOfMonth(params['BYMONTHDAY']),
      setPositions: setPositions,
      interval: interval,
      end: end,
      rawRrule: rrule,
    );
  }

  static List<int>? _parseIntList(String? value) {
    if (value == null || value.isEmpty) return null;
    final ints = value
        .split(',')
        .map((d) => int.tryParse(d.trim()))
        .whereType<int>()
        .toList();
    return ints.isEmpty ? null : ints;
  }

  static YearlyRecurrence _parseYearly(
    Map<String, String> params,
    int interval,
    RecurrenceEnd? end,
    String rrule,
  ) {
    final months = _parseIntList(params['BYMONTH']);
    final setPositions = _parseIntList(params['BYSETPOS']);
    final byDay = _parseRecurrenceDays(params['BYDAY']);
    if (byDay != null) {
      return YearlyRecurrence.byWeekday(
        months: months,
        daysOfWeek: byDay,
        setPositions: setPositions,
        interval: interval,
        end: end,
        rawRrule: rrule,
      );
    }
    return YearlyRecurrence.byDayOfMonth(
      months: months,
      daysOfMonth: _parseIntList(params['BYMONTHDAY']),
      setPositions: setPositions,
      interval: interval,
      end: end,
      rawRrule: rrule,
    );
  }

  /// Parses RRULE date string: `YYYYMMDD` or `YYYYMMDDTHHMMSSZ`.
  static DateTime? _parseRruleDate(String dateStr) {
    try {
      final clean = dateStr.replaceAll('Z', '');
      if (clean.length < 8) return null;

      final year = int.parse(clean.substring(0, 4));
      final month = int.parse(clean.substring(4, 6));
      final day = int.parse(clean.substring(6, 8));

      if (clean.length >= 15 && clean[8] == 'T') {
        final hour = int.parse(clean.substring(9, 11));
        final minute = int.parse(clean.substring(11, 13));
        final second = int.parse(clean.substring(13, 15));
        return DateTime.utc(year, month, day, hour, minute, second);
      }

      return DateTime.utc(year, month, day);
    } catch (_) {
      return null;
    }
  }
}
