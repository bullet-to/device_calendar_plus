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
