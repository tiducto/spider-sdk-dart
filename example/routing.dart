// Routing examples for the Spider Dart SDK. The docs site inlines the named
// regions below (between the START/END markers) as code samples.
import 'package:spider_sdk/spider_sdk.dart';

/// Construct a client to reach the routing surface.
SpiderClient setup() {
  // [START setup]
  final client =
      SpiderClient('https://your-env-slug.api.tiducto.eu', 'your-api-key');
  // [END setup]
  return client;
}

/// Plan a trip and walk its itineraries leg by leg.
Future<void> planTrip(SpiderClient client) async {
  // [START planTrip]
  final result = await client.routing.plan(PlanOptions(
    origin: Location.coordinate(49.1951, 16.6068),
    destination: Location.coordinate(49.2246, 16.5747),
    first: 3,
  ));

  switch (result) {
    case Success(:final value):
      for (final edge in value.edges) {
        final trip = edge.itinerary;
        print('${trip.start} → ${trip.end} '
            '(${trip.numberOfTransfers} transfers)');
        for (final leg in trip.legs) {
          final mode = leg.mode?.name ?? 'walk';
          final route = leg.routeShortName ?? 'walk';
          print('  $mode $route: ${leg.fromName} → ${leg.toName} '
              '(${leg.durationSeconds}s)');
        }
      }
    case Failure(:final error):
      print('plan failed: ${error.code.name} — ${error.message}');
  }
  // [END planTrip]
}

/// Plan for a specific departure time instead of "now".
Future<void> planForTime(SpiderClient client) async {
  // [START planForTime]
  final result = await client.routing.plan(PlanOptions(
    origin: Location.coordinate(49.1951, 16.6068),
    destination: Location.coordinate(49.2246, 16.5747),
    departAt: DateTime(2026, 8, 21, 8, 30),
    first: 3,
  ));

  if (result case Success(:final value)) {
    print('found ${value.edges.length} itineraries');
  }
  // [END planForTime]
}

/// Page forward: fetch the itineraries after the first page.
Future<void> laterItineraries(SpiderClient client) async {
  // [START laterItineraries]
  final result = await client.routing.plan(PlanOptions(
    origin: Location.coordinate(49.1951, 16.6068),
    destination: Location.coordinate(49.2246, 16.5747),
    first: 3,
  ));

  switch (result) {
    case Success(:final value):
      // planNext returns null when there is no next page.
      final nextPage = await client.routing.planNext(value);
      switch (nextPage) {
        case null:
          print('No later itineraries — that was the last page');
        case Success(value: final later):
          for (final edge in later.edges) {
            print('${edge.itinerary.start} → ${edge.itinerary.end}');
          }
        case Failure(:final error):
          print('plan failed: ${error.code.name} — ${error.message}');
      }
    case Failure(:final error):
      print('plan failed: ${error.code.name} — ${error.message}');
  }
  // [END laterItineraries]
}

/// List the next departures from a stop.
Future<void> departures(SpiderClient client) async {
  // [START departures]
  final result =
      await client.routing.departures('U123Z1', numberOfDepartures: 5);

  if (result case Success(:final value)) {
    for (final departure in value) {
      final at =
          DateTime.fromMillisecondsSinceEpoch(departure.scheduledTimeEpochMs);
      print('${departure.routeShortName} → ${departure.headsign} at $at');
    }
  }
  // [END departures]
}

/// Look up a single trip's timetable.
Future<void> tripLookup(SpiderClient client) async {
  // [START tripLookup]
  final result = await client.routing.trip('1:12345');

  if (result case Success(:final value)) {
    for (final stop in value.stops) {
      print('${stop.name}: '
          'arr ${stop.scheduledArrivalEpochMs} '
          'dep ${stop.scheduledDepartureEpochMs}');
    }
  }
  // [END tripLookup]
}
