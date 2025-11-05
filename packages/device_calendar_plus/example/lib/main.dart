import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Device Calendar Plus Example'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<Calendar> _calendars = [];
  bool _isLoadingCalendars = false;
  final Set<String> _selectedCalendarIds = {};
  List<Event> _events = [];
  bool _isLoadingEvents = false;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _requestPermissions() async {
    try {
      final status = await DeviceCalendar.instance.requestPermissions();

      if (!mounted) return;

      String message;
      switch (status) {
        case CalendarPermissionStatus.granted:
          message = 'Permission granted! Full read/write access to calendars.';
          break;
        case CalendarPermissionStatus.writeOnly:
          message =
              'Write-only permission granted (iOS 17+). Can add events but not read existing ones.';
          break;
        case CalendarPermissionStatus.denied:
          message =
              'Permission denied. Please enable calendar access in Settings.';
          break;
        case CalendarPermissionStatus.restricted:
          message =
              'Calendar access is restricted by device policies (MDM/parental controls).';
          break;
        case CalendarPermissionStatus.notDetermined:
          message = 'Permission not yet determined.';
          break;
      }

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Calendar Permission Status'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } on DeviceCalendarException catch (e) {
      // Developer configuration error (missing manifest permissions)
      if (!mounted) return;

      final title = e.errorCode == DeviceCalendarError.permissionsNotDeclared
          ? 'Configuration Error'
          : 'Calendar Error';

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Text(
              e.message,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      // Other errors
      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Error'),
          content: Text('Failed to request permissions: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _loadCalendars() async {
    setState(() {
      _isLoadingCalendars = true;
    });

    try {
      final calendars = await DeviceCalendar.instance.listCalendars();

      setState(() {
        _calendars = calendars;
        _isLoadingCalendars = false;
      });
    } on DeviceCalendarException catch (e) {
      setState(() {
        _isLoadingCalendars = false;
      });

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Calendar Error'),
          content: Text(e.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      setState(() {
        _isLoadingCalendars = false;
      });

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Error'),
          content: Text('Failed to load calendars: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Color _parseColor(String? colorHex) {
    if (colorHex == null || colorHex.isEmpty) {
      return Colors.grey;
    }
    try {
      final hexColor = colorHex.replaceAll('#', '');
      return Color(int.parse('FF$hexColor', radix: 16));
    } catch (e) {
      return Colors.grey;
    }
  }

  Future<void> _loadEvents() async {
    setState(() {
      _isLoadingEvents = true;
    });

    try {
      final now = DateTime.now();
      final startDate = DateTime(now.year, now.month - 3, now.day);
      final endDate = DateTime(now.year, now.month + 3, now.day);

      final events = await DeviceCalendar.instance.listEvents(
        startDate,
        endDate,
        calendarIds:
            _selectedCalendarIds.isEmpty ? null : _selectedCalendarIds.toList(),
      );

      setState(() {
        _events = events;
        _isLoadingEvents = false;
      });
    } on DeviceCalendarException catch (e) {
      setState(() {
        _isLoadingEvents = false;
      });

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Calendar Error'),
          content: Text(e.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      setState(() {
        _isLoadingEvents = false;
      });

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Error'),
          content: Text('Failed to load events: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _updateEvent(Event event) async {
    try {
      // Add an exclamation mark to the title
      final newTitle = '${event.title}!';

      await DeviceCalendar.instance.updateEvent(
        eventId: event.instanceId,
        title: newTitle,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Updated: $newTitle'),
          duration: const Duration(seconds: 2),
        ),
      );

      // Reload events to show the change
      await _loadEvents();
    } on DeviceCalendarException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update event: $e')),
      );
    }
  }

  Future<void> _deleteEvent(Event event) async {
    try {
      await DeviceCalendar.instance.deleteEvent(eventId: event.instanceId);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deleted: ${event.title}'),
          duration: const Duration(seconds: 2),
        ),
      );

      // Reload events to show the change
      await _loadEvents();
    } on DeviceCalendarException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete event: $e')),
      );
    }
  }

  Future<void> _showEventDetails(Event event) async {
    try {
      // Fetch the specific event instance using instanceId
      // For recurring events, instanceId includes the timestamp
      final fetchedEvent = await DeviceCalendar.instance.getEvent(
        event.instanceId,
      );

      if (fetchedEvent == null) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Error'),
            content: const Text('Event not found'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      if (!mounted) return;

      final calendar = _calendars.firstWhere(
        (c) => c.id == fetchedEvent.calendarId,
        orElse: () => _calendars.first,
      );

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(fetchedEvent.title),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDetailRow(
                  Icons.calendar_today,
                  'Calendar',
                  calendar.name,
                ),
                const SizedBox(height: 12),
                _buildDetailRow(
                  Icons.access_time,
                  'Time',
                  fetchedEvent.isAllDay
                      ? 'All Day'
                      : '${_formatEventDate(fetchedEvent.startDate)} • ${_formatEventTime(fetchedEvent)}',
                ),
                if (fetchedEvent.location != null) ...[
                  const SizedBox(height: 12),
                  _buildDetailRow(
                    Icons.location_on,
                    'Location',
                    fetchedEvent.location!,
                  ),
                ],
                if (fetchedEvent.description != null) ...[
                  const SizedBox(height: 12),
                  _buildDetailRow(
                    Icons.notes,
                    'Description',
                    fetchedEvent.description!,
                  ),
                ],
                if (fetchedEvent.timeZone != null) ...[
                  const SizedBox(height: 12),
                  _buildDetailRow(
                    Icons.public,
                    'Timezone',
                    fetchedEvent.timeZone!,
                  ),
                ],
                if (fetchedEvent.isRecurring) ...[
                  const SizedBox(height: 12),
                  _buildDetailRow(
                    Icons.repeat,
                    'Recurring',
                    'Yes',
                  ),
                ],
                const SizedBox(height: 12),
                _buildDetailRow(
                  Icons.info_outline,
                  'Status',
                  '${fetchedEvent.status.name} • ${fetchedEvent.availability.name}',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                try {
                  await DeviceCalendar.instance
                      .showEventModal(fetchedEvent.instanceId);
                } on DeviceCalendarException catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: ${e.message}')),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to show event: $e')),
                  );
                }
              },
              child: const Text('Show in Modal'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } on DeviceCalendarException catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Calendar Error'),
          content: Text(e.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Error'),
          content: Text('Failed to load event details: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatEventTime(Event event) {
    if (event.isAllDay) {
      return 'All Day';
    }
    final startTime =
        '${event.startDate.hour.toString().padLeft(2, '0')}:${event.startDate.minute.toString().padLeft(2, '0')}';
    final endTime =
        '${event.endDate.hour.toString().padLeft(2, '0')}:${event.endDate.minute.toString().padLeft(2, '0')}';
    return '$startTime - $endTime';
  }

  String _formatEventDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eventDay = DateTime(date.year, date.month, date.day);

    if (eventDay == today) {
      return 'Today';
    } else if (eventDay == today.add(const Duration(days: 1))) {
      return 'Tomorrow';
    } else if (eventDay == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    } else {
      final months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ];
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text('Permissions'),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _requestPermissions,
                      child: const Text('Request Calendar Permissions'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Calendars',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (_calendars.isNotEmpty)
                          Text(
                            '${_calendars.length} found',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _isLoadingCalendars ? null : _loadCalendars,
                      icon: _isLoadingCalendars
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: Text(_isLoadingCalendars
                          ? 'Loading...'
                          : 'Load Calendars'),
                    ),
                    if (_calendars.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Select calendars to fetch events:',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _calendars.map((calendar) {
                          final color = _parseColor(calendar.colorHex);
                          final luminance = color.computeLuminance();
                          final textColor =
                              luminance > 0.5 ? Colors.black : Colors.white;
                          final isSelected =
                              _selectedCalendarIds.contains(calendar.id);

                          return FilterChip(
                            selected: isSelected,
                            backgroundColor: color.withValues(alpha: 0.3),
                            selectedColor: color,
                            checkmarkColor: textColor,
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  calendar.name,
                                  style: TextStyle(
                                    color: isSelected ? textColor : null,
                                    fontWeight: calendar.isPrimary
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                                if (calendar.isPrimary) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.star,
                                    size: 14,
                                    color: isSelected ? textColor : null,
                                  ),
                                ],
                                if (calendar.readOnly) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.lock,
                                    size: 14,
                                    color: isSelected ? textColor : null,
                                  ),
                                ],
                              ],
                            ),
                            avatar: calendar.accountName != null
                                ? CircleAvatar(
                                    backgroundColor: isSelected
                                        ? color.withValues(alpha: 0.3)
                                        : color.withValues(alpha: 0.2),
                                    child: Text(
                                      calendar.accountName![0].toUpperCase(),
                                      style: TextStyle(
                                        color: isSelected ? textColor : null,
                                        fontSize: 12,
                                      ),
                                    ),
                                  )
                                : null,
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _selectedCalendarIds.add(calendar.id);
                                } else {
                                  _selectedCalendarIds.remove(calendar.id);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_calendars.isNotEmpty) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Events',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          if (_events.isNotEmpty)
                            Text(
                              '${_events.length} found',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'From 3 months ago to 3 months ahead',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _isLoadingEvents ? null : _loadEvents,
                        icon: _isLoadingEvents
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.event),
                        label: Text(_isLoadingEvents
                            ? 'Loading...'
                            : _selectedCalendarIds.isEmpty
                                ? 'Fetch Events (All calendars)'
                                : 'Fetch Events (${_selectedCalendarIds.length} selected)'),
                      ),
                      if (_events.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 400,
                          child: ListView.separated(
                            itemCount: _events.length,
                            separatorBuilder: (context, index) =>
                                const Divider(),
                            itemBuilder: (context, index) {
                              final event = _events[index];
                              final calendar = _calendars.firstWhere(
                                (c) => c.id == event.calendarId,
                                orElse: () => _calendars.first,
                              );
                              final color = _parseColor(calendar.colorHex);

                              return ListTile(
                                onTap: () => _showEventDetails(event),
                                leading: Container(
                                  width: 4,
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                title: Text(
                                  event.title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w500),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text(
                                      '${_formatEventDate(event.startDate)} • ${_formatEventTime(event)}',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                    if (event.timeZone != null) ...[
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          const Icon(Icons.access_time,
                                              size: 12),
                                          const SizedBox(width: 4),
                                          Text(
                                            event.timeZone!,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  fontStyle: FontStyle.italic,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    if (event.location != null) ...[
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          const Icon(Icons.location_on,
                                              size: 12),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              event.location!,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    const SizedBox(height: 2),
                                    Text(
                                      calendar.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: color,
                                          ),
                                    ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (event.isAllDay)
                                      const Icon(Icons.all_inclusive, size: 16),
                                    if (event.status == EventStatus.tentative)
                                      const Icon(Icons.help_outline, size: 16),
                                    if (event.status == EventStatus.canceled)
                                      const Icon(Icons.cancel_outlined,
                                          size: 16),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(Icons.edit, size: 18),
                                      onPressed: () => _updateEvent(event),
                                      tooltip: 'Update',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, size: 18),
                                      onPressed: () => _deleteEvent(event),
                                      tooltip: 'Delete',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
