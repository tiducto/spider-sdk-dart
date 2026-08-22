import 'contract/contract_version.dart' as c;
import 'realtime.dart';
import 'routing.dart';
import 'stops.dart';
import 'transport.dart';

/// Per-surface retry configuration. Retries are opt-in: leave null to disable (the default).
class AutoRetryOptions {
  /// Total attempts including the first (default 3 when auto-retry is enabled).
  final int? maxAttempts;
  const AutoRetryOptions({this.maxAttempts});
}

/// Feature toggles for one surface (routing / stops / realtime).
class FeatureOptions {
  final AutoRetryOptions? autoRetry;
  const FeatureOptions({this.autoRetry});
}

/// Client-wide options: a shared HTTP client + timeout, and per-surface feature toggles.
class SpiderClientOptions {
  /// Inject a custom HTTP client (tests, proxies). Defaults to [DefaultSpiderHttpClient].
  final SpiderHttpClient? httpClient;

  /// Per-request timeout (default 30s).
  final Duration? timeout;

  final FeatureOptions? routing;
  final FeatureOptions? stops;
  final FeatureOptions? realtime;

  const SpiderClientOptions(
      {this.httpClient, this.timeout, this.routing, this.stops, this.realtime});
}

/// The Spider API client. Construct once with your environment base URL and API key, then reach a surface:
/// [routing], [stops], [realtime]. Each surface gets its own transport (own retry config) sharing
/// the same base URL, key, HTTP client and timeout.
class SpiderClient {
  final SpiderRouting routing;
  final SpiderStops stops;
  final SpiderRealtime realtime;

  factory SpiderClient(String baseUrl, String apiKey,
      [SpiderClientOptions options = const SpiderClientOptions()]) {
    final httpClient = options.httpClient ?? DefaultSpiderHttpClient();
    final timeout = options.timeout ?? const Duration(seconds: 30);

    Transport transportFor(FeatureOptions? feature) {
      final autoRetry = feature?.autoRetry;
      final retry =
          autoRetry != null ? RetryConfig(autoRetry.maxAttempts ?? 3) : null;
      return Transport(
          baseUrl: baseUrl,
          apiKey: apiKey,
          httpClient: httpClient,
          timeout: timeout,
          retry: retry);
    }

    return SpiderClient._(
      SpiderRouting(transportFor(options.routing)),
      SpiderStops(transportFor(options.stops)),
      SpiderRealtime(transportFor(options.realtime)),
    );
  }

  SpiderClient._(this.routing, this.stops, this.realtime);

  /// The contract (major.minor) version this SDK speaks.
  String get contractVersion => c.contractVersion;
}
