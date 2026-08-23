import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'contract/contract_version.dart';
import 'contract/persisted_queries.dart';
import 'errors.dart';
import 'identity.dart';

/// The HTTP boundary the SDK depends on. Production uses [DefaultSpiderHttpClient]; tests inject their own.
abstract class SpiderHttpClient {
  Future<SpiderHttpResponse> send(SpiderHttpRequest request);
}

class SpiderHttpRequest {
  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String? body;
  const SpiderHttpRequest(this.method, this.uri, this.headers, this.body);
}

class SpiderHttpResponse {
  final int statusCode;
  final Map<String, String> headers; // lower-cased keys
  final String body;
  const SpiderHttpResponse(this.statusCode, this.headers, this.body);
}

/// Default [SpiderHttpClient] backed by `package:http` (works on mobile, desktop, and web).
class DefaultSpiderHttpClient implements SpiderHttpClient {
  final http.Client _client;
  DefaultSpiderHttpClient([http.Client? client])
      : _client = client ?? http.Client();

  @override
  Future<SpiderHttpResponse> send(SpiderHttpRequest request) async {
    final req = http.Request(request.method, request.uri);
    req.headers.addAll(request.headers);
    if (request.body != null) req.body = request.body!;
    final streamed = await _client.send(req);
    final resp = await http.Response.fromStream(streamed);
    return SpiderHttpResponse(resp.statusCode, resp.headers, resp.body);
  }
}

class RetryConfig {
  final int maxAttempts;
  const RetryConfig(this.maxAttempts);
}

/// Translates SDK calls into HTTP against the gateway: identity headers, the persisted-query body shape,
/// the contract-version response check, and the retry/backoff loop.
class Transport {
  final String baseUrl;
  final String apiKey;
  final SpiderHttpClient httpClient;
  final Duration timeout;
  final RetryConfig? retry;

  Transport({
    required String baseUrl,
    required this.apiKey,
    required this.httpClient,
    required this.timeout,
    this.retry,
  }) : baseUrl = _stripTrailingSlashes(baseUrl);

  Map<String, String> _headers({bool json = false}) => {
        'apikey': apiKey,
        contractHeader: contractVersion,
        sdkHeader: sdkIdentity,
        if (json) 'content-type': 'application/json',
      };

  /// Persisted-query POST: `{ id, variables }` to `/routing/{op.path}`.
  Future<D> graphql<D>(PersistedOp op, Map<String, dynamic> variables,
      D Function(Map<String, dynamic>) fromJson) async {
    final resp = await _send(SpiderHttpRequest(
      'POST',
      Uri.parse('$baseUrl/routing/${op.path}'),
      _headers(json: true),
      jsonEncode({'id': op.id, 'variables': variables}),
    ));
    checkContract(resp.headers[contractHeader]);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final env = _parseErrorEnvelope(resp.body);
      final detail = env.message ?? _trunc(resp.body);
      throw TransportError(TransportErrorKind.http,
          'routing ${op.path} -> ${resp.statusCode}: $detail',
          httpStatus: resp.statusCode, serverCode: env.code);
    }
    final decoded = _decodeJson(resp.body, 'routing ${op.path}');
    final errors = decoded['errors'];
    if (errors is List && errors.isNotEmpty) {
      // A BAD_REQUEST extension (over-cap searchWindow, bad via, missing required field) → typed badRequest;
      // anything else stays a generic upstream (→ server).
      for (final e in errors) {
        final ext = e is Map ? e['extensions'] : null;
        if (ext is Map && ext['code'] == 'BAD_REQUEST') {
          throw TransportError(TransportErrorKind.badRequest,
              (e as Map)['message']?.toString() ?? 'bad request',
              field: ext['field'] as String?);
        }
      }
      final joined = errors.map((e) => (e as Map)['message']).join(', ');
      throw TransportError(
          TransportErrorKind.upstream, 'routing ${op.path} errors: $joined');
    }
    final data = decoded['data'];
    if (data == null) {
      throw TransportError(
          TransportErrorKind.noData, 'routing ${op.path} returned no data');
    }
    return fromJson(data as Map<String, dynamic>);
  }

  Future<D> postJson<D>(String path, Map<String, dynamic> body,
      D Function(Map<String, dynamic>) fromJson,
      {String Function(String)? errorMessage}) async {
    final resp = await _send(SpiderHttpRequest('POST',
        Uri.parse('$baseUrl$path'), _headers(json: true), jsonEncode(body)));
    checkContract(resp.headers[contractHeader]);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final env = _parseErrorEnvelope(resp.body);
      final message =
          errorMessage?.call(resp.body) ?? env.message ?? _trunc(resp.body);
      throw TransportError(
          TransportErrorKind.http, 'POST $path -> ${resp.statusCode}: $message',
          httpStatus: resp.statusCode, serverCode: env.code);
    }
    return fromJson(_decodeJson(resp.body, 'POST $path'));
  }

  Future<SpiderHttpResponse> getRaw(String path,
      {Map<String, String> query = const {}}) async {
    final uri = Uri.parse('$baseUrl$path')
        .replace(queryParameters: query.isEmpty ? null : query);
    final resp = await _send(SpiderHttpRequest('GET', uri, _headers(), null));
    checkContract(resp.headers[contractHeader]);
    return resp;
  }

  Future<D> getJson<D>(String path, D Function(Map<String, dynamic>) fromJson,
      {Map<String, String> query = const {}}) async {
    final resp = await getRaw(path, query: query);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final env = _parseErrorEnvelope(resp.body);
      final detail = env.message ?? _trunc(resp.body);
      throw TransportError(
          TransportErrorKind.http, 'GET $path -> ${resp.statusCode}: $detail',
          httpStatus: resp.statusCode, serverCode: env.code);
    }
    return fromJson(_decodeJson(resp.body, 'GET $path'));
  }

  Future<SpiderHttpResponse> _send(SpiderHttpRequest request) async {
    final maxAttempts = retry?.maxAttempts ?? 1;
    var attempt = 1;
    while (true) {
      try {
        final resp = await httpClient.send(request).timeout(timeout);
        if (attempt < maxAttempts &&
            (resp.statusCode == 429 || resp.statusCode >= 500)) {
          await _retryDelay(attempt, resp);
          attempt++;
          continue;
        }
        return resp;
      } catch (_) {
        if (attempt < maxAttempts) {
          await _retryDelay(attempt, null);
          attempt++;
          continue;
        }
        rethrow;
      }
    }
  }

  Future<void> _retryDelay(int attempt, SpiderHttpResponse? resp) async {
    final exp = (1000 * pow(2, attempt - 1)).toDouble();
    var baseMs = exp < 10000 ? exp : 10000.0;
    final retryAfter = resp?.headers['retry-after'];
    if (retryAfter != null) {
      final seconds = double.tryParse(retryAfter);
      if (seconds != null && seconds >= 0) baseMs = seconds * 1000;
    }
    final jitter = baseMs * 0.25 * Random().nextDouble();
    await Future<void>.delayed(
        Duration(milliseconds: (baseMs + jitter).round()));
  }
}

Map<String, dynamic> _decodeJson(String body, String where) {
  try {
    return jsonDecode(body) as Map<String, dynamic>;
  } catch (e) {
    throw SpiderDecodingError('failed to decode $where', e);
  }
}

ErrorEnvelope _parseErrorEnvelope(String text) {
  try {
    final obj = jsonDecode(text);
    if (obj is Map<String, dynamic>) {
      final code = obj['code'];
      final message = obj['message'];
      return ErrorEnvelope(
          code is String ? code : null, message is String ? message : null);
    }
  } catch (_) {
    // fall through
  }
  return const ErrorEnvelope(null, null);
}

String _trunc(String s) => s.length > 300 ? s.substring(0, 300) : s;

String _stripTrailingSlashes(String s) {
  var r = s;
  while (r.endsWith('/')) {
    r = r.substring(0, r.length - 1);
  }
  return r;
}
