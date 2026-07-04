/// A lightweight, pure-Dart implementation of the ChangeNotifier pattern.
/// Allows classes in pure Dart packages to notify listeners without depending on Flutter.
class McpChangeNotifier {
  final List<void Function()> _listeners = [];

  /// Returns true if there are any registered listeners.
  bool get hasListeners => _listeners.isNotEmpty;

  /// Register a closure to be called when the object notifies its listeners.
  void addListener(void Function() listener) {
    _listeners.add(listener);
  }

  /// Remove a previously registered closure from the list of listeners.
  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  /// Call all the registered listeners.
  void notifyListeners() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  /// Discard any resources used by the object. After this is called, the
  /// object is not in a usable state and should be discarded.
  void dispose() {
    _listeners.clear();
  }
}
