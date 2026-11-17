import 'result.dart';

/// One plain sentence per failure. Never includes the token.
String describeFailure(Failure f) => switch (f) {
  NotConfiguredFailure() => 'Add the sheet URL and token in Settings.',
  UnauthorisedFailure() => 'Token rejected. Check it in Settings.',
  TimeoutFailure() => 'The sheet took longer than 20 s. Will retry.',
  NetworkFailure() => 'Offline. Changes are saved and will sync.',
  ServerFailure(:final message) => 'Sheet error: $message',
  ParseFailure(:final message) => 'Unexpected reply from the sheet ($message).',
};
