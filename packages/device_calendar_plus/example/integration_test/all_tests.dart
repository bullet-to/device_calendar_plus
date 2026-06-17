import 'attendee_test.dart' as attendee;
import 'device_calendar_test.dart' as device_calendar;
import 'edge_cases_test.dart' as edge_cases;
import 'range_test.dart' as range;
import 'recurrence_test.dart' as recurrence;
import 'reminders_test.dart' as reminders;
import 'sources_test.dart' as sources;

void main() {
  device_calendar.main();
  recurrence.main();
  attendee.main();
  sources.main();
  range.main();
  edge_cases.main();
  reminders.main();
}
