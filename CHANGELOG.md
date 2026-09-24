# Changelog

## 0.7.0 - 2026-09-24

Targets Spider API contract `0.7`. Brings the Dart SDK to parity with the reference SDK.

### Added

- **`SpiderRouting.planStream(...)`** — streams itineraries over Server-Sent Events as the router sweeps the
  search window forward, emitting a `Stream<PlanStreamEvent>` (`PlanStreamChunk` / `PlanStreamPage` /
  `PlanStreamDone`, or a terminal `PlanStreamFailure`) instead of one batched page. Cold and cancellable;
  `targetResults`/`maxWindowMinutes` pace the sweep, `after`/`before` continue from a prior page's cursors.
- **`SpiderClient.warmup()`** — pre-warms the connection to the environment's API host with one `GET /ping`
  (authenticated with the client apikey), so the first trip-planning call rides an already-open TLS
  connection. Best-effort and never throws; returns the measured round-trip `Duration`.
- **`Leg` realtime fields** — `startEstimated`/`endEstimated`, `startDelay`/`endDelay`, `isRealtime`,
  `realtimeState`, and `serviceDate` (the GTFS service date to scope a delay lookup by), plus `fromGtfsId`/
  `toGtfsId`. Surfaced by both `plan` and `planStream`.

### Changed

- **Realtime delays are now grouped by service date.** `realtime.delays(tripIds, serviceDate)` and
  `realtime.delaysByServiceDate({serviceDate: tripIds})` POST a grouped query so the same trip id on two
  service dates resolves to two distinct instances; look one up with `TripDelays.delayFor(tripId,
  serviceDate)`. `TripDelays.groups` replaces the flat `delays`/`missing`. `pollDelays` mirrors the change.
  The flat `delays(tripIds)` is removed.

### Fixed

- `maxTransfers` now maps to the router's boarding count (`maximumTransfers = transfers + 1`). The router
  indexes legs with leg 0 as the initial access (walk, or nothing), so passing the caller's transfer count
  verbatim made `maxTransfers` 0 and 1 behave identically. Now `0` means direct, `1` allows one transfer.

## 0.1.1 - 2026-08-26

**Breaking:** `searchWindow` is now required on plan requests (the gateway enforces the
updated contract, and older persisted-query ids are rejected with 403).

- Persisted queries updated to the current published contract.
- Server-side validation failures now surface as `SpiderErrorCode.badRequest`.

## 0.1.0 - 2026-08-22

Initial public pre-release; targets Spider API contract `0.1`.

This is a pre-1.0 release: the API surface may change without a major-version
bump until 1.0.0. Pin an exact version if you need stability.

Covered surfaces:

- **Trip planning** (`planConnection`) — itineraries with paging.
- **Stop departures** — upcoming departures for a stop.
- **Single-trip lookup** — a trip's stops and times.
- **Stop search** — free-text/autocomplete and geographic (nearest, radius,
  bounding box) queries, plus lookup by GTFS id.
- **Realtime** (poll-based) — vehicle positions, delays, and service alerts.
