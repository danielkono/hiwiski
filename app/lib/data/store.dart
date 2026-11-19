import 'package:flutter/foundation.dart';

/// State that several screens share, kept below them in the Model:
/// the filters, the preferences, the session.
///
/// Read synchronously and announced at once — a screen that has just changed it reads
/// the new value right away, not one cycle later. The composition root
/// hands it to the ViewModels as a provider (`app/stores.dart`).
abstract class Store<T> extends ChangeNotifier implements ValueListenable<T> {
  Store(this._value);

  T _value;

  @override
  T get value => _value;

  @protected
  set value(T next) {
    if (identical(next, _value)) return;
    _value = next;
    notifyListeners();
  }
}
