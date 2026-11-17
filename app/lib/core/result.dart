/// Typed failures for anything that talks to the sheet.
sealed class Failure {
  const Failure(this.message);

  final String message;

  /// Whether the outbox should retry with backoff.
  bool get retryable;

  @override
  String toString() => '$runtimeType($message)';
}

/// No connection, DNS failure, socket closed, 5xx.
final class NetworkFailure extends Failure {
  const NetworkFailure(super.message);
  @override
  bool get retryable => true;
}

/// No reply within the timeout.
final class TimeoutFailure extends Failure {
  const TimeoutFailure() : super('timed out');
  @override
  bool get retryable => true;
}

/// `{ok:false, error:"unauthorised"}`. Retrying won't help until the token changes.
final class UnauthorisedFailure extends Failure {
  const UnauthorisedFailure() : super('unauthorised');
  @override
  bool get retryable => false;
}

/// `{ok:false, error:<anything else>}`.
final class ServerFailure extends Failure {
  const ServerFailure(super.message);
  @override
  bool get retryable => true;
}

/// Reply was not the JSON we expected (e.g. an HTML error page).
final class ParseFailure extends Failure {
  const ParseFailure(super.message);
  @override
  bool get retryable => true;
}

/// URL or token missing.
final class NotConfiguredFailure extends Failure {
  const NotConfiguredFailure() : super('sheet URL or token not set');
  @override
  bool get retryable => false;
}

sealed class Result<T> {
  const Result();

  bool get isOk => this is Ok<T>;

  R fold<R>(R Function(T value) ok, R Function(Failure failure) err) =>
      switch (this) {
        Ok<T>(:final value) => ok(value),
        Err<T>(:final failure) => err(failure),
      };
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.failure);
  final Failure failure;
}
