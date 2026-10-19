import 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Patch', () {
    group('map', () {
      test('should map a clear to a clear of the new type', () {
        final mapped = Patch<int>.clear().map((x) => '$x');

        expect(mapped, Patch<String>.clear());
        expect(Patch<String>.clear(), mapped);
        expect(mapped.hashCode, Patch<String>.clear().hashCode);
      });
    });
  });

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
