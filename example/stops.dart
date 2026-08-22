// Stop-search examples for the Spider Dart SDK. The docs site inlines the
// named regions below (between the START/END markers) as code samples.
import 'package:spider_sdk/spider_sdk.dart';

/// Search stops by free text.
Future<void> search(SpiderClient client) async {
  // [START search]
  final result =
      await client.stops.search(const StopFilter(name: 'Hlavní nádraží'));

  if (result case Success(:final value)) {
    for (final stop in value) {
      print('${stop.name} (${stop.gtfsId}) — ${stop.city}');
    }
  }
  // [END search]
}

/// Reuse a search hit as the input to another call.
Future<void> reuseHit(SpiderClient client) async {
  // [START reuseHit]
  final found = await client.stops.search(const StopFilter(name: 'Náměstí'));

  if (found case Success(:final value) when value.isNotEmpty) {
    final hit = value.first;
    if (hit.lat != null && hit.lon != null) {
      print('using ${hit.name} at ${hit.lat}, ${hit.lon}');
    }

    final departures =
        await client.routing.departures(hit.gtfsId, numberOfDepartures: 5);
    if (departures case Success(value: final departureList)) {
      print('${departureList.length} departures from ${hit.name}');
    }
  }
  // [END reuseHit]
}

/// Constrain a text search to a single administrative area — here a single
/// city. The admin fields on [StopFilter] narrow the free-text query.
Future<void> stopsByCity(SpiderClient client) async {
  // [START stopsByCity]
  final result = await client.stops.search(
    const StopFilter(name: 'nádraží', city: 'Example City'),
  );

  if (result case Success(:final value)) {
    for (final stop in value) {
      print('${stop.name} (${stop.gtfsId}) — ${stop.city}');
    }
  }
  // [END stopsByCity]
}

/// Find stops near a point (here a city-center point, ~49.19, 16.61), nearest first,
/// within a 500 m radius.
Future<void> stopsNearby(SpiderClient client) async {
  // [START stopsNearby]
  final result = await client.stops.near(49.19, 16.61, radiusMeters: 500);

  if (result case Success(:final value)) {
    for (final stop in value) {
      print('${stop.name} (${stop.gtfsId}) — ${stop.lat}, ${stop.lon}');
    }
  }
  // [END stopsNearby]
}

/// Look up a single stop by its GTFS id.
Future<void> stopById(SpiderClient client) async {
  // [START stopById]
  final result = await client.stops.byId('U123Z1');

  switch (result) {
    case Success(value: final stop?):
      print('found ${stop.name} at ${stop.lat}, ${stop.lon}');
    case Success():
      print('no stop with that id');
    case Failure(:final error):
      print('lookup failed: ${error.code.name} — ${error.message}');
  }
  // [END stopById]
}
