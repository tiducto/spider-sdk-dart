// Quickstart examples for the Spider Dart SDK. The docs site inlines the
// named regions below (between the START/END markers) as code samples.
import 'package:spider_sdk/spider_sdk.dart';

/// Construct a client and make your first call.
Future<SpiderResult<Route>> firstCall() async {
  // [START firstCall]
  final client =
      SpiderClient('https://your-env-slug.api.tiducto.eu', 'your-api-key');

  final result = await client.routing.plan(PlanOptions(
    origin: Location.coordinate(49.1908, 16.6128),
    destination: Location.coordinate(49.2270, 16.5273),
    first: 3,
  ));
  // [END firstCall]
  return result;
}

/// Every call returns a `SpiderResult` you branch on before reading the value.
Future<void> handleResult(SpiderClient client) async {
  // [START handleResult]
  final result = await client.routing.plan(PlanOptions(
    origin: Location.coordinate(49.1908, 16.6128),
    destination: Location.coordinate(49.2270, 16.5273),
    first: 3,
  ));

  switch (result) {
    case Success(:final value):
      for (final edge in value.edges) {
        final legs =
            edge.itinerary.legs.map((l) => l.mode?.name ?? 'walk').join(' → ');
        print('${edge.itinerary.durationSeconds ~/ 60} min: $legs');
      }
    case Failure(:final error):
      print('plan failed: ${error.code.name} — ${error.message}');
  }
  // [END handleResult]
}

/// React to a failure by branching on its typed `SpiderErrorCode`. The codes are
/// camelCase: network, timeout, unauthorized, notFound, server, rateLimited,
/// decoding, unknown. The switch is exhaustive — no `default` needed.
Future<void> handleErrors(SpiderClient client) async {
  // [START handleErrors]
  final result = await client.routing.plan(PlanOptions(
    origin: Location.coordinate(49.1908, 16.6128),
    destination: Location.coordinate(49.2270, 16.5273),
    first: 3,
  ));

  if (result case Failure(:final error)) {
    switch (error.code) {
      case SpiderErrorCode.unauthorized:
        print('Check the API key for this environment');
      case SpiderErrorCode.rateLimited:
        print('Rate limited — back off, then retry');
      case SpiderErrorCode.timeout:
        print('Request timed out — retry');
      case SpiderErrorCode.network:
        print('Network unreachable — check connectivity');
      case SpiderErrorCode.notFound:
        print('Nothing matched that request');
      case SpiderErrorCode.server:
        print('Gateway error (HTTP ${error.httpStatus}) — retry later');
      case SpiderErrorCode.decoding:
        print('Could not decode the response: ${error.message}');
      case SpiderErrorCode.unknown:
        print('Unexpected failure: ${error.message}');
    }
  }
  // [END handleErrors]
}

/// The same client reaches the stops and realtime surfaces too.
Future<void> otherSurfaces(SpiderClient client, String tripId) async {
  // [START otherSurfaces]
  final stops = await client.stops.search(const StopFilter(name: 'central'));
  if (stops case Success(:final value)) {
    print('found ${value.length} stops');
  }

  final vehicle = await client.realtime.vehicleForTrip(tripId);
  if (vehicle case Success(:final value)) {
    print('live vehicle: ${value.vehicle?.vehicleId}');
  }
  // [END otherSurfaces]
}
