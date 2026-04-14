import 'package:device_calendar_plus/src/recurrence_rule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DayOfWeek', () {
    test('toRruleDay returns correct codes', () {
      expect(DayOfWeek.monday.toRruleDay(), 'MO');
      expect(DayOfWeek.tuesday.toRruleDay(), 'TU');
      expect(DayOfWeek.wednesday.toRruleDay(), 'WE');
      expect(DayOfWeek.thursday.toRruleDay(), 'TH');
      expect(DayOfWeek.friday.toRruleDay(), 'FR');
      expect(DayOfWeek.saturday.toRruleDay(), 'SA');
      expect(DayOfWeek.sunday.toRruleDay(), 'SU');
    });

    test('fromRruleDay parses correctly', () {
      expect(DayOfWeek.fromRruleDay('MO'), DayOfWeek.monday);
      expect(DayOfWeek.fromRruleDay('tu'), DayOfWeek.tuesday);
      expect(DayOfWeek.fromRruleDay('XX'), isNull);
    });
  });

  group('RecurrenceDay', () {
    test('without position serializes to plain day code', () {
      const day = RecurrenceDay(DayOfWeek.tuesday);
      expect(day.toRruleByDay(), 'TU');
    });

    test('with positive position serializes with prefix', () {
      const day = RecurrenceDay(DayOfWeek.tuesday, position: 2);
      expect(day.toRruleByDay(), '2TU');
    });

    test('with negative position serializes with prefix', () {
      const day = RecurrenceDay(DayOfWeek.friday, position: -1);
      expect(day.toRruleByDay(), '-1FR');
    });

    test('fromRruleByDay parses plain day code', () {
      final day = RecurrenceDay.fromRruleByDay('TU');
      expect(day, isNotNull);
      expect(day!.day, DayOfWeek.tuesday);
      expect(day.position, isNull);
    });

    test('fromRruleByDay parses positive position', () {
      final day = RecurrenceDay.fromRruleByDay('2TU');
      expect(day, isNotNull);
      expect(day!.day, DayOfWeek.tuesday);
      expect(day.position, 2);
    });

    test('fromRruleByDay parses negative position', () {
      final day = RecurrenceDay.fromRruleByDay('-1FR');
      expect(day, isNotNull);
      expect(day!.day, DayOfWeek.friday);
      expect(day.position, -1);
    });

    test('fromRruleByDay is case insensitive', () {
      final day = RecurrenceDay.fromRruleByDay('2tu');
      expect(day, isNotNull);
      expect(day!.day, DayOfWeek.tuesday);
      expect(day.position, 2);
    });

    test('fromRruleByDay returns null for invalid input', () {
      expect(RecurrenceDay.fromRruleByDay('XX'), isNull);
      expect(RecurrenceDay.fromRruleByDay('0TU'), isNull);
      expect(RecurrenceDay.fromRruleByDay(''), isNull);
    });

    test('equality', () {
      const a = RecurrenceDay(DayOfWeek.tuesday, position: 2);
      const b = RecurrenceDay(DayOfWeek.tuesday, position: 2);
      const c = RecurrenceDay(DayOfWeek.tuesday);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('position must be non-zero', () {
      expect(
        () => RecurrenceDay(DayOfWeek.monday, position: 0),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('RecurrenceEnd', () {
    test('CountEnd equality', () {
      expect(CountEnd(5), equals(CountEnd(5)));
      expect(CountEnd(5), isNot(equals(CountEnd(10))));
    });

    test('UntilEnd equality', () {
      final dt = DateTime.utc(2025, 6, 15);
      expect(UntilEnd(dt), equals(UntilEnd(dt)));
      expect(UntilEnd(dt), isNot(equals(UntilEnd(DateTime.utc(2025, 7, 1)))));
    });
  });

  group('toRruleString', () {
    group('DailyRecurrence', () {
      test('basic daily', () {
        const rule = DailyRecurrence();
        expect(rule.toRruleString(), 'FREQ=DAILY');
      });

      test('daily with interval', () {
        const rule = DailyRecurrence(interval: 3);
        expect(rule.toRruleString(), 'FREQ=DAILY;INTERVAL=3');
      });

      test('daily with count', () {
        const rule = DailyRecurrence(end: CountEnd(10));
        expect(rule.toRruleString(), 'FREQ=DAILY;COUNT=10');
      });

      test('daily with until (date-only, midnight)', () {
        final rule = DailyRecurrence(end: UntilEnd(DateTime.utc(2025, 6, 15)));
        expect(rule.toRruleString(), 'FREQ=DAILY;UNTIL=20250615');
      });

      test('daily with until (date-time)', () {
        final rule =
            DailyRecurrence(end: UntilEnd(DateTime.utc(2025, 6, 15, 14, 30)));
        expect(rule.toRruleString(), 'FREQ=DAILY;UNTIL=20250615T143000Z');
      });

      test('interval=1 is omitted', () {
        const rule = DailyRecurrence(interval: 1);
        expect(rule.toRruleString(), 'FREQ=DAILY');
      });
    });

    group('WeeklyRecurrence', () {
      test('basic weekly', () {
        const rule = WeeklyRecurrence();
        expect(rule.toRruleString(), 'FREQ=WEEKLY');
      });

      test('weekly with days', () {
        const rule = WeeklyRecurrence(
          daysOfWeek: [DayOfWeek.monday, DayOfWeek.wednesday, DayOfWeek.friday],
        );
        expect(rule.toRruleString(), 'FREQ=WEEKLY;BYDAY=MO,WE,FR');
      });

      test('weekly with interval and count', () {
        const rule = WeeklyRecurrence(
          interval: 2,
          daysOfWeek: [DayOfWeek.tuesday],
          end: CountEnd(8),
        );
        expect(rule.toRruleString(), 'FREQ=WEEKLY;INTERVAL=2;BYDAY=TU;COUNT=8');
      });
    });

    group('MonthlyRecurrence', () {
      test('basic monthly by date', () {
        final rule = MonthlyRecurrence.byDayOfMonth();
        expect(rule.toRruleString(), 'FREQ=MONTHLY');
      });

      test('monthly on day 15', () {
        final rule = MonthlyRecurrence.byDayOfMonth(daysOfMonth: [15]);
        expect(rule.toRruleString(), 'FREQ=MONTHLY;BYMONTHDAY=15');
      });

      test('monthly on multiple days', () {
        final rule = MonthlyRecurrence.byDayOfMonth(daysOfMonth: [1, 15]);
        expect(rule.toRruleString(), 'FREQ=MONTHLY;BYMONTHDAY=1,15');
      });

      test('monthly with interval and until', () {
        final rule = MonthlyRecurrence.byDayOfMonth(
          interval: 3,
          daysOfMonth: [1],
          end: UntilEnd(DateTime.utc(2026, 12, 31)),
        );
        expect(rule.toRruleString(),
            'FREQ=MONTHLY;INTERVAL=3;BYMONTHDAY=1;UNTIL=20261231');
      });

      test('monthly by weekday - 2nd Tuesday', () {
        final rule = MonthlyRecurrence.byWeekday(
          daysOfWeek: [RecurrenceDay(DayOfWeek.tuesday, position: 2)],
        );
        expect(rule.toRruleString(), 'FREQ=MONTHLY;BYDAY=2TU');
      });

      test('monthly by weekday - last Friday', () {
        final rule = MonthlyRecurrence.byWeekday(
          daysOfWeek: [RecurrenceDay(DayOfWeek.friday, position: -1)],
        );
        expect(rule.toRruleString(), 'FREQ=MONTHLY;BYDAY=-1FR');
      });

      test('monthly by weekday - every Tuesday (no position)', () {
        final rule = MonthlyRecurrence.byWeekday(
          daysOfWeek: [RecurrenceDay(DayOfWeek.tuesday)],
        );
        expect(rule.toRruleString(), 'FREQ=MONTHLY;BYDAY=TU');
      });

      test('monthly by weekday with interval and count', () {
        final rule = MonthlyRecurrence.byWeekday(
          interval: 2,
          daysOfWeek: [RecurrenceDay(DayOfWeek.monday, position: 1)],
          end: CountEnd(6),
        );
        expect(
            rule.toRruleString(), 'FREQ=MONTHLY;INTERVAL=2;BYDAY=1MO;COUNT=6');
      });
    });

    group('YearlyRecurrence', () {
      test('basic yearly by date', () {
        final rule = YearlyRecurrence.byDayOfMonth();
        expect(rule.toRruleString(), 'FREQ=YEARLY');
      });

      test('yearly with month and day', () {
        final rule =
            YearlyRecurrence.byDayOfMonth(months: [3], daysOfMonth: [15]);
        expect(rule.toRruleString(), 'FREQ=YEARLY;BYMONTH=3;BYMONTHDAY=15');
      });

      test('yearly with multiple months', () {
        final rule =
            YearlyRecurrence.byDayOfMonth(months: [6, 12], daysOfMonth: [15]);
        expect(rule.toRruleString(), 'FREQ=YEARLY;BYMONTH=6,12;BYMONTHDAY=15');
      });

      test('yearly with multiple months and days', () {
        final rule = YearlyRecurrence.byDayOfMonth(
            months: [6, 12], daysOfMonth: [1, 15]);
        expect(
            rule.toRruleString(), 'FREQ=YEARLY;BYMONTH=6,12;BYMONTHDAY=1,15');
      });

      test('yearly with count', () {
        final rule = YearlyRecurrence.byDayOfMonth(end: CountEnd(5));
        expect(rule.toRruleString(), 'FREQ=YEARLY;COUNT=5');
      });

      test('yearly by weekday - last Monday of May', () {
        final rule = YearlyRecurrence.byWeekday(
          months: [5],
          daysOfWeek: [RecurrenceDay(DayOfWeek.monday, position: -1)],
        );
        expect(rule.toRruleString(), 'FREQ=YEARLY;BYMONTH=5;BYDAY=-1MO');
      });

      test('yearly by weekday - 4th Thursday of November (Thanksgiving)', () {
        final rule = YearlyRecurrence.byWeekday(
          months: [11],
          daysOfWeek: [RecurrenceDay(DayOfWeek.thursday, position: 4)],
        );
        expect(rule.toRruleString(), 'FREQ=YEARLY;BYMONTH=11;BYDAY=4TH');
      });

      test('yearly by weekday - last Friday of June and December', () {
        final rule = YearlyRecurrence.byWeekday(
          months: [6, 12],
          daysOfWeek: [RecurrenceDay(DayOfWeek.friday, position: -1)],
        );
        expect(rule.toRruleString(), 'FREQ=YEARLY;BYMONTH=6,12;BYDAY=-1FR');
      });

      test('yearly by weekday with interval', () {
        final rule = YearlyRecurrence.byWeekday(
          interval: 2,
          months: [1],
          daysOfWeek: [RecurrenceDay(DayOfWeek.monday, position: 3)],
          end: CountEnd(5),
        );
        expect(rule.toRruleString(),
            'FREQ=YEARLY;INTERVAL=2;BYMONTH=1;BYDAY=3MO;COUNT=5');
      });
    });
  });

  group('fromRruleString', () {
    test('parses basic daily', () {
      final rule = RecurrenceRule.fromRruleString('FREQ=DAILY');
      expect(rule, isA<DailyRecurrence>());
      expect(rule!.interval, 1);
      expect(rule.end, isNull);
    });

    test('parses daily with interval and count', () {
      final rule =
          RecurrenceRule.fromRruleString('FREQ=DAILY;INTERVAL=3;COUNT=10');
      expect(rule, isA<DailyRecurrence>());
      expect(rule!.interval, 3);
      expect(rule.end, isA<CountEnd>());
      expect((rule.end as CountEnd).count, 10);
    });

    test('parses weekly with BYDAY', () {
      final rule = RecurrenceRule.fromRruleString('FREQ=WEEKLY;BYDAY=MO,WE,FR');
      expect(rule, isA<WeeklyRecurrence>());
      final weekly = rule as WeeklyRecurrence;
      expect(weekly.daysOfWeek, [
        DayOfWeek.monday,
        DayOfWeek.wednesday,
        DayOfWeek.friday,
      ]);
    });

    test('parses monthly with BYMONTHDAY', () {
      final rule = RecurrenceRule.fromRruleString('FREQ=MONTHLY;BYMONTHDAY=15');
      expect(rule, isA<MonthlyByDate>());
      expect((rule as MonthlyByDate).daysOfMonth, [15]);
    });

    test('parses monthly with multiple BYMONTHDAY', () {
      final rule =
          RecurrenceRule.fromRruleString('FREQ=MONTHLY;BYMONTHDAY=1,15');
      expect(rule, isA<MonthlyByDate>());
      expect((rule as MonthlyByDate).daysOfMonth, [1, 15]);
    });

    test('parses monthly with positional BYDAY', () {
      final rule = RecurrenceRule.fromRruleString('FREQ=MONTHLY;BYDAY=2TU');
      expect(rule, isA<MonthlyByWeekday>());
      final monthly = rule as MonthlyByWeekday;
      expect(monthly.daysOfWeek.length, 1);
      expect(monthly.daysOfWeek[0].day, DayOfWeek.tuesday);
      expect(monthly.daysOfWeek[0].position, 2);
    });

    test('parses monthly with negative positional BYDAY', () {
      final rule = RecurrenceRule.fromRruleString('FREQ=MONTHLY;BYDAY=-1FR');
      expect(rule, isA<MonthlyByWeekday>());
      final monthly = rule as MonthlyByWeekday;
      expect(monthly.daysOfWeek[0].day, DayOfWeek.friday);
      expect(monthly.daysOfWeek[0].position, -1);
    });

    test('parses monthly with plain BYDAY (no position)', () {
      final rule = RecurrenceRule.fromRruleString('FREQ=MONTHLY;BYDAY=TU');
      expect(rule, isA<MonthlyByWeekday>());
      final monthly = rule as MonthlyByWeekday;
      expect(monthly.daysOfWeek[0].day, DayOfWeek.tuesday);
      expect(monthly.daysOfWeek[0].position, isNull);
    });

    test('parses monthly with no BYDAY or BYMONTHDAY as MonthlyByDate', () {
      final rule = RecurrenceRule.fromRruleString('FREQ=MONTHLY');
      expect(rule, isA<MonthlyByDate>());
      expect((rule as MonthlyByDate).daysOfMonth, isNull);
    });

    test('parses yearly with BYMONTH and BYMONTHDAY', () {
      final rule =
          RecurrenceRule.fromRruleString('FREQ=YEARLY;BYMONTH=3;BYMONTHDAY=15');
      expect(rule, isA<YearlyByDate>());
      final yearly = rule as YearlyByDate;
      expect(yearly.months, [3]);
      expect(yearly.daysOfMonth, [15]);
    });

    test('parses yearly with multiple BYMONTH', () {
      final rule = RecurrenceRule.fromRruleString(
          'FREQ=YEARLY;BYMONTH=6,12;BYMONTHDAY=15');
      expect(rule, isA<YearlyByDate>());
      final yearly = rule as YearlyByDate;
      expect(yearly.months, [6, 12]);
      expect(yearly.daysOfMonth, [15]);
    });

    test('parses yearly with BYMONTH and positional BYDAY', () {
      final rule =
          RecurrenceRule.fromRruleString('FREQ=YEARLY;BYMONTH=5;BYDAY=-1MO');
      expect(rule, isA<YearlyByWeekday>());
      final yearly = rule as YearlyByWeekday;
      expect(yearly.months, [5]);
      expect(yearly.daysOfWeek.length, 1);
      expect(yearly.daysOfWeek[0].day, DayOfWeek.monday);
      expect(yearly.daysOfWeek[0].position, -1);
    });

    test('parses yearly with no BYDAY as YearlyByDate', () {
      final rule = RecurrenceRule.fromRruleString('FREQ=YEARLY;BYMONTH=12');
      expect(rule, isA<YearlyByDate>());
      expect((rule as YearlyByDate).months, [12]);
    });

    test('handles RRULE: prefix', () {
      final rule = RecurrenceRule.fromRruleString('RRULE:FREQ=DAILY;COUNT=5');
      expect(rule, isA<DailyRecurrence>());
      expect((rule!.end as CountEnd).count, 5);
    });

    test('returns null for unsupported frequency', () {
      expect(RecurrenceRule.fromRruleString('FREQ=MINUTELY'), isNull);
      expect(RecurrenceRule.fromRruleString('FREQ=HOURLY'), isNull);
      expect(RecurrenceRule.fromRruleString('FREQ=SECONDLY'), isNull);
    });

    test('returns null for missing FREQ', () {
      expect(RecurrenceRule.fromRruleString('INTERVAL=2;COUNT=5'), isNull);
    });

    test('returns null for empty string', () {
      expect(RecurrenceRule.fromRruleString(''), isNull);
    });

    test('returns null for garbage', () {
      expect(RecurrenceRule.fromRruleString('not a rrule'), isNull);
    });
  });

  group('UNTIL date parsing', () {
    test('parses date-only UNTIL (YYYYMMDD)', () {
      final rule = RecurrenceRule.fromRruleString('FREQ=DAILY;UNTIL=20250615');
      expect(rule, isNotNull);
      final until = (rule!.end as UntilEnd).until;
      expect(until, DateTime.utc(2025, 6, 15));
      expect(until.hour, 0);
      expect(until.minute, 0);
      expect(until.second, 0);
    });

    test('parses date-time UNTIL (YYYYMMDDTHHMMSSZ)', () {
      final rule =
          RecurrenceRule.fromRruleString('FREQ=DAILY;UNTIL=20250615T143000Z');
      expect(rule, isNotNull);
      final until = (rule!.end as UntilEnd).until;
      expect(until, DateTime.utc(2025, 6, 15, 14, 30, 0));
    });

    test('parses date-time UNTIL without Z suffix', () {
      final rule =
          RecurrenceRule.fromRruleString('FREQ=DAILY;UNTIL=20250615T143000');
      expect(rule, isNotNull);
      final until = (rule!.end as UntilEnd).until;
      expect(until, DateTime.utc(2025, 6, 15, 14, 30, 0));
    });
  });

  group('UNTIL date serialization', () {
    test('midnight DateTime serializes as date-only', () {
      final rule = DailyRecurrence(end: UntilEnd(DateTime.utc(2025, 6, 15)));
      final rrule = rule.toRruleString();
      expect(rrule, contains('UNTIL=20250615'));
      // Should not have a time component (no T after the date digits)
      expect(rrule, isNot(contains('UNTIL=20250615T')));
    });

    test('non-midnight DateTime serializes with time and Z', () {
      final rule =
          DailyRecurrence(end: UntilEnd(DateTime.utc(2025, 6, 15, 14, 30)));
      expect(rule.toRruleString(), contains('UNTIL=20250615T143000Z'));
    });

    test('local DateTime is converted to UTC before serialization', () {
      // Create a local DateTime (not UTC)
      final localDt = DateTime(2025, 6, 15, 14, 30);
      final rule = DailyRecurrence(end: UntilEnd(localDt));
      final rrule = rule.toRruleString();
      // The UNTIL should contain the UTC-converted time
      expect(rrule, contains('UNTIL='));
      expect(rrule, contains('Z'));
    });
  });

  group('serialization roundtrip', () {
    test('daily roundtrip', () {
      const original = DailyRecurrence(interval: 2, end: CountEnd(10));
      final parsed = RecurrenceRule.fromRruleString(original.toRruleString());
      expect(parsed, isA<DailyRecurrence>());
      expect(parsed!.interval, original.interval);
      expect(parsed.end, original.end);
    });

    test('weekly roundtrip with days', () {
      const original = WeeklyRecurrence(
        interval: 1,
        daysOfWeek: [DayOfWeek.monday, DayOfWeek.friday],
        end: CountEnd(20),
      );
      final parsed = RecurrenceRule.fromRruleString(original.toRruleString());
      expect(parsed, isA<WeeklyRecurrence>());
      final weekly = parsed as WeeklyRecurrence;
      expect(weekly.daysOfWeek, original.daysOfWeek);
      expect(weekly.end, original.end);
    });

    test('monthly by date roundtrip', () {
      final original =
          MonthlyRecurrence.byDayOfMonth(daysOfMonth: [28], end: CountEnd(12));
      final parsed = RecurrenceRule.fromRruleString(original.toRruleString());
      expect(parsed, isA<MonthlyByDate>());
      expect((parsed as MonthlyByDate).daysOfMonth, [28]);
    });

    test('monthly by date roundtrip with multiple days', () {
      final original = MonthlyRecurrence.byDayOfMonth(
          daysOfMonth: [1, 15], end: CountEnd(12));
      final parsed = RecurrenceRule.fromRruleString(original.toRruleString());
      expect(parsed, isA<MonthlyByDate>());
      expect((parsed as MonthlyByDate).daysOfMonth, [1, 15]);
    });

    test('monthly by weekday roundtrip - positional', () {
      final original = MonthlyRecurrence.byWeekday(
        daysOfWeek: [RecurrenceDay(DayOfWeek.tuesday, position: 2)],
        end: CountEnd(12),
      );
      final parsed = RecurrenceRule.fromRruleString(original.toRruleString());
      expect(parsed, isA<MonthlyByWeekday>());
      final monthly = parsed as MonthlyByWeekday;
      expect(monthly.daysOfWeek.length, 1);
      expect(monthly.daysOfWeek[0].day, DayOfWeek.tuesday);
      expect(monthly.daysOfWeek[0].position, 2);
    });

    test('monthly by weekday roundtrip - negative position', () {
      final original = MonthlyRecurrence.byWeekday(
        daysOfWeek: [RecurrenceDay(DayOfWeek.friday, position: -1)],
      );
      final parsed = RecurrenceRule.fromRruleString(original.toRruleString());
      expect(parsed, isA<MonthlyByWeekday>());
      final monthly = parsed as MonthlyByWeekday;
      expect(monthly.daysOfWeek[0].day, DayOfWeek.friday);
      expect(monthly.daysOfWeek[0].position, -1);
    });

    test('monthly by weekday roundtrip - no position', () {
      final original = MonthlyRecurrence.byWeekday(
        daysOfWeek: [RecurrenceDay(DayOfWeek.wednesday)],
      );
      final parsed = RecurrenceRule.fromRruleString(original.toRruleString());
      expect(parsed, isA<MonthlyByWeekday>());
      final monthly = parsed as MonthlyByWeekday;
      expect(monthly.daysOfWeek[0].day, DayOfWeek.wednesday);
      expect(monthly.daysOfWeek[0].position, isNull);
    });

    test('yearly by date roundtrip', () {
      final original = YearlyRecurrence.byDayOfMonth(
          months: [12], daysOfMonth: [25], end: CountEnd(5));
      final parsed = RecurrenceRule.fromRruleString(original.toRruleString());
      expect(parsed, isA<YearlyByDate>());
      final yearly = parsed as YearlyByDate;
      expect(yearly.months, [12]);
      expect(yearly.daysOfMonth, [25]);
    });

    test('yearly by date roundtrip with multiple months', () {
      final original =
          YearlyRecurrence.byDayOfMonth(months: [6, 12], daysOfMonth: [1, 15]);
      final parsed = RecurrenceRule.fromRruleString(original.toRruleString());
      expect(parsed, isA<YearlyByDate>());
      final yearly = parsed as YearlyByDate;
      expect(yearly.months, [6, 12]);
      expect(yearly.daysOfMonth, [1, 15]);
    });

    test('yearly by weekday roundtrip', () {
      final original = YearlyRecurrence.byWeekday(
        months: [11],
        daysOfWeek: [RecurrenceDay(DayOfWeek.thursday, position: 4)],
      );
      final parsed = RecurrenceRule.fromRruleString(original.toRruleString());
      expect(parsed, isA<YearlyByWeekday>());
      final yearly = parsed as YearlyByWeekday;
      expect(yearly.months, [11]);
      expect(yearly.daysOfWeek[0].day, DayOfWeek.thursday);
      expect(yearly.daysOfWeek[0].position, 4);
    });

    test('yearly by weekday roundtrip with multiple months', () {
      final original = YearlyRecurrence.byWeekday(
        months: [6, 12],
        daysOfWeek: [RecurrenceDay(DayOfWeek.friday, position: -1)],
      );
      final parsed = RecurrenceRule.fromRruleString(original.toRruleString());
      expect(parsed, isA<YearlyByWeekday>());
      final yearly = parsed as YearlyByWeekday;
      expect(yearly.months, [6, 12]);
      expect(yearly.daysOfWeek[0].day, DayOfWeek.friday);
      expect(yearly.daysOfWeek[0].position, -1);
    });

    test('UNTIL date-only roundtrip', () {
      final original =
          DailyRecurrence(end: UntilEnd(DateTime.utc(2025, 6, 15)));
      final parsed = RecurrenceRule.fromRruleString(original.toRruleString());
      final until = (parsed!.end as UntilEnd).until;
      expect(until, DateTime.utc(2025, 6, 15));
    });

    test('UNTIL date-time roundtrip', () {
      final original =
          DailyRecurrence(end: UntilEnd(DateTime.utc(2025, 6, 15, 14, 30, 45)));
      final parsed = RecurrenceRule.fromRruleString(original.toRruleString());
      final until = (parsed!.end as UntilEnd).until;
      expect(until, DateTime.utc(2025, 6, 15, 14, 30, 45));
    });
  });

  group('rruleString getter', () {
    test('returns toRruleString when constructed directly', () {
      const rule = DailyRecurrence(interval: 2, end: CountEnd(5));
      expect(rule.rruleString, rule.toRruleString());
    });

    test('returns original raw string when parsed', () {
      const raw = 'FREQ=DAILY;INTERVAL=2;COUNT=5;BYHOUR=9';
      final rule = RecurrenceRule.fromRruleString(raw);
      // rruleString preserves the original including BYHOUR
      expect(rule!.rruleString, raw);
    });

    test('preserves RRULE: prefix in raw string', () {
      const raw = 'RRULE:FREQ=WEEKLY;BYDAY=MO';
      final rule = RecurrenceRule.fromRruleString(raw);
      expect(rule!.rruleString, raw);
    });
  });

  group('equality', () {
    test('same DailyRecurrence are equal', () {
      const a = DailyRecurrence(interval: 2, end: CountEnd(5));
      const b = DailyRecurrence(interval: 2, end: CountEnd(5));
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different frequencies are not equal', () {
      const daily = DailyRecurrence(end: CountEnd(5));
      const weekly = WeeklyRecurrence(end: CountEnd(5));
      expect(daily, isNot(equals(weekly)));
    });

    test('WeeklyRecurrence with different days are not equal', () {
      const a = WeeklyRecurrence(daysOfWeek: [DayOfWeek.monday]);
      const b = WeeklyRecurrence(daysOfWeek: [DayOfWeek.friday]);
      expect(a, isNot(equals(b)));
    });

    test('MonthlyByDate with different daysOfMonth are not equal', () {
      final a = MonthlyRecurrence.byDayOfMonth(daysOfMonth: [1]);
      final b = MonthlyRecurrence.byDayOfMonth(daysOfMonth: [15]);
      expect(a, isNot(equals(b)));
    });

    test('MonthlyByWeekday with different days are not equal', () {
      final a = MonthlyRecurrence.byWeekday(
        daysOfWeek: [RecurrenceDay(DayOfWeek.tuesday, position: 2)],
      );
      final b = MonthlyRecurrence.byWeekday(
        daysOfWeek: [RecurrenceDay(DayOfWeek.friday, position: -1)],
      );
      expect(a, isNot(equals(b)));
    });

    test('MonthlyByDate and MonthlyByWeekday are not equal', () {
      final a = MonthlyRecurrence.byDayOfMonth(daysOfMonth: [15]);
      final b = MonthlyRecurrence.byWeekday(
        daysOfWeek: [RecurrenceDay(DayOfWeek.tuesday, position: 2)],
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('WKST', () {
    test('weekly with wkst serializes correctly', () {
      const rule = WeeklyRecurrence(
        daysOfWeek: [DayOfWeek.monday],
        wkst: DayOfWeek.sunday,
      );
      expect(rule.toRruleString(), 'FREQ=WEEKLY;BYDAY=MO;WKST=SU');
    });

    test('weekly without wkst omits it', () {
      const rule = WeeklyRecurrence(daysOfWeek: [DayOfWeek.monday]);
      expect(rule.toRruleString(), isNot(contains('WKST')));
    });

    test('parses WKST from rrule string', () {
      final rule =
          RecurrenceRule.fromRruleString('FREQ=WEEKLY;BYDAY=MO;WKST=SU');
      expect(rule, isA<WeeklyRecurrence>());
      expect((rule as WeeklyRecurrence).wkst, DayOfWeek.sunday);
    });

    test('WKST roundtrip', () {
      const original = WeeklyRecurrence(
        daysOfWeek: [DayOfWeek.monday, DayOfWeek.friday],
        wkst: DayOfWeek.sunday,
        end: CountEnd(10),
      );
      final parsed = RecurrenceRule.fromRruleString(original.toRruleString());
      expect(parsed, isA<WeeklyRecurrence>());
      final weekly = parsed as WeeklyRecurrence;
      expect(weekly.wkst, DayOfWeek.sunday);
      expect(weekly.daysOfWeek, original.daysOfWeek);
    });

    test('WKST equality', () {
      const a = WeeklyRecurrence(
          daysOfWeek: [DayOfWeek.monday], wkst: DayOfWeek.sunday);
      const b = WeeklyRecurrence(
          daysOfWeek: [DayOfWeek.monday], wkst: DayOfWeek.sunday);
      const c = WeeklyRecurrence(
          daysOfWeek: [DayOfWeek.monday], wkst: DayOfWeek.monday);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('BYSETPOS', () {
    test('monthly byWeekday with setPositions - last weekday', () {
      final rule = MonthlyRecurrence.byWeekday(
        daysOfWeek: [
          RecurrenceDay(DayOfWeek.monday),
          RecurrenceDay(DayOfWeek.tuesday),
          RecurrenceDay(DayOfWeek.wednesday),
          RecurrenceDay(DayOfWeek.thursday),
          RecurrenceDay(DayOfWeek.friday),
        ],
        setPositions: [-1],
      );
      expect(rule.toRruleString(),
          'FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1');
    });

    test('monthly byWeekday with setPositions - first and last', () {
      final rule = MonthlyRecurrence.byWeekday(
        daysOfWeek: [
          RecurrenceDay(DayOfWeek.monday),
          RecurrenceDay(DayOfWeek.friday),
        ],
        setPositions: [1, -1],
      );
      expect(rule.toRruleString(), 'FREQ=MONTHLY;BYDAY=MO,FR;BYSETPOS=1,-1');
    });

    test('monthly without setPositions omits it', () {
      final rule = MonthlyRecurrence.byWeekday(
        daysOfWeek: [RecurrenceDay(DayOfWeek.monday)],
      );
      expect(rule.toRruleString(), isNot(contains('BYSETPOS')));
    });

    test('parses BYSETPOS from monthly rrule', () {
      final rule = RecurrenceRule.fromRruleString(
          'FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1');
      expect(rule, isA<MonthlyByWeekday>());
      final monthly = rule as MonthlyByWeekday;
      expect(monthly.setPositions, [-1]);
      expect(monthly.daysOfWeek.length, 5);
    });

    test('parses BYSETPOS from yearly rrule', () {
      final rule = RecurrenceRule.fromRruleString(
          'FREQ=YEARLY;BYMONTH=1;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1');
      expect(rule, isA<YearlyByWeekday>());
      final yearly = rule as YearlyByWeekday;
      expect(yearly.setPositions, [1]);
    });

    test('BYSETPOS monthly roundtrip', () {
      final original = MonthlyRecurrence.byWeekday(
        daysOfWeek: [
          RecurrenceDay(DayOfWeek.monday),
          RecurrenceDay(DayOfWeek.tuesday),
          RecurrenceDay(DayOfWeek.wednesday),
          RecurrenceDay(DayOfWeek.thursday),
          RecurrenceDay(DayOfWeek.friday),
        ],
        setPositions: [-1],
        end: CountEnd(12),
      );
      final parsed = RecurrenceRule.fromRruleString(original.toRruleString());
      expect(parsed, isA<MonthlyByWeekday>());
      final monthly = parsed as MonthlyByWeekday;
      expect(monthly.setPositions, [-1]);
      expect(monthly.daysOfWeek.length, 5);
      expect((monthly.end as CountEnd).count, 12);
    });

    test('BYSETPOS yearly roundtrip', () {
      final original = YearlyRecurrence.byWeekday(
        months: [1],
        daysOfWeek: [
          RecurrenceDay(DayOfWeek.monday),
          RecurrenceDay(DayOfWeek.friday),
        ],
        setPositions: [1, -1],
      );
      final parsed = RecurrenceRule.fromRruleString(original.toRruleString());
      expect(parsed, isA<YearlyByWeekday>());
      final yearly = parsed as YearlyByWeekday;
      expect(yearly.setPositions, [1, -1]);
    });

    test('BYSETPOS equality', () {
      final a = MonthlyRecurrence.byWeekday(
        daysOfWeek: [RecurrenceDay(DayOfWeek.monday)],
        setPositions: [-1],
      );
      final b = MonthlyRecurrence.byWeekday(
        daysOfWeek: [RecurrenceDay(DayOfWeek.monday)],
        setPositions: [-1],
      );
      final c = MonthlyRecurrence.byWeekday(
        daysOfWeek: [RecurrenceDay(DayOfWeek.monday)],
        setPositions: [1],
      );
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('validation', () {
    test('interval must be >= 1', () {
      expect(
          () => DailyRecurrence(interval: 0), throwsA(isA<AssertionError>()));
    });

    test('CountEnd count must be >= 1', () {
      expect(() => CountEnd(0), throwsA(isA<AssertionError>()));
    });

    test('MonthlyByDate daysOfMonth range', () {
      expect(
        () => MonthlyRecurrence.byDayOfMonth(daysOfMonth: [0]),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => MonthlyRecurrence.byDayOfMonth(daysOfMonth: [32]),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => MonthlyRecurrence.byDayOfMonth(daysOfMonth: [1, 15, 31]),
        returnsNormally,
      );
    });

    test('YearlyByDate months range', () {
      expect(
        () => YearlyRecurrence.byDayOfMonth(months: [0]),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => YearlyRecurrence.byDayOfMonth(months: [13]),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => YearlyRecurrence.byDayOfMonth(months: [1, 6, 12]),
        returnsNormally,
      );
    });

    test('YearlyByDate daysOfMonth range', () {
      expect(
        () => YearlyRecurrence.byDayOfMonth(daysOfMonth: [0]),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => YearlyRecurrence.byDayOfMonth(daysOfMonth: [32]),
        throwsA(isA<AssertionError>()),
      );
    });

    test('YearlyByWeekday months range', () {
      expect(
        () => YearlyRecurrence.byWeekday(
          months: [0],
          daysOfWeek: [RecurrenceDay(DayOfWeek.monday)],
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => YearlyRecurrence.byWeekday(
          months: [13],
          daysOfWeek: [RecurrenceDay(DayOfWeek.monday)],
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('RecurrenceDay position range', () {
      expect(
        () => RecurrenceDay(DayOfWeek.monday, position: 0),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => RecurrenceDay(DayOfWeek.monday, position: 54),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => RecurrenceDay(DayOfWeek.monday, position: -54),
        throwsA(isA<AssertionError>()),
      );
      // Valid bounds
      expect(
        () => RecurrenceDay(DayOfWeek.monday, position: 53),
        returnsNormally,
      );
      expect(
        () => RecurrenceDay(DayOfWeek.monday, position: -53),
        returnsNormally,
      );
    });
  });
}
