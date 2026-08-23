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
  // The recommended shape: a departure time plus a search window, not "N results from now".
  final result = await client.routing.plan(PlanOptions(
    origin: Location.coordinate(49.1951, 16.6068),
    destination: Location.coordinate(49.2246, 16.5747),
    departAt: DateTime.now(),
    searchWindowMinutes: 60,
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
    searchWindowMinutes: 30,
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

/// Page backward: fetch the itineraries before the first page.
Future<void> earlierItineraries(SpiderClient client) async {
  // [START earlierItineraries]
  final result = await client.routing.plan(PlanOptions(
    origin: Location.coordinate(49.1951, 16.6068),
    destination: Location.coordinate(49.2246, 16.5747),
    first: 3,
  ));

  switch (result) {
    case Success(:final value):
      // planPrevious returns null when there is no previous page.
      final previousPage = await client.routing.planPrevious(value);
      switch (previousPage) {
        case null:
          print('No earlier itineraries — that was the first page');
        case Success(value: final earlier):
          for (final edge in earlier.edges) {
            print('${edge.itinerary.start} → ${edge.itinerary.end}');
          }
        case Failure(:final error):
          print('plan failed: ${error.code.name} — ${error.message}');
      }
    case Failure(:final error):
      print('plan failed: ${error.code.name} — ${error.message}');
  }
  // [END earlierItineraries]
}

/// Restrict a plan to a set of transit modes (here: tram + subway).
Future<void> planWithModes(SpiderClient client) async {
  // [START planWithModes]
  final result = await client.routing.plan(PlanOptions(
    origin: Location.coordinate(49.1951, 16.6068),
    destination: Location.coordinate(49.2246, 16.5747),
    allowedTransitModes: const [TransitMode.tram, TransitMode.subway],
    first: 3,
  ));

  if (result case Success(:final value)) {
    for (final edge in value.edges) {
      final modes =
          edge.itinerary.legs.map((l) => l.mode?.name ?? 'walk').join(' → ');
      print('${edge.itinerary.durationSeconds ~/ 60} min: $modes');
    }
  }
  // [END planWithModes]
}

/// Plan to arrive by a given time instead of departing at one.
Future<void> arriveBy(SpiderClient client) async {
  // [START arriveBy]
  final result = await client.routing.plan(PlanOptions(
    origin: Location.coordinate(49.1951, 16.6068),
    destination: Location.coordinate(49.2246, 16.5747),
    arriveBy: DateTime(2026, 8, 21, 9, 0),
    searchWindowMinutes: 60,
  ));

  if (result case Success(:final value)) {
    for (final edge in value.edges) {
      final trip = edge.itinerary;
      print('depart ${trip.start} → arrive ${trip.end}');
    }
  }
  // [END arriveBy]
}

/// Plan a trip that passes through a via point, dwelling there for a few minutes.
Future<void> planVia(SpiderClient client) async {
  // [START planVia]
  final result = await client.routing.plan(PlanOptions(
    origin: Location.coordinate(49.1951, 16.6068),
    destination: Location.coordinate(49.2246, 16.5747),
    via: [
      ViaLocation.visit(
        Location.coordinate(49.2103, 16.5993),
        minimumWaitSeconds: 300,
      ),
    ],
    first: 3,
  ));

  if (result case Success(:final value)) {
    print('found ${value.edges.length} itineraries via the waypoint');
  }
  // [END planVia]
}

/// Plan a wheelchair-accessible trip and read the accessibility info.
Future<void> wheelchairPlan(SpiderClient client) async {
  // [START wheelchairPlan]
  final result = await client.routing.plan(PlanOptions(
    origin: Location.coordinate(49.1951, 16.6068),
    destination: Location.coordinate(49.2246, 16.5747),
    wheelchairAccessible: true,
    first: 3,
  ));

  if (result case Success(:final value)) {
    for (final edge in value.edges) {
      final trip = edge.itinerary;
      print('${trip.start} → ${trip.end} '
          'accessibility: ${trip.accessibilityScore ?? 'n/a'}');
      for (final leg in trip.legs) {
        final boarding = leg.fromWheelchair?.name ?? 'unknown';
        print('  boarding at ${leg.fromName}: $boarding');
      }
    }
  }
  // [END wheelchairPlan]
}

/// Tune a plan with the optional request options: leave at a set time, cap the
/// number of transfers, widen the search window, restrict the modes, and ask for
/// more itineraries per page.
Future<void> planWithOptions(SpiderClient client) async {
  // [START planWithOptions]
  final result = await client.routing.plan(PlanOptions(
    origin: Location.coordinate(49.1951, 16.6068),
    destination: Location.coordinate(49.2246, 16.5747),
    departAt: DateTime(2026, 8, 21, 8, 30),
    maxTransfers: 1,
    searchWindowMinutes: 120,
    allowedTransitModes: const [TransitMode.tram, TransitMode.bus],
    first: 5,
  ));

  if (result case Success(:final value)) {
    for (final edge in value.edges) {
      final trip = edge.itinerary;
      print('${trip.durationSeconds ~/ 60} min, '
          '${trip.numberOfTransfers} transfers');
    }
    print('search window used: ${value.pageInfo.searchWindowUsed}');
  }
  // [END planWithOptions]
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

/// Read the full departure record, including realtime delay info. Each
/// `Departure` carries scheduled and (when live) realtime epoch-ms times, an
/// `isRealtime` flag, a `realtimeState`, the route names, headsign, trip id, and mode.
Future<void> departuresWithRealtime(SpiderClient client) async {
  // [START departuresWithRealtime]
  final result =
      await client.routing.departures('U123Z1', numberOfDepartures: 5);

  if (result case Success(:final value)) {
    for (final d in value) {
      final line = d.routeShortName ?? d.routeLongName ?? d.mode?.name ?? '?';
      final scheduled =
          DateTime.fromMillisecondsSinceEpoch(d.scheduledTimeEpochMs);

      if (d.isRealtime && d.realtimeTimeEpochMs != null) {
        final live =
            DateTime.fromMillisecondsSinceEpoch(d.realtimeTimeEpochMs!);
        final delayMin =
            (d.realtimeTimeEpochMs! - d.scheduledTimeEpochMs) ~/ 60000;
        print('$line → ${d.headsign}: scheduled $scheduled, '
            'live $live (${delayMin}m, ${d.realtimeState?.name}) '
            '[trip ${d.tripGtfsId}]');
      } else {
        print('$line → ${d.headsign}: $scheduled (scheduled)');
      }
    }
  }
  // [END departuresWithRealtime]
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
