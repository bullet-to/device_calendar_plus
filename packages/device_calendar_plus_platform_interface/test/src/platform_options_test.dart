import 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ada = AttendeeAndroid(email: 'ada@example.com', name: 'Ada');
  const bob = AttendeeAndroid(email: 'bob@example.com');

  group('EventOptionsAndroid', () {
    group('==', () {
      test('should compare the attendee list by its elements', () {
        final a = EventOptionsAndroid(attendees: [ada, bob]);
        final b = EventOptionsAndroid(attendees: [ada, bob]);

        expect(a, b);
        expect(a.hashCode, b.hashCode);
      });

      test('should tell attendee lists in another order apart', () {
        expect(
          EventOptionsAndroid(attendees: [ada, bob]),
          isNot(EventOptionsAndroid(attendees: [bob, ada])),
        );
      });
    });
  });

  group('EventUpdateOptionsAndroid', () {
    group('==', () {
      test('should compare a set attendee list by its elements', () {
        final a = EventUpdateOptionsAndroid(attendees: Patch.set([ada]));
        final b = EventUpdateOptionsAndroid(attendees: Patch.set([ada]));

        expect(a, b);
        expect(a.hashCode, b.hashCode);
      });

      test('should tell different set attendee lists apart', () {
        expect(
          EventUpdateOptionsAndroid(attendees: Patch.set([ada])),
          isNot(EventUpdateOptionsAndroid(attendees: Patch.set([bob]))),
        );
      });

      test('should tell a set from a clear', () {
        expect(
          const EventUpdateOptionsAndroid(attendees: Patch.set([])),
          isNot(const EventUpdateOptionsAndroid(attendees: Patch.clear())),
        );
      });
    });

    group('isEmpty', () {
      test('should be false when only attendees are set', () {
        expect(
          const EventUpdateOptionsAndroid(attendees: Patch.clear()).isEmpty,
          isFalse,
        );
      });
    });
  });
}
