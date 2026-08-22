# spider_sdk (Dart / Flutter)

The Dart SDK for **Spider** — the managed transit API by Tiducto. Trip planning, stop search, and live realtime data behind one typed client that ships the exact queries the gateway allows and attaches auth for you.

Native Dart package (single dependency: `package:http`), usable from Flutter (iOS/Android/web/desktop) and plain Dart. Sibling of the Kotlin, TypeScript, and Swift SDKs — same domain model, Dart idioms (`Future`, `Stream`, sealed classes).

## Install

```yaml
dependencies:
  spider_sdk: ^0.1.0
```

## Quickstart

```dart
import 'package:spider_sdk/spider_sdk.dart';

final client = SpiderClient('https://your-env-slug.api.tiducto.eu', apiKey);

final result = await client.routing.plan(const PlanOptions(
  origin: Location.coordinate(49.19, 16.61),
  destination: Location.coordinate(49.23, 16.53),
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

Ordinary failures are values — every call returns a `SpiderResult<T>` (`Success` / `Failure`) you branch on. The one thrown error is `SpiderContractMismatchError`, raised when the gateway speaks a different **major** contract version than this SDK.

## What's in it

- **`client.routing`** — trip planning (with paging and a streaming `planUntil`), departures, and single-trip lookups.
- **`client.stops`** — text search, geo queries (nearest / bounding box), and lookup by GTFS id.
- **`client.realtime`** — poll-based live vehicle positions, delays, and alerts, plus change-detecting `poll…` streams (no push connections).

**Full API reference and guides → [docs.tiducto.eu](https://docs.tiducto.eu).** Product overview → [tiducto.eu](https://tiducto.eu).

## Contract & codegen

The wire models under `lib/src/contract/` and the persisted-query ids are generated from the published contract by `scripts/generate-contract.sh` (via `tiducto/spider-codegen`) and committed — the package carries the types, not the spec. `client.contractVersion` reports the contract version this SDK speaks. Don't hand-edit generated files; re-run the script.

## License

Apache-2.0 — see [LICENSE](LICENSE).
