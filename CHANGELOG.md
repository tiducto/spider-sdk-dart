# Changelog

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
