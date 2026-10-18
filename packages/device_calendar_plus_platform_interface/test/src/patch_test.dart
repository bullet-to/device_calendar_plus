import 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PatchSet', () {
    group('==', () {
      test('should compare a List value by its elements', () {
        final a = Patch<List<int>>.set([15, 30]);
        final b = Patch<List<int>>.set([15, 30]);

        expect(a, b);
        expect(a.hashCode, b.hashCode);
      });

      test('should tell List values in a different order apart', () {
        expect(
          Patch<List<int>>.set([15, 30]),
          isNot(Patch<List<int>>.set([30, 15])),
        );
      });
    });
  });
}
