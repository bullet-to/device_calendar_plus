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
  String _platformVersion = 'Unknown';
  List<Calendar> _calendars = [];
  bool _isLoadingCalendars = false;

  @override
  void initState() {
    super.initState();
    _getPlatformVersion();
  }

  Future<void> _getPlatformVersion() async {
    final version = await DeviceCalendarPlugin.getPlatformVersion();
    setState(() {
      _platformVersion = version ?? 'Unknown';
    });
  }

  Future<void> _requestPermissions() async {
    try {
      final status = await DeviceCalendarPlugin.requestPermissions();

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
      final calendars = await DeviceCalendarPlugin.listCalendars();

      print('Calendars: $calendars');

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
                    const Text('Platform Info'),
                    const SizedBox(height: 8),
                    Text(
                      _platformVersion,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _getPlatformVersion,
                      child: const Text('Refresh Platform Version'),
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
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _calendars.map((calendar) {
                          final color = _parseColor(calendar.colorHex);
                          final luminance = color.computeLuminance();
                          final textColor =
                              luminance > 0.5 ? Colors.black : Colors.white;

                          return Chip(
                            backgroundColor: color,
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  calendar.name,
                                  style: TextStyle(
                                    color: textColor,
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
                                    color: textColor,
                                  ),
                                ],
                                if (calendar.readOnly) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.lock,
                                    size: 14,
                                    color: textColor,
                                  ),
                                ],
                                if (calendar.hidden) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.visibility_off,
                                    size: 14,
                                    color: textColor,
                                  ),
                                ],
                              ],
                            ),
                            avatar: calendar.accountName != null
                                ? CircleAvatar(
                                    backgroundColor:
                                        color.withValues(alpha: 0.3),
                                    child: Text(
                                      calendar.accountName![0].toUpperCase(),
                                      style: TextStyle(
                                        color: textColor,
                                        fontSize: 12,
                                      ),
                                    ),
                                  )
                                : null,
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
