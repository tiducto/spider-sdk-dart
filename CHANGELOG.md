# Changelog

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
