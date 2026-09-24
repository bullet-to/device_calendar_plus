import 'dart:ui' show Color;

/// Parses a hex color string into a [Color].
///
/// Accepts `#RRGGBB` or `#AARRGGBB` (the `#` prefix is optional). 6-digit
/// values are treated as fully opaque; 8-digit values keep their own alpha.
/// Returns `null` when [hex] is `null` or unparseable.
///
/// Package-internal: shared by `Calendar.color` and `Event.color`.
Color? colorFromHex(String? hex) {
  if (hex == null) return null;
  final cleaned = hex.startsWith('#') ? hex.substring(1) : hex;
  final value = int.tryParse(cleaned, radix: 16);
  if (value == null) return null;
  return Color(cleaned.length == 6 ? value | 0xFF000000 : value);
}

final RegExp _writableHex = RegExp(r'^#?[0-9a-fA-F]{6}$');

/// Throws [ArgumentError] unless [hex] is `#RRGGBB` (the `#` optional): the
/// one form both platforms store the same way and [colorFromHex] reads back.
/// Anything else used to reach the platform and be stored silently as black
/// (#126). An alpha byte is deliberately not a write form — iOS drops it and
/// Android stores it, so the platforms would disagree on what was written.
///
/// Package-internal: shared by `createCalendar` and `updateCalendar`.
void validateColorHex(String hex) {
  if (!_writableHex.hasMatch(hex.trim())) {
    throw ArgumentError.value(
      hex,
      'colorHex',
      'Expected a hex color like #RRGGBB',
    );
  }
}
