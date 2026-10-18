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
    });
  });
}
