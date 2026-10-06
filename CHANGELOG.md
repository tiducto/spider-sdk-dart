# Changelog

## 2.0.0 - 2026-10-06

Targets Spider API contract `2.0`.

**Hard cut.** Contract `2.0` moves routing from persisted GraphQL queries to REST and retires the persisted
queries: once the API serves `2.0`, `plan`, `planStream`, `departures` and `trip` from a 1.x SDK fail with
`SpiderErrorCode.queryRetired` (HTTP 410). Stops and realtime calls keep working on 1.x.

### Changed

- **`plan`, `planStream`, `departures` and `trip` call the REST operations** `POST /routing/plan`,
  `/routing/plan-stream`, `/routing/departures` and `/routing/trip` with the contract's JSON bodies. The public
  routing API (`PlanOptions`, `Route`, `Departure`, `TripDetails`, `PlanStreamEvent`) keeps its shape.
- **`SpiderErrorCode.queryRetired` means the API part a call uses is retired (HTTP 410)**, on every surface: a
  410, or a body whose `code` (or gateway `error`) is `query_retired`, whatever the status. The message is the
  body's.
- **`SpiderError.field` on a 400 is the body's `field`**, else the dot path the message names
  (`<path> is required`, `is invalid`, `is out of range` or `is not allowed`), e.g.
  `preferences.transit.transfer.maximumTransfers`. A member the API does not take is `<path> is not allowed`.
- **A plan-limit refusal is read from the body's `code`, else its `error`.**
- **A via visit waits at most 1 h** (`minimumWaitSeconds` 0–3600, was 0–86400), as the API takes. Outside that
  the plan fails as `badRequest` with field `via.visit.minimumWaitTime`, without a request.
- **A coordinate via visit fails before sending.** `ViaLocation.visit(Location.coordinate(...))` is
  `badRequest` with message `via is invalid` and field `via`, the answer the API already gave; a visit takes a
  stop.
- **`planStream` ignores event names it doesn't know**, so the API can add events. A stream that ends without
  its paging info ends with a `PlanStreamFailure` (`server`), or `network` when the connection drops first.
  Nothing follows the terminal `PlanStreamDone` or `PlanStreamFailure`. A non-2xx answer before the stream
  maps like the one-shot calls.

### Deprecated

- **`RouteEdge.cursor`** is always `"NoCursor"`; page with `Route.pageInfo` through `planNext` /
  `planPrevious`.
- **`Itinerary.accessibilityScore` and `Leg.accessibilityScore`** are always null.

### Removed

- The persisted-query transport and its `persisted_query_rejected` code: a 403 that isn't a plan-limit
  refusal is `unauthorized`, like any other.

## 1.1.0 - 2026-10-05

Targets Spider API contract `1.1`.

### Added

- **`PlanOptions.reliability`** for `plan` and `planStream`: each arrival is planned with the trip's typical
  delay at the stop from the environment's realtime history, the median at `Reliability.standard`, the 70th
  percentile at `safe` and the 90th at `verySafe`. Boarding keeps the scheduled departure, and a trip with live
  realtime uses its realtime times. Left null, the plan follows the timetable and no `reliability` is sent.
- **`Leg.typicalArrivalDelay`**: the delay planned into the leg's arrival; null without `reliability` or when
  the trip has no delay history.
- **`Departure.typicalDelay` and `TripStop.typicalDelay`**: the median delay at the stop for that trip on the
  service date's day type; null when there is no history.
- **`Leg.interlineWithPreviousLeg`**: the rider stays on the same vehicle from the previous leg as it carries on
  as another trip, often under another line. That change isn't counted in `numberOfTransfers`.

### Changed

- `plan`, `planStream`, `departures` and `trip` send the contract `1.1` persisted queries. The `1.0` queries
  stay served until 2027-07-01, so earlier SDK versions keep working until then.

## 1.0.0 - 2026-10-01

Targets Spider API contract `1.0`. The first stable release: from here on, breaking changes need a new major.

### Changed

- **`planStream` / `planStreamNext` / `planStreamPrevious` require `targetResults:` and `maxWindowMinutes:`.**
  There is no SDK default; `maxWindowMinutes` must be at least 120.
- **`WheelchairBoarding` and `BikesAllowed` gain `unknown`**, so every decoded enum (`TransitMode`,
  `OccupancyStatus`, `RealtimeState`, `RoutingErrorCode`, `InputField`, `WheelchairBoarding`, `BikesAllowed`)
  maps a value this SDK version doesn't know to `unknown` instead of `null`. `NO_INFORMATION` /
  `NO_DATA_AVAILABLE` stay `null`. An exhaustive `switch` on either enum needs the `unknown` case.
- **HTTP 400 is `SpiderErrorCode.badRequest`** on every surface (it was `unknown`), with `SpiderError.field`
  set when the server's message names the input.
- **Invalid input is rejected before any request**, as `badRequest` naming only the field (e.g.
  `maxWindow is out of range`) with `field` set: a stream window under 120 minutes, a departures
  `timeRangeSeconds` outside (0, 86400], more than 50 realtime trip ids across all service dates, a malformed
  `serviceDate` on `trip` or `delays` / `delaysByServiceDate`, a stop-search `limit` outside 1–50, a via
  pass-through without 1–10 stop ids, or a visit wait outside 0–86400 s. Nothing is clamped.
- **Departures always send 30 departures over 24 h** unless told otherwise (`timeRangeSeconds` is a non-null
  `int`), and **stop search always sends `limit`** (20 unless told otherwise; `StopFilter.limit` and the
  `limit` of `near` / `within` are non-null `int`s).
- A plan stream the gateway rejects before routing (e.g. a missing variable) fails as `badRequest` naming the
  field, like the batch call.
- An unknown persisted-query id (403 `persisted_query_rejected`) stays `unauthorized` and keeps the gateway's
  message.

### Added

- **`SpiderErrorCode.queryRetired`** for a persisted query the API no longer serves (HTTP 410). It used to
  arrive as `unauthorized`. An exhaustive `switch` on `SpiderErrorCode` needs the new case.
- **`SpiderErrorCode.planningLimitReached`** when the project has reached its plan's trip planning limit. Trip
  planning (`plan`, `planStream`) is refused and the other calls still work.
- **`SpiderErrorCode.agreementInactive`** when the project has no active agreement. Every call made with the
  key is refused.
  Both come from the response body's code whatever the HTTP status, on every surface (including a plan stream
  refused before it starts), with `httpStatus` and `serverCode` set. A `vehicleForTrip` 404 that carries one
  is that error, not "no vehicle". The message is the body's; when the body has none, it is
  `trip planning limit reached` or `agreement is not active`. A 403 without one of these codes stays
  `unauthorized`. An exhaustive `switch` on `SpiderErrorCode` needs both cases.
- **Display fields.** `Leg`: `routeGtfsId`, `routeColor`, `routeTextColor`, `fromPlatformCode`,
  `toPlatformCode`, `fromZoneId`, `toZoneId`. `Departure`: `routeGtfsId`, `routeColor`, `routeTextColor`,
  `stopGtfsId`, `platformCode`, `wheelchairAccessible`. `TripDetails`: `routeGtfsId`, `routeColor`,
  `routeTextColor`, `wheelchairAccessible`. `TripStop`: `platformCode`, `zoneId`. Colours are the feed's GTFS
  hex without `#`.
- **`Departure.serviceDate` and `TripDetails.serviceDate`** (ISO `YYYY-MM-DD`), to scope a realtime delay
  lookup or a `trip(serviceDate:)` call.
- **`PlanStreamDone.routingErrors`**, like `Route.routingErrors`. A `locationNotFound` names
  `InputField.from`, `to` or `via`.
- **Stops:** `Stop.code`, `Stop.locationType`, `Stop.wheelchairBoarding`, `Stop.modes`, and
  `StopFilter.modes` (stops served by at least one of the modes). Search text also matches a stop's code, town
  and district.

### Removed

- `SpiderContractMismatchError`: a gateway declaring another contract major is no longer an error, so every
  call reports its failures through `SpiderResult`.
- The departures filter that dropped rows whose headsign equals the stop name.

## 0.7.1 - 2026-09-25

Targets Spider API contract `0.7`.

### Changed

- **`SpiderRouting.planStream(...)` streams the initial window only** and emits a three-variant
  `Stream<PlanStreamEvent>`: `PlanStreamResult(itineraries)` for each batch of finalized itineraries, a
  terminal `PlanStreamDone(pageInfo)` carrying the continuation `RoutePageInfo`
  (`endCursor`/`startCursor`/`hasNextPage`/`hasPreviousPage`), or a terminal `PlanStreamFailure(error)`.
- **Continue a stream with `planStreamNext(options, after:)` / `planStreamPrevious(options, before:)`** — each
  repeats `planStream`'s parameters plus a raw cursor `String` read off `PlanStreamDone.pageInfo`. `planStream`
  no longer takes `after`/`before`.

### Removed

- **`planUntil` / `planNextUntil` / `planPreviousUntil`** — the client-side window-walkers. Drive continuation
  from `PlanStreamDone.pageInfo` (stream) or `planNext` / `planPrevious` (batch) instead.
- **`PlanStreamChunk` and `PlanStreamPage`**, folded into `PlanStreamResult` and `PlanStreamDone`; the internal
  sweep telemetry (`frontierSeconds`/`found`/`finalized`, `iterations`/`windowSeconds`/`resultCount`/
  `stoppedBy`) is no longer surfaced.

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
