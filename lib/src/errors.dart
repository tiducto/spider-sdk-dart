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

  /// The project has reached its plan's trip planning limit, so trip planning (`plan`, `planStream`) is refused;
  /// the other calls still work (gateway `planning_limit_reached`).
  planningLimitReached,

  /// The project has no active agreement, so every call made with the key is refused (gateway
  /// `agreement_inactive`).
  agreementInactive,
  decoding,
  unknown
}

/// A recoverable failure carried in `Failure`.
class SpiderError implements Exception {
  final SpiderErrorCode code;
  final String message;
  final int? httpStatus;
  final String? serverCode;

  /// The rejected input of a [SpiderErrorCode.badRequest] as a wire dot path (e.g. `maxWindow`), else null.
  final String? field;
  final Object? cause;

  const SpiderError(this.code, this.message,
      {this.httpStatus, this.serverCode, this.field, this.cause});

  @override
  String toString() => 'SpiderError(${code.name}: $message)';
}

// Internal transport errors, mapped to SpiderError by [toSpiderError].
enum TransportErrorKind {
  http,
  noData,
  upstream,
  planningLimitReached,
  agreementInactive
}

class TransportError implements Exception {
  final TransportErrorKind kind;
  final String message;
  final int? httpStatus;
  final String? serverCode;

  /// The offending input field an HTTP 400 names, if any.
  final String? field;

  const TransportError(this.kind, this.message,
      {this.httpStatus, this.serverCode, this.field});
}

class SpiderDecodingError implements Exception {
  final String message;
  final Object cause;

  const SpiderDecodingError(this.message, this.cause);
}

/// A parsed error body: the contract's `code`, `message` and `field`, and the gateway's `error`.
class ErrorEnvelope {
  final String? code;
  final String? message;
  final String? field;
  final String? error;
  const ErrorEnvelope({this.code, this.message, this.field, this.error});
}

/// A [SpiderErrorCode.badRequest] the SDK raises before sending. [field] is the wire name, and the message
/// names only it (`<field> is out of range`, or `<field> is invalid` when [malformed]), never the value or limit.
SpiderError invalidInput(String field, {bool malformed = false}) => SpiderError(
    SpiderErrorCode.badRequest,
    malformed ? '$field is invalid' : '$field is out of range',
    field: field);

/// A [SpiderErrorCode.badRequest] the SDK raises before sending when the required [field] is empty.
SpiderError missingInput(String field) =>
    SpiderError(SpiderErrorCode.badRequest, '$field is required', field: field);

/// Maps any thrown error into the public [SpiderError] taxonomy. Mirrors the TS SDK's `toSpiderError`.
SpiderError toSpiderError(Object error) {
  if (error is SpiderError) return error;
  if (error is TransportError) {
    switch (error.kind) {
      case TransportErrorKind.http:
        final status = error.httpStatus ?? 0;
        final code = switch (status) {
          400 => SpiderErrorCode.badRequest,
          401 || 403 => SpiderErrorCode.unauthorized,
          404 => SpiderErrorCode.notFound,
          408 || 504 => SpiderErrorCode.timeout,
          429 => SpiderErrorCode.rateLimited,
          >= 500 && <= 599 => SpiderErrorCode.server,
          _ => SpiderErrorCode.unknown,
        };
        return SpiderError(code, error.message,
            httpStatus: status,
            serverCode: error.serverCode,
            field: error.field);
      case TransportErrorKind.planningLimitReached:
        return SpiderError(SpiderErrorCode.planningLimitReached, error.message,
            httpStatus: error.httpStatus, serverCode: error.serverCode);
      case TransportErrorKind.agreementInactive:
        return SpiderError(SpiderErrorCode.agreementInactive, error.message,
            httpStatus: error.httpStatus, serverCode: error.serverCode);
      case TransportErrorKind.noData:
        return SpiderError(SpiderErrorCode.notFound, error.message);
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
