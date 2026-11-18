/// App-wide switches.
abstract final class FeatureFlags {
  /// The one switch for every write path: Today's +1 tiles, Quick log and
  /// its FAB, the bus Board/Arrived card, Study and Bus mode, undo, outbox
  /// enqueueing and outbox flushing. Off (the default since Phase 7) makes
  /// the app a read-only viewer of the Events tab: no screen can create,
  /// edit or void an event, and Today/Study are not in the shell.
  ///
  /// Turn it back on with `--dart-define=LOGGING=true`. Tests that exercise
  /// the logging paths set it directly.
  static bool logging = const bool.fromEnvironment('LOGGING');
}

/// Thrown when something tries to write while [FeatureFlags.logging] is off.
class ReadOnlyError extends StateError {
  ReadOnlyError() : super('Read-only build: logging is switched off.');
}
