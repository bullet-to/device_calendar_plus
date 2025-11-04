// ignore_for_file: avoid_print

import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() async {
  const packageName = 'to.bullet.example';

  // Grant Android permissions before tests run (via adb on host machine)
  print('📱 Granting calendar permissions via adb...');
  for (final permission in [
    'android.permission.READ_CALENDAR',
    'android.permission.WRITE_CALENDAR',
  ]) {
    try {
      final result = Process.runSync(
        'adb',
        ['shell', 'pm', 'grant', packageName, permission],
      );
      if (result.exitCode == 0) {
        print('  ✓ Granted $permission');
      } else {
        print('  ⚠ Failed to grant $permission: ${result.stderr}');
      }
    } catch (e) {
      print('  ⚠ Error granting $permission: $e');
    }
  }
  print('');

  // Run the integration tests
  await integrationDriver();

  // Revoke permissions after tests (cleanup)
  print('');
  print('🧹 Revoking calendar permissions...');
  for (final permission in [
    'android.permission.READ_CALENDAR',
    'android.permission.WRITE_CALENDAR',
  ]) {
    try {
      Process.runSync(
        'adb',
        ['shell', 'pm', 'revoke', packageName, permission],
      );
    } catch (e) {
      // Ignore errors during cleanup
    }
  }
}
