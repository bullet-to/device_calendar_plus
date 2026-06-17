/// A partial-update instruction for an optional, clearable field.
///
/// `updateEvent` follows the convention that a `null` argument means "leave
/// this field unchanged". That leaves no way to express "remove the field's
/// value". [Patch] adds the missing third state:
///
/// - argument omitted / `null` — leave the field unchanged
/// - [Patch.set] — set the field to a new value
/// - [Patch.clear] — remove the field's value
sealed class Patch<T> {
  const Patch();

  /// Sets the field to [value].
  const factory Patch.set(T value) = PatchSet<T>;

  /// Clears the field, removing any existing value.
  const factory Patch.clear() = PatchClear<T>;
}

/// A [Patch] that sets the field to [value].
final class PatchSet<T> extends Patch<T> {
  const PatchSet(this.value);

  /// The new value for the field.
  final T value;

  @override
  bool operator ==(Object other) =>
      other is PatchSet<T> && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// A [Patch] that clears the field.
final class PatchClear<T> extends Patch<T> {
  const PatchClear();

  @override
  bool operator ==(Object other) => other is PatchClear<T>;

  @override
  int get hashCode => (PatchClear<T>).hashCode;
}

/// Writes patchable fields into a method-channel argument map.
///
/// For each entry: a [PatchSet] adds `key: value`; a [PatchClear] appends the
/// key to the `clearedFields` list; a `null` patch is omitted entirely. The
/// platform side treats a key listed in `clearedFields` as "remove", a present
/// key as "set", and an absent key as "leave unchanged".
///
/// Values cross the channel as dynamic, so fields of any serializable type
/// (strings, `List<int>` reminder offsets, …) share the one path.
void writePatchFields(
  Map<String, dynamic> args,
  Map<String, Patch<Object?>?> fields,
) {
  final cleared = <String>[];
  for (final entry in fields.entries) {
    switch (entry.value) {
      case null:
        break;
      case PatchSet(:final value):
        args[entry.key] = value;
      case PatchClear():
        cleared.add(entry.key);
    }
  }
  args['clearedFields'] = cleared;
}
