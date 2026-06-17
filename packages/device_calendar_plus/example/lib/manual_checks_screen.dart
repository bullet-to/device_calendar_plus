import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter/material.dart';

/// Manual verification screen for behaviour that integration tests **cannot**
/// cover.
///
/// Everything here depends on a surface the test harness can't drive or assert
/// on: a system permission dialog (its tier and copy are drawn by the OS), the
/// native create/edit/view forms (rendered by EventKit / the system Calendar
/// app), leaving the app for Settings, or state that only changes across
/// sessions. Each card pairs an action with the plain-text result you should
/// see, so a human can run it on a real device and eyeball the outcome.
///
/// The automated `integration_test/` suite already covers the headless
/// round-trips (create → read back, recurrence expansion, ranges, sources).
class ManualChecksScreen extends StatefulWidget {
  const ManualChecksScreen({super.key});

  @override
  State<ManualChecksScreen> createState() => _ManualChecksScreenState();
}

class _ManualChecksScreenState extends State<ManualChecksScreen> {
  /// Last outcome per check, keyed by the check's title.
  final Map<String, _CheckResult> _results = {};

  /// Set of checks currently running (so we can show a spinner / disable).
  final Set<String> _running = {};

  /// Event created by the "Create sample event" check, reused by the View /
  /// Edit form checks below (they need an existing event to open).
  String? _sampleEventId;

  Future<void> _run(String key, Future<String> Function() action) async {
    setState(() => _running.add(key));
    try {
      final outcome = await action();
      _set(key, _CheckResult.ok(outcome));
    } catch (e) {
      _set(key, _CheckResult.error(e.toString()));
    } finally {
      setState(() => _running.remove(key));
    }
  }

  void _set(String key, _CheckResult result) {
    if (!mounted) return;
    setState(() => _results[key] = result);
  }

  /// Finds the first writable calendar, or throws a readable error.
  Future<Calendar> _firstWritableCalendar() async {
    final calendars = await DeviceCalendar.instance.listCalendars();
    final writable = calendars.where((c) => !c.readOnly).toList();
    if (writable.isEmpty) {
      throw StateError(
        'No writable calendar found. Grant full access first.',
      );
    }
    return writable.first;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Manual Checks'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionHeader(
            'Permission prompts',
            'Integration tests can grant/deny via the harness but cannot see '
                'which dialog the OS draws or its wording. Verify by eye on a '
                'real device.',
          ),
          _CheckCard(
            title: 'Request FULL access',
            expectation:
                'First call shows the full read/write calendar prompt (iOS copy '
                'mentions viewing & managing events). Grant → result "granted".\n\n'
                'After a write-only grant the platforms differ:\n'
                '• Android: NO dialog — READ_CALENDAR shares the CALENDAR '
                'permission group with the already-granted WRITE_CALENDAR, so the '
                'OS escalates to "granted" immediately. (Expected OS behaviour, '
                'not a bug — write-only is a soft boundary on Android.)\n'
                '• iOS: stays "writeOnly"; full access can only be granted from '
                'Settings.',
            actionLabel: 'requestPermissions(full)',
            running: _running.contains('full'),
            result: _results['full'],
            onRun: () => _run('full', () async {
              final status = await DeviceCalendar.instance.requestPermissions();
              return 'status: ${status.name}';
            }),
          ),
          _CheckCard(
            title: 'Request WRITE-ONLY access',
            expectation:
                'iOS 17+: shows the gentler "Add Events Only" prompt (NOT the '
                'full one). Grant → result "writeOnly".\n'
                'iOS 16 and below: no write-only tier exists, so the normal full '
                'prompt appears and a grant returns "granted".\n'
                'Android: requests WRITE_CALENDAR only. Granting write but not '
                'read → "writeOnly".',
            actionLabel: 'requestPermissions(writeOnly)',
            running: _running.contains('writeOnly'),
            result: _results['writeOnly'],
            onRun: () => _run('writeOnly', () async {
              final status = await DeviceCalendar.instance.requestPermissions(
                level: CalendarAccessLevel.writeOnly,
              );
              return 'status: ${status.name}';
            }),
          ),
          _CheckCard(
            title: 'Check status (no prompt)',
            expectation:
                'Never shows a dialog. Returns the current tier: granted, '
                'writeOnly, denied, restricted, or notDetermined. Run this after '
                'toggling access in Settings to confirm the app sees the change.',
            actionLabel: 'hasPermissions()',
            running: _running.contains('has'),
            result: _results['has'],
            onRun: () => _run('has', () async {
              final status = await DeviceCalendar.instance.hasPermissions();
              return 'status: ${status.name}';
            }),
          ),
          const _NoteCard(
            title: 'Missing usage description / manifest entry',
            body:
                'Needs a deliberately mis-configured build, so it is not a '
                'button.\n\n'
                '• iOS write-only: remove NSCalendarsWriteOnlyAccessUsageDescription '
                'from Info.plist, then run "Request write-only". Expect a clear '
                'permissionsNotDeclared error naming that key — not a crash.\n'
                '• iOS add-only app: declare ONLY the write-only key (drop '
                'NSCalendarsUsageDescription). Both "Request write-only" AND '
                '"Check status" must still work.\n'
                '• Android add-only app: declare ONLY WRITE_CALENDAR in the '
                'manifest. "Request write-only" must NOT throw '
                'permissionsNotDeclared.',
          ),
          const SizedBox(height: 8),
          const _SectionHeader(
            'Leaving the app',
            'Opens a system surface outside the app, so the harness loses '
                'control of the process.',
          ),
          _CheckCard(
            title: 'Open app settings',
            expectation:
                'Leaves the app and opens THIS app\'s system settings page, '
                'where calendar access can be toggled (iOS: app settings; '
                'Android: app info / permissions). Returns on back.',
            actionLabel: 'openAppSettings()',
            running: _running.contains('settings'),
            result: _results['settings'],
            onRun: () => _run('settings', () async {
              await DeviceCalendar.instance.openAppSettings();
              return 'opened (verify you left the app)';
            }),
          ),
          const SizedBox(height: 8),
          const _SectionHeader(
            'Native event forms',
            'These present a form drawn by EventKit (iOS) or the system Calendar '
                'app (Android). The harness cannot tap inside system UI, and the '
                'API returns no data — the Future just completes on dismiss.',
          ),
          _CheckCard(
            title: 'Create sample event (setup)',
            expectation:
                'Creates a throwaway event in the first writable calendar so the '
                'View / Edit checks below have something to open. Requires full '
                'access. Result shows the new event id.',
            actionLabel: 'createEvent()',
            running: _running.contains('sample'),
            result: _results['sample'],
            onRun: () => _run('sample', () async {
              final calendar = await _firstWritableCalendar();
              final now = DateTime.now();
              final id = await DeviceCalendar.instance.createEvent(
                calendarId: calendar.id,
                title: 'Manual check sample',
                startDate: now.add(const Duration(hours: 1)),
                endDate: now.add(const Duration(hours: 2)),
                location: 'Manual checks screen',
              );
              setState(() => _sampleEventId = id);
              return 'created in "${calendar.name}" — id: $id';
            }),
          ),
          _CheckCard(
            title: 'Create form — blank',
            expectation:
                'Opens the native CREATE editor (iOS EKEventEditViewController / '
                'Android ACTION_INSERT) with empty fields. Fill + save or cancel; '
                'the OS writes the event. The Future completes on dismiss either '
                'way — no result data is returned.',
            actionLabel: 'showCreateEventModal()',
            running: _running.contains('createBlank'),
            result: _results['createBlank'],
            onRun: () => _run('createBlank', () async {
              await DeviceCalendar.instance.showCreateEventModal();
              return 'dismissed';
            }),
          ),
          _CheckCard(
            title: 'Create form — pre-filled',
            expectation:
                'Same native create editor, pre-populated: title "Lunch", starts '
                '+1h, ends +2h, location "Cafe". Verify every field is pre-filled '
                'and the times look right (correct timezone, not shifted).',
            actionLabel: 'showCreateEventModal(prefilled)',
            running: _running.contains('createPrefilled'),
            result: _results['createPrefilled'],
            onRun: () => _run('createPrefilled', () async {
              final now = DateTime.now();
              await DeviceCalendar.instance.showCreateEventModal(
                title: 'Lunch',
                startDate: now.add(const Duration(hours: 1)),
                endDate: now.add(const Duration(hours: 2)),
                location: 'Cafe',
              );
              return 'dismissed';
            }),
          ),
          _CheckCard(
            title: 'View form (needs sample)',
            expectation:
                'Opens the native VIEW screen for the sample event. NOT '
                'read-only: both platforms expose an Edit affordance from here. '
                'Verify the details match and an Edit button is present.',
            actionLabel: 'showEventModal(edit: false)',
            running: _running.contains('view'),
            result: _results['view'],
            onRun: _sampleEventId == null
                ? null
                : () => _run('view', () async {
                      await DeviceCalendar.instance
                          .showEventModal(_sampleEventId!);
                      return 'dismissed';
                    }),
          ),
          _CheckCard(
            title: 'Edit form (needs sample)',
            expectation:
                'Opens the sample event directly in the native EDITOR. Changes '
                'you save are written by the OS; the Future completes on dismiss '
                'without reporting what changed.\n\n'
                'Android caveat: ACTION_EDIT is honored inconsistently. Google '
                'Calendar opens a BLANK new-event editor (it ignores the event); '
                'the AOSP/stock calendar opens the existing event. For a reliable '
                'edit, use the View form above and tap its edit button. iOS opens '
                'the existing event correctly.',
            actionLabel: 'showEventModal(edit: true)',
            running: _running.contains('edit'),
            result: _results['edit'],
            onRun: _sampleEventId == null
                ? null
                : () => _run('edit', () async {
                      await DeviceCalendar.instance
                          .showEventModal(_sampleEventId!, edit: true);
                      return 'dismissed';
                    }),
          ),
          const SizedBox(height: 8),
          const _SectionHeader(
            'Cross-session / persisted state',
            'Depends on real user interaction across prompts and app launches, '
                'which the harness cannot reproduce deterministically.',
          ),
          const _NoteCard(
            title: 'Permanently-denied flow',
            body:
                'Procedure (use the buttons above):\n'
                '1. Fresh install. "Request full" → deny.\n'
                '2. "Request full" again → on Android the OS may show the prompt '
                'once more; deny again.\n'
                '3. "Check status" now returns "denied" (sticks — not '
                'notDetermined).\n'
                '4. "Request full" no longer shows a dialog; it returns "denied".\n'
                '5. Recover only via "Open app settings".',
          ),
          const _NoteCard(
            title: 'Settings round-trip',
            body:
                'With access granted: "Open app settings", then revoke calendar '
                'access.\n\n'
                'iOS TERMINATES the app the moment you change a privacy '
                'permission for it — this is expected OS behaviour (under a '
                'debugger it shows as "signal SIGKILL"; it is not a crash in the '
                'plugin). Relaunch the app, then "Check status": it must reflect '
                'the revocation (denied / notDetermined), proving the plugin '
                'reads live OS state rather than a cached value.\n\n'
                'Android keeps the process alive — just return and "Check '
                'status".',
          ),
        ],
      ),
    );
  }
}

/// Outcome of a single manual check run.
class _CheckResult {
  const _CheckResult._(this.message, this.isError);

  factory _CheckResult.ok(String message) => _CheckResult._(message, false);
  factory _CheckResult.error(String message) => _CheckResult._(message, true);

  final String message;
  final bool isError;
}

/// A check: an expectation in plain text, an action button, and its last
/// result. A null [onRun] disables the button (e.g. a prerequisite is missing).
class _CheckCard extends StatelessWidget {
  const _CheckCard({
    required this.title,
    required this.expectation,
    required this.actionLabel,
    required this.onRun,
    required this.running,
    required this.result,
  });

  final String title;
  final String expectation;
  final String actionLabel;
  final VoidCallback? onRun;
  final bool running;
  final _CheckResult? result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              expectation,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: running ? null : onRun,
              child: running
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(actionLabel),
            ),
            if (result != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: result!.isError
                      ? theme.colorScheme.errorContainer
                      : theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  result!.message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: result!.isError
                        ? theme.colorScheme.onErrorContainer
                        : theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A documentation-only card for checks that can't be reduced to one tap
/// (they need a special build or a multi-step manual procedure).
class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(body, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Section divider with a heading and a note on why the checks below are
/// manual-only.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, this.subtitle);

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
