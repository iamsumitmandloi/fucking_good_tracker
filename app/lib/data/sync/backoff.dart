import 'dart:math' as math;

const maxBackoff = Duration(minutes: 5);

/// 2^attempt seconds (attempt 1 → 2 s), capped at 5 minutes.
Duration backoffFor(int attempt) {
  if (attempt <= 0) return Duration.zero;
  final secs = math.pow(2, math.min(attempt, 16)).toInt();
  final d = Duration(seconds: secs);
  return d > maxBackoff ? maxBackoff : d;
}
