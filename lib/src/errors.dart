import 'dart:async';
import 'package:http/http.dart' as http;

/// The stable failure taxonomy shared with the other Spider SDKs. Branch on [code].
enum SpiderErrorCode {
  network,
  timeout,
  unauthorized,
  badRequest,
  notFound,
  server,
  rateLimited,
  decoding,
  unknown
}

/// A recoverable failure carried in `Failure`.
class SpiderError implements Exception {
  final SpiderErrorCode code;
  final String message;
  final int? httpStatus;
  final String? serverCode;

  /// For a [SpiderErrorCode.badRequest] (a server validation failure — over-cap `searchWindow`, malformed
  /// `via`, or a missing required field), the offending input field when the server names one. Null otherwise.
  final String? field;
  final Object? cause;

  const SpiderError(this.code, this.message,
      {this.httpStatus, this.serverCode, this.field, this.cause});

  @override
  String toString() => 'SpiderError(${code.name}: $message)';
}

/// Thrown (never returned) when the gateway declares a different MAJOR contract version than this SDK speaks.
class SpiderContractMismatchError implements Exception {
  final String expected;
  final String actual;

  const SpiderContractMismatchError(this.expected, this.actual);

  String get message =>
      'Spider contract mismatch: this SDK speaks $expected but the gateway declared $actual';

  @override
  String toString() => message;
}

// Internal transport errors, mapped to SpiderError by [toSpiderError].
enum TransportErrorKind { http, noData, upstream, badRequest }

class TransportError implements Exception {
  final TransportErrorKind kind;
  final String message;
  final int? httpStatus;
  final String? serverCode;

  /// Set only for [TransportErrorKind.badRequest]: the offending input field the server named, if any.
  final String? field;

  const TransportError(this.kind, this.message,
      {this.httpStatus, this.serverCode, this.field});
}

class SpiderDecodingError implements Exception {
  final String message;
  final Object cause;

  const SpiderDecodingError(this.message, this.cause);
}

/// A parsed server error envelope: a stable machine `code` and a human `message`, either possibly absent.
class ErrorEnvelope {
  final String? code;
  final String? message;
  const ErrorEnvelope(this.code, this.message);
}

/// Maps any thrown error into the public [SpiderError] taxonomy. Mirrors the TS SDK's `toSpiderError`.
SpiderError toSpiderError(Object error) {
  if (error is TransportError) {
    switch (error.kind) {
      case TransportErrorKind.http:
        final status = error.httpStatus ?? 0;
        final code = switch (status) {
          401 || 403 => SpiderErrorCode.unauthorized,
          404 => SpiderErrorCode.notFound,
          408 || 504 => SpiderErrorCode.timeout,
          429 => SpiderErrorCode.rateLimited,
          >= 500 && <= 599 => SpiderErrorCode.server,
          _ => SpiderErrorCode.unknown,
        };
        return SpiderError(code, error.message,
            httpStatus: status, serverCode: error.serverCode);
      case TransportErrorKind.noData:
        return SpiderError(SpiderErrorCode.notFound, error.message);
      case TransportErrorKind.badRequest:
        return SpiderError(SpiderErrorCode.badRequest, error.message,
            field: error.field);
      case TransportErrorKind.upstream:
        return SpiderError(SpiderErrorCode.server, error.message);
    }
  }
  if (error is SpiderDecodingError) {
    return SpiderError(SpiderErrorCode.decoding, error.message,
        cause: error.cause);
  }
  if (error is TimeoutException) {
    return SpiderError(
        SpiderErrorCode.timeout, error.message ?? 'request timed out',
        cause: error);
  }
  // package:http surfaces connection/DNS failures as ClientException on every platform (incl. web).
  if (error is http.ClientException) {
    return SpiderError(SpiderErrorCode.network, error.message, cause: error);
  }
  return SpiderError(SpiderErrorCode.unknown, error.toString(), cause: error);
}
