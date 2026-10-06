import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'contract/contract_version.dart';
import 'errors.dart';
import 'identity.dart';

/// The HTTP boundary the SDK depends on. Production uses [DefaultSpiderHttpClient]; tests inject their own.
abstract class SpiderHttpClient {
  Future<SpiderHttpResponse> send(SpiderHttpRequest request);

  /// Opens a response without buffering its body, for Server-Sent Events (the routing `plan-stream` route).
  /// The body is delivered as it arrives so the caller can parse SSE records incrementally.
  Future<SpiderHttpStreamedResponse> sendStreaming(SpiderHttpRequest request);
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

/// A response whose body is still streaming — the SSE counterpart of [SpiderHttpResponse].
class SpiderHttpStreamedResponse {
  final int statusCode;
  final Map<String, String> headers; // lower-cased keys
  final Stream<List<int>> body;
  const SpiderHttpStreamedResponse(this.statusCode, this.headers, this.body);
}

/// One finished Server-Sent Events record: its `event` name (defaulting to `message`) and accumulated `data`.
class SpiderSseEvent {
  final String event;
  final String data;
  const SpiderSseEvent(this.event, this.data);
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

  @override
  Future<SpiderHttpStreamedResponse> sendStreaming(
      SpiderHttpRequest request) async {
    final req = http.Request(request.method, request.uri);
    req.headers.addAll(request.headers);
    if (request.body != null) req.body = request.body!;
    final streamed = await _client.send(req);
    return SpiderHttpStreamedResponse(
        streamed.statusCode, streamed.headers, streamed.stream);
  }
}

class RetryConfig {
  final int maxAttempts;
  const RetryConfig(this.maxAttempts);
}

/// HTTP against the gateway: identity headers, JSON bodies and the retry/backoff loop.
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

  /// The contract-gated identity headers a real API call carries. The invariant `apikey` is not here — it is
  /// stamped centrally in [_send], so every request (including `/ping`) gets it without re-attaching per call.
  Map<String, String> _contractHeaders({bool json = false}) => {
        contractHeader: contractVersion,
        sdkHeader: sdkIdentity,
        if (json) 'content-type': 'application/json',
      };

  Future<D> postJson<D>(String path, Map<String, dynamic> body,
      D Function(Map<String, dynamic>) fromJson) async {
    final resp = await _send(SpiderHttpRequest(
        'POST',
        Uri.parse('$baseUrl$path'),
        _contractHeaders(json: true),
        jsonEncode(body)));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw httpFailure('POST $path', resp.statusCode, resp.body);
    }
    return fromJson(_decodeJson(resp.body, 'POST $path'));
  }

  Future<SpiderHttpResponse> getRaw(String path,
      {Map<String, String> query = const {}}) {
    final uri = Uri.parse('$baseUrl$path')
        .replace(queryParameters: query.isEmpty ? null : query);
    return _send(SpiderHttpRequest('GET', uri, _contractHeaders(), null));
  }

  Future<D> getJson<D>(String path, D Function(Map<String, dynamic>) fromJson,
      {Map<String, String> query = const {}}) async {
    final resp = await getRaw(path, query: query);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw httpFailure('GET $path', resp.statusCode, resp.body);
    }
    return fromJson(_decodeJson(resp.body, 'GET $path'));
  }

  /// Connection warm-up: one `GET {baseUrl}/ping` through the shared [_send] path, so it opens (or reuses) the
  /// TLS connection real calls travel over. Carries only the client `apikey` — stamped centrally by [_send], which
  /// the keyed `/ping` route authenticates — and no contract/identity headers, since `/ping` is gateway
  /// infrastructure, not a contract operation. The response (any status) is ignored; the round trip is the point.
  /// Bounded by [timeout]; the warmup transport is retry-free, so this runs no retry.
  Future<void> ping() async {
    await _send(
        SpiderHttpRequest('GET', Uri.parse('$baseUrl/ping'), const {}, null));
  }

  /// One un-retried SSE `POST {baseUrl}{path}`; it bypasses [_send], so it stamps the apikey itself.
  Stream<SpiderSseEvent> sse(String path, Map<String, dynamic> body) async* {
    final headers = {
      ..._contractHeaders(json: true),
      'accept': 'text/event-stream',
      'apikey': apiKey,
    };
    final response = await httpClient.sendStreaming(SpiderHttpRequest(
        'POST', Uri.parse('$baseUrl$path'), headers, jsonEncode(body)));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var text = '';
      try {
        text = await utf8.decodeStream(response.body);
      } catch (_) {
        // The error body is best-effort detail; its absence doesn't change the status mapping.
      }
      throw httpFailure('POST $path', response.statusCode, text);
    }
    yield* _parseSse(response.body);
  }

  Stream<SpiderSseEvent> _parseSse(Stream<List<int>> bytes) async* {
    var event = _defaultSseEvent;
    final dataLines = <String>[];
    await for (final line
        in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.isEmpty) {
        if (dataLines.isNotEmpty || event != _defaultSseEvent) {
          yield SpiderSseEvent(event, dataLines.join('\n'));
        }
        event = _defaultSseEvent;
        dataLines.clear();
        continue;
      }
      if (line.startsWith(':')) continue; // comment / heartbeat
      final colon = line.indexOf(':');
      final field = colon < 0 ? line : line.substring(0, colon);
      var value = colon < 0 ? '' : line.substring(colon + 1);
      if (value.startsWith(' ')) value = value.substring(1);
      switch (field) {
        case 'event':
          event = value;
        case 'data':
          dataLines.add(value);
        default:
          break; // id / retry and unknown fields are not surfaced
      }
    }
    if (dataLines.isNotEmpty || event != _defaultSseEvent) {
      yield SpiderSseEvent(event, dataLines.join('\n'));
    }
  }

  Future<SpiderHttpResponse> _send(SpiderHttpRequest request) async {
    // The client apikey is invariant for the client's whole life, so it is applied here — the single path every
    // request funnels through — rather than re-attached per call.
    final stamped = SpiderHttpRequest(request.method, request.uri,
        {...request.headers, 'apikey': apiKey}, request.body);
    final maxAttempts = retry?.maxAttempts ?? 1;
    var attempt = 1;
    while (true) {
      try {
        final resp = await httpClient.send(stamped).timeout(timeout);
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

const _defaultSseEvent = 'message';

const _queryRetired = 'query_retired';

// Plan-limit refusal codes with their fallback messages; only the body code identifies them, never the status.
const _planLimits = {
  'planning_limit_reached': (
    TransportErrorKind.planningLimitReached,
    'trip planning limit reached'
  ),
  'agreement_inactive': (
    TransportErrorKind.agreementInactive,
    'agreement is not active'
  ),
};

/// A plan-limit or `query_retired` body code (`code`, else gateway `error`) wins over the status.
TransportError httpFailure(String where, int status, String body) {
  final env = _parseErrorEnvelope(body);
  final bodyCode = env.code ?? env.error;
  final planLimit = _planLimits[bodyCode];
  if (planLimit != null) {
    final (kind, defaultMessage) = planLimit;
    final message = env.message?.trim() ?? '';
    return TransportError(kind, message.isEmpty ? defaultMessage : message,
        httpStatus: status, serverCode: bodyCode);
  }
  if (bodyCode == _queryRetired || status == 410) {
    return TransportError(TransportErrorKind.queryRetired,
        '$where -> $status: ${env.message ?? 'this operation is retired'}',
        httpStatus: status, serverCode: _queryRetired);
  }
  return TransportError(TransportErrorKind.http,
      '$where -> $status: ${env.message ?? _trunc(body)}',
      httpStatus: status,
      serverCode: env.code,
      field: status == 400
          ? env.field ?? _fieldNamedBy(env.message ?? body)
          : null);
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
      String? string(String key) {
        final value = obj[key];
        return value is String ? value : null;
      }

      return ErrorEnvelope(
          code: string('code'),
          message: string('message'),
          field: string('field'),
          error: string('error'));
    }
  } catch (_) {
    // fall through
  }
  return const ErrorEnvelope();
}

final _fieldMessage = RegExp(
    r'^([A-Za-z_][A-Za-z0-9_.]*) is (?:out of range|required|invalid|not allowed)$');

String? _fieldNamedBy(String message) =>
    _fieldMessage.firstMatch(message.trim())?.group(1);

String _trunc(String s) => s.length > 300 ? s.substring(0, 300) : s;

String _stripTrailingSlashes(String s) {
  var r = s;
  while (r.endsWith('/')) {
    r = r.substring(0, r.length - 1);
  }
  return r;
}
