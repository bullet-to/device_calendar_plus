import 'package:device_calendar_plus_platform_interface/device_calendar_plus_platform_interface.dart';

/// Throws [ArgumentError] when [value] is empty or whitespace: an empty id
/// or name targets nothing, so no correct behaviour exists (error-handling.md).
///
/// [name] is the parameter name the error reports; [label] is the human label
/// in its message (`'$label cannot be empty'`).
///
/// Package-internal: shared by every mutation on `DeviceCalendar`.
void requireNonBlank(
  String value, {
  required String name,
  required String label,
}) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, '$label cannot be empty');
  }
}

/// Throws [ArgumentError] when any of [attendees] has a blank email: an
/// attendee row with no address invites no one, so no correct behaviour
/// exists. Checked on every platform, though only Android writes them: the
/// mistake is the caller's either way.
void requireAttendeeEmails(List<AttendeeWriteAndroid>? attendees) {
  for (final attendee in attendees ?? const <AttendeeWriteAndroid>[]) {
    requireNonBlank(attendee.email, name: 'attendees', label: 'Attendee email');
  }
}

/// [requireAttendeeEmails] for an update's attendees [patch]: the list a
/// [PatchSet] writes. A clear or no patch writes no address to check.
void requireAttendeePatchEmails(Patch<List<AttendeeWriteAndroid>>? patch) {
  if (patch case PatchSet(:final value)) requireAttendeeEmails(value);
}
