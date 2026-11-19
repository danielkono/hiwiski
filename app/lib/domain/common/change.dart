/// A new value for a field that may be empty, in a partial update.
///
/// Updates take one optional parameter per field: left out, the field stays as it is.
/// For a field that can be empty that is not enough — `null` would mean both "leave
/// it" and "clear it". `Change(null)` clears it, `Change(value)` sets it, no `Change`
/// leaves it.
final class const Change<T>(final T value);
