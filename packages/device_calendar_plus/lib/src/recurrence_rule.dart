/// Frequency of event recurrence.
enum RecurrenceFrequency {
  /// Event repeats every N days.
  daily,

  /// Event repeats every N weeks on specific days.
  weekly,

  /// Event repeats every N months on a specific day.
  monthly,

  /// Event repeats every N years on a specific date.
  yearly,
}

/// Days of the week for weekly recurrence.
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
    switch (this) {
      case DayOfWeek.monday:
        return 'MO';
      case DayOfWeek.tuesday:
        return 'TU';
      case DayOfWeek.wednesday:
        return 'WE';
      case DayOfWeek.thursday:
        return 'TH';
      case DayOfWeek.friday:
        return 'FR';
      case DayOfWeek.saturday:
        return 'SA';
      case DayOfWeek.sunday:
        return 'SU';
    }
  }

  /// Parses a BYDAY code to DayOfWeek.
  static DayOfWeek? fromRruleDay(String day) {
    switch (day.toUpperCase()) {
      case 'MO':
        return DayOfWeek.monday;
      case 'TU':
        return DayOfWeek.tuesday;
      case 'WE':
        return DayOfWeek.wednesday;
      case 'TH':
        return DayOfWeek.thursday;
      case 'FR':
        return DayOfWeek.friday;
      case 'SA':
        return DayOfWeek.saturday;
      case 'SU':
        return DayOfWeek.sunday;
      default:
        return null;
    }
  }
}

/// Represents a recurrence rule for calendar events.
///
/// This class follows the iCalendar RRULE specification (RFC 5545).
///
/// Example usage:
/// ```dart
/// // Daily event
/// final dailyRule = RecurrenceRule(
///   frequency: RecurrenceFrequency.daily,
/// );
///
/// // Weekly on Monday and Wednesday
/// final weeklyRule = RecurrenceRule(
///   frequency: RecurrenceFrequency.weekly,
///   daysOfWeek: [DayOfWeek.monday, DayOfWeek.wednesday],
/// );
///
/// // Monthly on the 15th, ending after 12 occurrences
/// final monthlyRule = RecurrenceRule(
///   frequency: RecurrenceFrequency.monthly,
///   dayOfMonth: 15,
///   occurrences: 12,
/// );
///
/// // Yearly on the same date, ending on a specific date
/// final yearlyRule = RecurrenceRule(
///   frequency: RecurrenceFrequency.yearly,
///   endDate: DateTime(2025, 12, 31),
/// );
/// ```
class RecurrenceRule {
  /// The frequency of recurrence.
  final RecurrenceFrequency frequency;

  /// The interval between occurrences.
  ///
  /// For example, `interval: 2` with `frequency: weekly` means every 2 weeks.
  /// Defaults to 1.
  final int interval;

  /// Days of the week for weekly recurrence.
  ///
  /// Only used when [frequency] is [RecurrenceFrequency.weekly].
  /// If null for weekly frequency, defaults to the day of the week of the event's start date.
  final List<DayOfWeek>? daysOfWeek;

  /// Day of the month for monthly recurrence (1-31).
  ///
  /// Only used when [frequency] is [RecurrenceFrequency.monthly].
  /// If null for monthly frequency, defaults to the day of month of the event's start date.
  final int? dayOfMonth;

  /// Maximum number of occurrences.
  ///
  /// Mutually exclusive with [endDate]. If both are null, the event recurs indefinitely.
  final int? occurrences;

  /// End date for recurrence (inclusive).
  ///
  /// Mutually exclusive with [occurrences]. If both are null, the event recurs indefinitely.
  final DateTime? endDate;

  /// Creates a recurrence rule.
  ///
  /// [frequency] is required and specifies how often the event repeats.
  /// [interval] defaults to 1 (e.g., every week, every month).
  /// [occurrences] and [endDate] are mutually exclusive - only one can be set.
  RecurrenceRule({
    required this.frequency,
    this.interval = 1,
    this.daysOfWeek,
    this.dayOfMonth,
    this.occurrences,
    this.endDate,
  })  : assert(interval >= 1, 'Interval must be at least 1'),
        assert(
          occurrences == null || endDate == null,
          'Cannot specify both occurrences and endDate',
        ),
        assert(
          dayOfMonth == null || (dayOfMonth >= 1 && dayOfMonth <= 31),
          'dayOfMonth must be between 1 and 31',
        );

  /// Converts this recurrence rule to an RRULE string.
  ///
  /// Example output: `FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE,FR;COUNT=10`
  String toRruleString() {
    final parts = <String>[];

    // Frequency
    parts.add('FREQ=${frequency.name.toUpperCase()}');

    // Interval (only if greater than 1)
    if (interval > 1) {
      parts.add('INTERVAL=$interval');
    }

    // Days of week (for weekly recurrence)
    if (daysOfWeek != null && daysOfWeek!.isNotEmpty) {
      final days = daysOfWeek!.map((d) => d.toRruleDay()).join(',');
      parts.add('BYDAY=$days');
    }

    // Day of month (for monthly recurrence)
    if (dayOfMonth != null) {
      parts.add('BYMONTHDAY=$dayOfMonth');
    }

    // End condition
    if (occurrences != null) {
      parts.add('COUNT=$occurrences');
    } else if (endDate != null) {
      // Format: YYYYMMDD or YYYYMMDDTHHMMSSZ
      final date = endDate!.toUtc();
      final dateStr =
          '${date.year.toString().padLeft(4, '0')}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}T235959Z';
      parts.add('UNTIL=$dateStr');
    }

    return parts.join(';');
  }

  /// Parses an RRULE string into a RecurrenceRule.
  ///
  /// Returns null if the string is invalid or cannot be parsed.
  ///
  /// Example input: `FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;COUNT=10`
  static RecurrenceRule? fromRruleString(String rrule) {
    try {
      // Remove RRULE: prefix if present
      final ruleString =
          rrule.startsWith('RRULE:') ? rrule.substring(6) : rrule;

      final parts = ruleString.split(';');
      final Map<String, String> params = {};

      for (final part in parts) {
        final keyValue = part.split('=');
        if (keyValue.length == 2) {
          params[keyValue[0].toUpperCase()] = keyValue[1];
        }
      }

      // Parse frequency (required)
      final freqStr = params['FREQ'];
      if (freqStr == null) return null;

      final frequency =
          RecurrenceFrequency.values.cast<RecurrenceFrequency?>().firstWhere(
                (f) => f?.name.toUpperCase() == freqStr.toUpperCase(),
                orElse: () => null,
              );
      if (frequency == null) return null;

      // Parse interval
      final interval = int.tryParse(params['INTERVAL'] ?? '1') ?? 1;

      // Parse days of week
      List<DayOfWeek>? daysOfWeek;
      final byDay = params['BYDAY'];
      if (byDay != null) {
        daysOfWeek = byDay
            .split(',')
            .map((d) => DayOfWeek.fromRruleDay(d.trim()))
            .whereType<DayOfWeek>()
            .toList();
      }

      // Parse day of month
      final dayOfMonth = int.tryParse(params['BYMONTHDAY'] ?? '');

      // Parse occurrences
      final occurrences = int.tryParse(params['COUNT'] ?? '');

      // Parse end date
      DateTime? endDate;
      final until = params['UNTIL'];
      if (until != null) {
        endDate = _parseRruleDate(until);
      }

      return RecurrenceRule(
        frequency: frequency,
        interval: interval,
        daysOfWeek: daysOfWeek,
        dayOfMonth: dayOfMonth,
        occurrences: occurrences,
        endDate: endDate,
      );
    } catch (e) {
      return null;
    }
  }

  /// Parses an RRULE date string (YYYYMMDD or YYYYMMDDTHHMMSSZ).
  static DateTime? _parseRruleDate(String dateStr) {
    try {
      // Remove any trailing Z
      final cleanDate = dateStr.replaceAll('Z', '');

      if (cleanDate.length >= 8) {
        final year = int.parse(cleanDate.substring(0, 4));
        final month = int.parse(cleanDate.substring(4, 6));
        final day = int.parse(cleanDate.substring(6, 8));

        if (cleanDate.length >= 15) {
          // Has time component
          final hour = int.parse(cleanDate.substring(9, 11));
          final minute = int.parse(cleanDate.substring(11, 13));
          final second = int.parse(cleanDate.substring(13, 15));
          return DateTime.utc(year, month, day, hour, minute, second);
        }

        return DateTime.utc(year, month, day);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  @override
  String toString() {
    return 'RecurrenceRule(${toRruleString()})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is RecurrenceRule &&
        other.frequency == frequency &&
        other.interval == interval &&
        _listEquals(other.daysOfWeek, daysOfWeek) &&
        other.dayOfMonth == dayOfMonth &&
        other.occurrences == occurrences &&
        other.endDate == endDate;
  }

  @override
  int get hashCode {
    return Object.hash(
      frequency,
      interval,
      daysOfWeek != null ? Object.hashAll(daysOfWeek!) : null,
      dayOfMonth,
      occurrences,
      endDate,
    );
  }

  static bool _listEquals<T>(List<T>? a, List<T>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
