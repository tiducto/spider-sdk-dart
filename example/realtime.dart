// Realtime examples for the Spider Dart SDK. The docs site inlines the named
// regions below (between the START/END markers) as code samples.
import 'dart:async';
import 'package:spider_sdk/spider_sdk.dart';

/// Construct a client to reach the realtime surface.
SpiderClient setup() {
  // [START setup]
  final client =
      SpiderClient('https://your-env-slug.api.tiducto.eu', 'your-api-key');
  // [END setup]
  return client;
}

/// Opt into automatic retries for the realtime surface.
SpiderClient setupWithRetry() {
  // [START setupWithRetry]
  final client = SpiderClient(
    'https://your-env-slug.api.tiducto.eu',
    'your-api-key',
    const SpiderClientOptions(
      realtime: FeatureOptions(autoRetry: AutoRetryOptions(maxAttempts: 3)),
    ),
  );
  // [END setupWithRetry]
  return client;
}

/// A hand-rolled poll loop: refresh delays roughly every 15 seconds.
Future<void> poll(SpiderClient client, List<String> tripIds) async {
  // [START poll]
  while (true) {
    final result = await client.realtime.delays(tripIds);
    switch (result) {
      case Success(:final value):
        _updateBoard(value);
      case Failure(:final error):
        _log(error);
    }
    await Future<void>.delayed(const Duration(seconds: 15));
  }
  // [END poll]
}

/// The SDK's built-in polling stream does the loop for you and only yields when
/// the data changes. Cancel the subscription to stop.
StreamSubscription<SpiderResult<VehiclePositions>> pollHelper(
    SpiderClient client, List<String> tripIds) {
  // [START pollHelper]
  final sub =
      client.realtime.pollVehicles(tripIds, intervalMs: 10000).listen((update) {
    switch (update) {
      case Success(:final value):
        for (final vehicle in value.vehicles) {
          _placeMarker(vehicle);
        }
      case Failure(:final error):
        _log(error);
    }
  });
  // [END pollHelper]
  return sub;
}

/// One-shot live positions for a set of trips.
Future<void> vehicles(SpiderClient client, List<String> tripIds) async {
  // [START vehicles]
  final result = await client.realtime.vehicles(tripIds);

  if (result case Success(:final value)) {
    for (final vehicle in value.vehicles) {
      print('${vehicle.tripId} at ${vehicle.latitude}, ${vehicle.longitude}');
    }
  }
  // [END vehicles]
}

/// The live vehicle for a single trip — `null` when none is reporting.
Future<void> vehicleForTrip(SpiderClient client, String tripId) async {
  // [START vehicleForTrip]
  final result = await client.realtime.vehicleForTrip(tripId);

  switch (result) {
    case Success(:final value):
      final vehicle = value.vehicle;
      if (vehicle == null) {
        print('trip $tripId has no live vehicle right now');
      } else {
        print('trip $tripId at ${vehicle.latitude}, ${vehicle.longitude}');
      }
    case Failure(:final error):
      print('lookup failed: ${error.message}');
  }
  // [END vehicleForTrip]
}

/// Live schedule deviation for a set of trips.
Future<void> delays(SpiderClient client, List<String> tripIds) async {
  // [START delays]
  final result = await client.realtime.delays(tripIds);

  if (result case Success(:final value)) {
    for (final delay in value.delays) {
      final minutes = (delay.delaySeconds ?? 0) ~/ 60;
      print('${delay.tripId}: ${minutes >= 0 ? '+' : ''}$minutes min');
    }
  }
  // [END delays]
}

/// All active service alerts for the environment.
Future<void> alerts(SpiderClient client) async {
  // [START alerts]
  final result = await client.realtime.alerts();

  if (result case Success(:final value)) {
    for (final alert in value.alerts) {
      print('${alert.headerText}: ${alert.descriptionText}');
    }
  }
  // [END alerts]
}

// Stand-in app hooks so the examples above read cleanly.
void _updateBoard(TripDelays delays) =>
    print('board: ${delays.delays.length} trips');

void _placeMarker(LiveVehicle vehicle) => print('marker for ${vehicle.tripId}');

void _log(SpiderError error) => print('realtime error: ${error.message}');
