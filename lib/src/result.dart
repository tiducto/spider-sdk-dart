import 'errors.dart';

/// The result of every SDK call. Ordinary failures never throw — they surface as [Failure]. The one
/// exception is a major contract mismatch, which throws [SpiderContractMismatchError] out of the call.
sealed class SpiderResult<T> {
  const SpiderResult();

  /// True for [Success].
  bool get isSuccess => this is Success<T>;

  /// The value on success, else null.
  T? get valueOrNull => switch (this) {
        Success<T>(:final value) => value,
        Failure<T>() => null,
      };

  /// The error on failure, else null.
  SpiderError? get errorOrNull => switch (this) {
        Success<T>() => null,
        Failure<T>(:final error) => error,
      };
}

/// A successful result carrying [value].
final class Success<T> extends SpiderResult<T> {
  final T value;
  const Success(this.value);
}

/// A failed result carrying [error].
final class Failure<T> extends SpiderResult<T> {
  final SpiderError error;
  const Failure(this.error);
}
