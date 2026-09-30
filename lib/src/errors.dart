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

  /// The persisted query behind this call is retired: the API no longer serves it (gateway `query_retired`,
  /// HTTP 410).
  queryRetired,
  decoding,
  unknown
}

/// A recoverable failure carried in `Failure`.
class SpiderError implements Exception {
  final SpiderErrorCode code;
  final String message;
  final int? httpStatus;
  final String? serverCode;

  /// For a [SpiderErrorCode.badRequest] (an input the SDK rejects before sending, or one the server rejects as
  /// missing, invalid or out of range), the offending input when one is named, by its wire name (e.g.
  /// `maxWindow` for `maxWindowMinutes`, `timeRange` for `timeRangeSeconds`). Null otherwise.
  final String? field;
  final Object? cause;

  const SpiderError(this.code, this.message,
      {this.httpStatus, this.serverCode, this.field, this.cause});

  @override
  String toString() => 'SpiderError(${code.name}: $message)';
}

// Internal transport errors, mapped to SpiderError by [toSpiderError].
enum TransportErrorKind { http, noData, upstream, badRequest, queryRetired }

class TransportError implements Exception {
  final TransportErrorKind kind;
  final String message;
  final int? httpStatus;
  final String? serverCode;

  /// The offending input field the server named, if any: for [TransportErrorKind.badRequest], or an HTTP 400.
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

/// A [SpiderErrorCode.badRequest] the SDK raises before sending. [field] is the wire name, and the message
/// names only it (`<field> is out of range`, or `<field> is invalid` when [malformed]), never the value or limit.
SpiderError invalidInput(String field, {bool malformed = false}) => SpiderError(
    SpiderErrorCode.badRequest,
    malformed ? '$field is invalid' : '$field is out of range',
    field: field);

/// Maps any thrown error into the public [SpiderError] taxonomy. Mirrors the TS SDK's `toSpiderError`.
SpiderError toSpiderError(Object error) {
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
      case TransportErrorKind.queryRetired:
        return SpiderError(SpiderErrorCode.queryRetired, error.message,
            httpStatus: error.httpStatus, serverCode: error.serverCode);
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
