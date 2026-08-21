# spider_sdk (Dart / Flutter)

The Dart SDK for the **Spider** transit API — trip planning, stop search, and live realtime data behind one
typed client. It ships the exact query documents the gateway allows and attaches auth for you, so you get a
typed, closed surface out of the box.

A native Dart package (single dependency: `package:http`), usable from Flutter (iOS/Android/web/desktop) and
plain Dart. It is a sibling of the Kotlin, TypeScript, and Swift SDKs and mirrors their domain model and
semantics, adapted to Dart idioms (`Future`, `Stream`, sealed classes).

## Install

```yaml
dependencies:
  spider_sdk: ^5.0.0
```

## Quickstart

Construct a client with your environment's base URL and API key, then call a surface. Every call returns a
`SpiderResult<T>` you branch on before reading the value.

```dart
import 'package:spider_sdk/spider_sdk.dart';

final client = SpiderClient('https://your-env-slug.api.tiducto.eu', apiKey);

final result = await client.routing.plan(const PlanOptions(
  origin: Location.coordinate(49.1908, 16.6128),
  destination: Location.coordinate(49.2270, 16.5273),
  first: 3,
));

switch (result) {
  case Success(:final value):
    for (final edge in value.edges) {
      final legs = edge.itinerary.legs.map((l) => l.mode?.name ?? 'walk').join(' → ');
      print('${edge.itinerary.durationSeconds ~/ 60} min: $legs');
    }
  case Failure(:final error):
    print('plan failed: ${error.code.name} — ${error.message}');
}
```

### Trip planning

```dart
final result = await client.routing.plan(PlanOptions(
  origin: const Location.stop('U123Z1'),
  destination: const Location.coordinate(49.19, 16.61),
  departAt: DateTime.now(),
  allowedTransitModes: const [TransitMode.tram, TransitMode.bus, TransitMode.subway],
  maxTransfers: 2,
  searchWindowMinutes: 90,
  wheelchairAccessible: true,
));

// Page forward / backward.
if (result case Success(:final value)) {
  final next = await client.routing.planNext(value); // null if no next page
}

// Or stream itineraries, stepping the search window until you have enough.
await for (final page in client.routing.planUntil(
  const PlanOptions(origin: Location.stop('A'), destination: Location.stop('B')),
  targetResults: 20,
)) {
  if (page case Success(:final value)) { /* collect value.edges */ }
}
```

### Departures & a single trip

```dart
final departures = await client.routing.departures('U123Z1', numberOfDepartures: 10);
final trip = await client.routing.trip('T-4821', serviceDate: '2026-08-21');
```

### Stop search

```dart
final stops = await client.stops.search(const StopFilter(name: 'Náměstí', city: 'Brno'));
```

### Realtime (poll-based)

```dart
// One-shot.
final positions = await client.realtime.vehicles(['T-1', 'T-2']);
final alerts = await client.realtime.alerts();

// Or a change-detecting stream (yields only when the data changes; cancel the subscription to stop).
final sub = client.realtime.pollVehicles(['T-1', 'T-2'], intervalMs: 10000).listen((update) {
  if (update case Success(:final value)) { /* update the map */ }
});
// later: await sub.cancel();
```

## Errors

Ordinary failures are values, not thrown: every call returns `SpiderResult<T>` (`Success` / `Failure`), and
`Failure` carries a `SpiderError` with a stable `code` (`network`, `timeout`, `unauthorized`, `notFound`,
`server`, `rateLimited`, `decoding`, `unknown`). The **one** thrown error is `SpiderContractMismatchError` —
raised when the gateway speaks a different **major** contract version than this SDK.

## Options

```dart
final client = SpiderClient(base, key, SpiderClientOptions(
  timeout: const Duration(seconds: 20),                            // default 30s
  routing: const FeatureOptions(autoRetry: AutoRetryOptions(maxAttempts: 3)), // opt-in retries, per surface
));
```

Retries (opt-in per surface) back off on `429`/`5xx` and network/timeout errors, honoring a numeric
`Retry-After`. Inject a custom `SpiderHttpClient` via `SpiderClientOptions(httpClient:)` for tests or proxies.

## Contract & codegen

The wire models under `lib/src/contract/` and the persisted-query ids are **generated** from the published
contract by `scripts/generate-contract.sh` (via `tiducto/spider-codegen`) and committed — the package carries
the types, not the spec. `client.contractVersion` reports the contract version this SDK speaks (`5.0`). Do not
hand-edit generated files; re-run the script.
