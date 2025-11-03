import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Device Calendar Integration Tests', () {
    late DeviceCalendar plugin;
    final List<String> createdCalendarIds = [];

    setUpAll(() {
      plugin = DeviceCalendar.instance;
    });

    tearDownAll(() async {
      // Clean up all created calendars
      if (createdCalendarIds.isNotEmpty) {
        print(
            '🧹 Cleaning up ${createdCalendarIds.length} test calendar(s)...');
        int deletedCount = 0;
        for (final id in createdCalendarIds) {
          try {
            await plugin.deleteCalendar(id);
            deletedCount++;
          } catch (e) {
            print('  ⚠️  Failed to delete calendar $id: $e');
          }
        }
        print(
            '✅ Deleted $deletedCount/${createdCalendarIds.length} test calendars');
      }
    });

    test('1. Request Permissions', () async {
      final status = await plugin.requestPermissions();

      print('Permission status: $status');

      // The test will continue regardless of permission status, but warn if denied
      if (status != CalendarPermissionStatus.granted) {
        print('⚠️  Calendar permissions not granted. Status: $status');
        print('   Remaining tests may fail or be skipped.');
      }

      expect(
          status,
          isIn([
            CalendarPermissionStatus.granted,
            CalendarPermissionStatus.denied,
            CalendarPermissionStatus.restricted,
          ]));
    });

    test('2. Create and Delete Calendar', () async {
      // This test creates and immediately deletes a calendar to verify delete works
      // If delete fails, only one calendar needs manual cleanup
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final calendarName = 'Create-Delete Test $timestamp';

      // Create calendar
      final calendarId = await plugin.createCalendar(name: calendarName);
      expect(calendarId, isNotEmpty);
      expect(calendarId, isA<String>());
      print('✅ Created calendar: $calendarName (ID: $calendarId)');

      // Delete calendar
      await plugin.deleteCalendar(calendarId);
      print('✅ Deleted calendar: $calendarId');

      // Verify it's gone by listing calendars
      final calendars = await plugin.listCalendars();
      final deletedCalendar =
          calendars.where((cal) => cal.id == calendarId).toList();
      expect(deletedCalendar, isEmpty,
          reason: 'Calendar should be deleted and not in list');

      print('✅ Verified calendar was deleted');
    });

    test('3. Verify Calendar in List', () async {
      // Create a new calendar for this test
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final calendarName = 'Verify Test Calendar $timestamp';

      final calendarId = await plugin.createCalendar(name: calendarName);
      createdCalendarIds.add(calendarId);

      // List all calendars
      final calendars = await plugin.listCalendars();

      expect(calendars, isNotEmpty);

      // Find our newly created calendar
      final createdCalendar = calendars.firstWhere(
        (cal) => cal.id == calendarId,
        orElse: () => throw Exception('Created calendar not found in list'),
      );

      expect(createdCalendar.name, equals(calendarName));
      expect(createdCalendar.id, equals(calendarId));

      print('✅ Verified calendar in list: ${createdCalendar.name}');
      print('   - ID: ${createdCalendar.id}');
      print('   - Read-only: ${createdCalendar.readOnly}');
      print('   - Primary: ${createdCalendar.isPrimary}');
      print('   - Color: ${createdCalendar.colorHex}');
      print(
          '   - Account: ${createdCalendar.accountName} (${createdCalendar.accountType})');
    });

    test('4. Create Calendar with Color', () async {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final calendarName = 'Colored Calendar $timestamp';
      final colorHex = '#FF5733';

      final calendarId = await plugin.createCalendar(
        name: calendarName,
        colorHex: colorHex,
      );

      expect(calendarId, isNotEmpty);
      createdCalendarIds.add(calendarId);

      // List calendars and find the one we just created
      final calendars = await plugin.listCalendars();
      final coloredCalendar =
          calendars.firstWhere((cal) => cal.id == calendarId);

      expect(coloredCalendar.colorHex, isNotNull);

      // Note: iOS may convert the color to a different color space,
      // so we can't do an exact match. Just verify it has a color.
      print('✅ Created colored calendar: ${coloredCalendar.name}');
      print('   - Requested color: $colorHex');
      print('   - Actual color: ${coloredCalendar.colorHex}');

      // On Android, the color should match exactly
      // On iOS, color may be slightly different due to color space conversion
      if (coloredCalendar.colorHex != null) {
        expect(coloredCalendar.colorHex!.length, equals(7)); // #RRGGBB format
        expect(coloredCalendar.colorHex!.startsWith('#'), isTrue);
      }
    });

    test('5. Create Multiple Calendars', () async {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final calendarNames = [
        'Multi Test Calendar 1 $timestamp',
        'Multi Test Calendar 2 $timestamp',
        'Multi Test Calendar 3 $timestamp',
      ];

      final createdIds = <String>[];

      // Create 3 calendars
      for (final name in calendarNames) {
        final calendarId = await plugin.createCalendar(name: name);
        expect(calendarId, isNotEmpty);
        createdIds.add(calendarId);
        createdCalendarIds.add(calendarId);
      }

      expect(createdIds.length, equals(3));
      expect(createdIds.toSet().length, equals(3)); // All unique IDs

      // Verify all 3 appear in the list
      final calendars = await plugin.listCalendars();

      for (var i = 0; i < calendarNames.length; i++) {
        final calendar = calendars.firstWhere(
          (cal) => cal.id == createdIds[i],
          orElse: () =>
              throw Exception('Calendar ${calendarNames[i]} not found'),
        );

        expect(calendar.name, equals(calendarNames[i]));
      }

      print('✅ Created and verified ${createdIds.length} calendars');
    });

    test('6. Cross-Platform Consistency', () async {
      // Create a calendar and verify the data structure is consistent
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final calendarName = 'Consistency Test $timestamp';
      final colorHex = '#3498DB';

      final calendarId = await plugin.createCalendar(
        name: calendarName,
        colorHex: colorHex,
      );
      createdCalendarIds.add(calendarId);

      final calendars = await plugin.listCalendars();
      final calendar = calendars.firstWhere((cal) => cal.id == calendarId);

      // Verify all expected fields are present and of correct types
      expect(calendar.id, isA<String>());
      expect(calendar.id, isNotEmpty);
      expect(calendar.name, isA<String>());
      expect(calendar.name, equals(calendarName));
      expect(calendar.readOnly, isA<bool>());
      expect(calendar.isPrimary, isA<bool>());
      expect(calendar.hidden, isA<bool>());

      // Optional fields
      if (calendar.colorHex != null) {
        expect(calendar.colorHex, isA<String>());
      }
      if (calendar.accountName != null) {
        expect(calendar.accountName, isA<String>());
      }
      if (calendar.accountType != null) {
        expect(calendar.accountType, isA<String>());
      }

      print('✅ Calendar data structure is consistent across platforms');
      print('   - Platform: ${await plugin.getPlatformVersion()}');
      print('   - All required fields present with correct types');
    });

    test('7. Update Calendar - Name Only', () async {
      // Create a calendar and update just its name
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final originalName = 'Update Name Test $timestamp';
      final newName = 'Updated Name $timestamp';

      final calendarId = await plugin.createCalendar(name: originalName);
      createdCalendarIds.add(calendarId);
      print('✅ Created calendar: $originalName (ID: $calendarId)');

      // Update just the name
      await plugin.updateCalendar(calendarId, name: newName);
      print('✅ Updated calendar name to: $newName');

      // Verify the update
      final calendars = await plugin.listCalendars();
      final updatedCalendar =
          calendars.firstWhere((cal) => cal.id == calendarId);
      expect(updatedCalendar.name, equals(newName));
      print('✅ Verified calendar name was updated');
    });

    test('8. Update Calendar - Color Only', () async {
      // Create a calendar and update just its color
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final calendarName = 'Update Color Test $timestamp';
      final newColor = '#00FF00'; // Green

      final calendarId = await plugin.createCalendar(
        name: calendarName,
        colorHex: '#FF0000', // Red
      );
      createdCalendarIds.add(calendarId);
      print(
          '✅ Created calendar: $calendarName (ID: $calendarId) with red color');

      // Update just the color
      await plugin.updateCalendar(calendarId, colorHex: newColor);
      print('✅ Updated calendar color to: $newColor');

      // Verify the update
      final calendars = await plugin.listCalendars();
      final updatedCalendar =
          calendars.firstWhere((cal) => cal.id == calendarId);
      expect(updatedCalendar.colorHex?.toUpperCase(),
          equals(newColor.toUpperCase()));
      print('✅ Verified calendar color was updated');
    });

    test('9. Update Calendar - Name and Color', () async {
      // Create a calendar and update both name and color
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final originalName = 'Update Both Test $timestamp';
      final newName = 'Updated Both $timestamp';
      final newColor = '#0000FF'; // Blue

      final calendarId = await plugin.createCalendar(
        name: originalName,
        colorHex: '#FF0000', // Red
      );
      createdCalendarIds.add(calendarId);
      print('✅ Created calendar: $originalName (ID: $calendarId)');

      // Update both name and color
      await plugin.updateCalendar(calendarId,
          name: newName, colorHex: newColor);
      print('✅ Updated calendar name and color');

      // Verify the updates
      final calendars = await plugin.listCalendars();
      final updatedCalendar =
          calendars.firstWhere((cal) => cal.id == calendarId);
      expect(updatedCalendar.name, equals(newName));
      expect(updatedCalendar.colorHex?.toUpperCase(),
          equals(newColor.toUpperCase()));
      print('✅ Verified calendar name and color were updated');
    });

    test('10. Error Handling - Update with No Parameters', () async {
      // Create a calendar first
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final calendarId =
          await plugin.createCalendar(name: 'Error Test $timestamp');
      createdCalendarIds.add(calendarId);

      // Try to update without providing any parameters
      try {
        await plugin.updateCalendar(calendarId);
        fail('Should have thrown an error when no parameters provided');
      } on ArgumentError catch (e) {
        print('✅ Correctly rejected update with no parameters: $e');
        expect(e.message, contains('At least one'));
      }
    });

    test('11. Error Handling - Update with Empty Name', () async {
      // Create a calendar first
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final calendarId =
          await plugin.createCalendar(name: 'Empty Name Test $timestamp');
      createdCalendarIds.add(calendarId);

      // Try to update with an empty name
      try {
        await plugin.updateCalendar(calendarId, name: '');
        fail('Should have thrown an error for empty name');
      } on ArgumentError catch (e) {
        print('✅ Correctly rejected empty name in update: $e');
        expect(e.message, contains('cannot be empty'));
      }
    });

    test('12. Error Handling - Create with Empty Name', () async {
      // Attempting to create a calendar with an empty name should fail
      try {
        await plugin.createCalendar(name: '');
        fail('Should have thrown an error for empty calendar name');
      } on ArgumentError catch (e) {
        // Expected - test passes
        print('✅ Correctly rejected empty calendar name: $e');
        expect(e.message, contains('cannot be empty'));
      }
    });

    test('13. Error Handling - Create with Whitespace-only Name', () async {
      // Whitespace-only names should also fail
      try {
        await plugin.createCalendar(name: '   ');
        fail('Should have thrown an error for whitespace-only calendar name');
      } on ArgumentError catch (e) {
        print('✅ Correctly rejected whitespace-only calendar name: $e');
        expect(e.message, contains('cannot be empty'));
      }
    });

    test('14. Color Format Variations', () async {
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      // Test different valid color formats
      final colorVariations = [
        '#FF0000', // Red
        '#00FF00', // Green
        '#0000FF', // Blue
        '#FFFFFF', // White
        '#000000', // Black
      ];

      for (var i = 0; i < colorVariations.length; i++) {
        final color = colorVariations[i];
        final calendarId = await plugin.createCalendar(
          name: 'Color Test $i $timestamp',
          colorHex: color,
        );

        expect(calendarId, isNotEmpty);
        createdCalendarIds.add(calendarId);
      }

      print('✅ Successfully created calendars with various color formats');
    });
  });
}
