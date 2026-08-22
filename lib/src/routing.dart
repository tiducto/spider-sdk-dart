import 'contract/persisted_queries.dart';
import 'contract/routing.dart' as wire;
import 'enums.dart';
import 'errors.dart';
import 'location.dart';
import 'polyline.dart';
import 'result.dart';
import 'transport.dart';

// MARK: public routing models

/// One leg of an itinerary (a single vehicle ride or walk).
class Leg {
  final TransitMode? mode;
  final String startScheduled;
  final String endScheduled;
  final String? fromName;
  final String? toName;
  final String? routeShortName;
  final String? routeLongName;
  final String? headsign;
  final double? distanceMeters;
  final double? durationSeconds;
  final String? tripGtfsId;
  final BikesAllowed? bikesAllowed;
  final double? accessibilityScore;
  final WheelchairBoarding? fromWheelchair;
  final WheelchairBoarding? toWheelchair;
  final List<LatLon> geometry;
  const Leg({
    this.mode,
    required this.startScheduled,
    required this.endScheduled,
    this.fromName,
    this.toName,
    this.routeShortName,
    this.routeLongName,
    this.headsign,
    this.distanceMeters,
    this.durationSeconds,
    this.tripGtfsId,
    this.bikesAllowed,
    this.accessibilityScore,
    this.fromWheelchair,
    this.toWheelchair,
    this.geometry = const [],
  });
}

/// A full origin-to-destination itinerary.
class Itinerary {
  final String? start;
  final String? end;
  final int durationSeconds;
  final int? waitingTimeSeconds;
  final int numberOfTransfers;
  final double? accessibilityScore;
  final List<Leg> legs;
  const Itinerary({
    this.start,
    this.end,
    required this.durationSeconds,
    this.waitingTimeSeconds,
    required this.numberOfTransfers,
    this.accessibilityScore,
    required this.legs,
  });
}

/// A paged itinerary with its cursor.
class RouteEdge {
  final String cursor;
  final Itinerary itinerary;
  const RouteEdge(this.cursor, this.itinerary);
}

/// Relay-style paging info for a [Route].
class RoutePageInfo {
  final String? startCursor;
  final String? endCursor;
  final bool hasNextPage;
  final bool hasPreviousPage;
  final String? searchWindowUsed;
  const RoutePageInfo({
    this.startCursor,
    this.endCursor,
    required this.hasNextPage,
    required this.hasPreviousPage,
    this.searchWindowUsed,
  });
}

/// A non-fatal routing problem (e.g. no transit connection in the window).
class RoutingError {
  final RoutingErrorCode code;
  final String description;
  final InputField? inputField;
  const RoutingError(this.code, this.description, this.inputField);
}

/// The result of a trip-plan search: a page of itineraries plus paging info and any routing errors.
class Route {
  final List<RouteEdge> edges;
  final RoutePageInfo pageInfo;
  final List<RoutingError> routingErrors;
  final String? searchDateTime;
  // Carries the originating request so planNext/planPrevious can page without re-deriving it. Library-private.
  final _PlanRequest _request;
  const Route._({
    required this.edges,
    required this.pageInfo,
    required this.routingErrors,
    this.searchDateTime,
    required _PlanRequest request,
  }) : _request = request;
}

/// A single departure from a stop.
class Departure {
  final int scheduledTimeEpochMs;
  final int? realtimeTimeEpochMs;
  final bool isRealtime;
  final RealtimeState? realtimeState;
  final String? headsign;
  final String? tripGtfsId;
  final String? routeShortName;
  final String? routeLongName;
  final TransitMode? mode;
  const Departure({
    required this.scheduledTimeEpochMs,
    this.realtimeTimeEpochMs,
    required this.isRealtime,
    this.realtimeState,
    this.headsign,
    this.tripGtfsId,
    this.routeShortName,
    this.routeLongName,
    this.mode,
  });
}

/// One stop on a trip's timetable.
class TripStop {
  final String gtfsId;
  final String name;
  final double? lat;
  final double? lon;
  final int? scheduledArrivalEpochMs;
  final int? scheduledDepartureEpochMs;
  final int? realtimeArrivalEpochMs;
  final int? realtimeDepartureEpochMs;
  final bool isRealtime;
  final WheelchairBoarding? wheelchairBoarding;
  const TripStop({
    required this.gtfsId,
    required this.name,
    this.lat,
    this.lon,
    this.scheduledArrivalEpochMs,
    this.scheduledDepartureEpochMs,
    this.realtimeArrivalEpochMs,
    this.realtimeDepartureEpochMs,
    required this.isRealtime,
    this.wheelchairBoarding,
  });
}

/// A single trip's route, stops, and geometry.
class TripDetails {
  final String gtfsId;
  final String? routeShortName;
  final String? routeLongName;
  final TransitMode? mode;
  final String? headsign;
  final String? directionId;
  final BikesAllowed? bikesAllowed;
  final List<TripStop> stops;
  final List<LatLon> geometry;
  const TripDetails({
    required this.gtfsId,
    this.routeShortName,
    this.routeLongName,
    this.mode,
    this.headsign,
    this.directionId,
    this.bikesAllowed,
    required this.stops,
    required this.geometry,
  });
}

/// Options for a trip-plan search. [departAt]/[arriveBy] are mutually exclusive (arriveBy wins if both set;
/// neither = depart now). [allowedTransitModes] empty = all modes. [searchWindowMinutes] defaults to 60.
class PlanOptions {
  final Location origin;
  final Location destination;
  final int? first;
  final DateTime? departAt;
  final DateTime? arriveBy;
  final List<ViaLocation> via;
  final List<TransitMode> allowedTransitModes;
  final int? maxTransfers;
  final int? searchWindowMinutes;
  final bool wheelchairAccessible;
  const PlanOptions({
    required this.origin,
    required this.destination,
    this.first,
    this.departAt,
    this.arriveBy,
    this.via = const [],
    this.allowedTransitModes = const [],
    this.maxTransfers,
    this.searchWindowMinutes,
    this.wheelchairAccessible = false,
  });
}

enum _TimeKind { departAt, arriveBy }

class _PlanRequest {
  final Location origin;
  final Location destination;
  final _TimeKind timeKind;
  final DateTime time;
  final List<ViaLocation> via;
  final List<TransitMode> allowedTransitModes;
  final int? maxTransfers;
  final int searchWindowMinutes;
  final bool wheelchairAccessible;
  const _PlanRequest({
    required this.origin,
    required this.destination,
    required this.timeKind,
    required this.time,
    required this.via,
    required this.allowedTransitModes,
    this.maxTransfers,
    required this.searchWindowMinutes,
    required this.wheelchairAccessible,
  });
}

enum _PageDirection { forward, backward }

const _defaultFirst = 5;
const _defaultSearchWindowMinutes = 60;
const _defaultMaxTraversalMinutes = 360;
const _defaultTargetResults = 10;
const _maxResultsPerStep = 50;
const _defaultTimeRangeSeconds = 24 * 60 * 60;
const _intMax = 2147483647;

// The transit modes valid in a modes filter — street/leg modes (WALK/BICYCLE/CAR/TRANSIT) must not reach it.
const _wireTransitModes = {
  'AIRPLANE',
  'BUS',
  'CABLE_CAR',
  'CARPOOL',
  'COACH',
  'FERRY',
  'FUNICULAR',
  'GONDOLA',
  'MONORAIL',
  'RAIL',
  'SNOW_AND_ICE',
  'SUBWAY',
  'TAXI',
  'TRAM',
  'TROLLEYBUS',
};

/// The routing surface: trip planning (plan + paging + streaming), stop departures, and single trip detail.
class SpiderRouting {
  final Transport _transport;
  SpiderRouting(this._transport);

  /// Plans a trip. Returns the first page of itineraries.
  Future<SpiderResult<Route>> plan(PlanOptions options) {
    return _page(_makeRequest(options), first: options.first ?? _defaultFirst);
  }

  /// The next page after [route], or null if there is none.
  Future<SpiderResult<Route>?> planNext(Route route,
      {int first = _defaultFirst}) async {
    if (!route.pageInfo.hasNextPage) return null;
    return _page(route._request, first: first, after: route.pageInfo.endCursor);
  }

  /// The previous page before [route], or null if there is none. Pages backward (last + before), Relay-correct.
  Future<SpiderResult<Route>?> planPrevious(Route route,
      {int last = _defaultFirst}) async {
    if (!route.pageInfo.hasPreviousPage) return null;
    return _page(route._request,
        last: last, before: route.pageInfo.startCursor);
  }

  /// Streams itineraries forward, one search window per step, until [targetResults] are collected or
  /// [maxTraversalMinutes] of time is traversed. Lazy: stop listening to skip the remaining searches.
  Stream<SpiderResult<Route>> planUntil(
    PlanOptions options, {
    int targetResults = _defaultTargetResults,
    int maxTraversalMinutes = _defaultMaxTraversalMinutes,
  }) async* {
    final windowMin =
        options.searchWindowMinutes ?? _defaultSearchWindowMinutes;
    final steps = _stepCount(maxTraversalMinutes, windowMin);
    final first = await plan(PlanOptions(
      origin: options.origin,
      destination: options.destination,
      first: _maxResultsPerStep,
      departAt: options.departAt,
      arriveBy: options.arriveBy,
      via: options.via,
      allowedTransitModes: options.allowedTransitModes,
      maxTransfers: options.maxTransfers,
      searchWindowMinutes: options.searchWindowMinutes,
      wheelchairAccessible: options.wheelchairAccessible,
    ));
    yield first;
    if (first is! Success<Route>) return;
    yield* _stepStream(first.value, _PageDirection.forward, steps - 1,
        targetResults, first.value.edges.length);
  }

  /// Streaming form of planNext: steps forward from [prev].
  Stream<SpiderResult<Route>> planNextUntil(Route prev,
      {int targetResults = _defaultTargetResults,
      int maxTraversalMinutes = _defaultMaxTraversalMinutes}) {
    final steps =
        _stepCount(maxTraversalMinutes, prev._request.searchWindowMinutes);
    return _stepStream(prev, _PageDirection.forward, steps, targetResults, 0);
  }

  /// Streaming form of planPrevious: steps backward from [prev].
  Stream<SpiderResult<Route>> planPreviousUntil(Route prev,
      {int targetResults = _defaultTargetResults,
      int maxTraversalMinutes = _defaultMaxTraversalMinutes}) {
    final steps =
        _stepCount(maxTraversalMinutes, prev._request.searchWindowMinutes);
    return _stepStream(prev, _PageDirection.backward, steps, targetResults, 0);
  }

  /// Departures from a stop, soonest first. [numberOfDepartures] caps the count; [startTime] defaults to now.
  Future<SpiderResult<List<Departure>>> departures(String stopId,
      {int numberOfDepartures = 30,
      DateTime? startTime,
      int? timeRangeSeconds}) async {
    try {
      final variables = wire.StopDeparturesVariables(
        id: stopId,
        numberOfDepartures: numberOfDepartures,
        startTime: startTime == null
            ? null
            : (startTime.millisecondsSinceEpoch / 1000).floor(),
        timeRange: _clampSeconds(timeRangeSeconds ?? _defaultTimeRangeSeconds),
      ).toJson();
      final data = await _transport.graphql(PersistedQueries.departures,
          variables, wire.StopDeparturesData.fromJson);
      final stop = data.asStop ?? data.asStation;
      if (stop == null) {
        throw TransportError(TransportErrorKind.noData,
            'routing returned no stop or station for id=$stopId');
      }
      return Success(_mapDepartures(stop));
    } on SpiderContractMismatchError {
      rethrow;
    } catch (e) {
      return Failure(toSpiderError(e));
    }
  }

  /// A single trip's stops, times, and geometry.
  Future<SpiderResult<TripDetails>> trip(String tripId,
      {String? serviceDate}) async {
    try {
      final variables =
          wire.TripVariables(id: tripId, serviceDate: serviceDate).toJson();
      final data = await _transport.graphql(
          PersistedQueries.trip, variables, wire.TripData.fromJson);
      final trip = data.trip;
      if (trip == null) {
        throw TransportError(TransportErrorKind.noData,
            'routing returned no trip for id=$tripId');
      }
      return Success(_mapTrip(trip));
    } on SpiderContractMismatchError {
      rethrow;
    } catch (e) {
      return Failure(toSpiderError(e));
    }
  }

  _PlanRequest _makeRequest(PlanOptions options) {
    final kind =
        options.arriveBy != null ? _TimeKind.arriveBy : _TimeKind.departAt;
    final time = options.arriveBy ?? options.departAt ?? DateTime.now();
    return _PlanRequest(
      origin: options.origin,
      destination: options.destination,
      timeKind: kind,
      time: time,
      via: options.via,
      allowedTransitModes: options.allowedTransitModes,
      maxTransfers: options.maxTransfers,
      searchWindowMinutes:
          options.searchWindowMinutes ?? _defaultSearchWindowMinutes,
      wheelchairAccessible: options.wheelchairAccessible,
    );
  }

  Future<SpiderResult<Route>> _page(_PlanRequest request,
      {int? first, int? last, String? before, String? after}) async {
    try {
      return Success(await _fetchPlan(request,
          first: first, last: last, before: before, after: after));
    } on SpiderContractMismatchError {
      rethrow;
    } catch (e) {
      return Failure(toSpiderError(e));
    }
  }

  Future<Route> _fetchPlan(_PlanRequest request,
      {int? first, int? last, String? before, String? after}) async {
    final iso = request.time.toUtc().toIso8601String();
    final dateTime = request.timeKind == _TimeKind.departAt
        ? wire.PlanDateTimeInput(earliestDeparture: iso)
        : wire.PlanDateTimeInput(latestArrival: iso);
    final variables = wire.PlanConnectionVariables(
      dateTime: dateTime,
      origin: _locationToInput(request.origin),
      destination: _locationToInput(request.destination),
      via: request.via.isEmpty ? null : request.via.map(_viaToInput).toList(),
      modes: _modesInput(request.allowedTransitModes),
      preferences: _preferencesInput(request),
      searchWindow:
          'PT${request.searchWindowMinutes < 1 ? 1 : request.searchWindowMinutes}M',
      first: first,
      last: last,
      before: before,
      after: after,
    ).toJson();
    final data = await _transport.graphql(
        PersistedQueries.plan, variables, wire.PlanConnectionData.fromJson);
    final plan = data.planConnection;
    if (plan == null) {
      throw TransportError(
          TransportErrorKind.noData, 'routing returned no plan data');
    }
    final edges = (plan.edges ?? [])
        .map((e) => RouteEdge(e.cursor, _mapItinerary(e.node)))
        .toList();
    final pageInfo = RoutePageInfo(
      startCursor: plan.pageInfo.startCursor,
      endCursor: plan.pageInfo.endCursor,
      hasNextPage: plan.pageInfo.hasNextPage,
      hasPreviousPage: plan.pageInfo.hasPreviousPage,
      searchWindowUsed: plan.pageInfo.searchWindowUsed,
    );
    final routingErrors = plan.routingErrors
        .map((re) => RoutingError(RoutingErrorCode.fromWire(re.code.wire),
            re.description, InputField.fromWire(re.inputField?.wire)))
        .toList();
    return Route._(
        edges: edges,
        pageInfo: pageInfo,
        routingErrors: routingErrors,
        searchDateTime: plan.searchDateTime,
        request: request);
  }

  Stream<SpiderResult<Route>> _stepStream(Route start, _PageDirection direction,
      int remainingSteps, int targetResults, int collectedSoFar) async* {
    if (collectedSoFar >= targetResults) return;
    var prev = start;
    var collected = collectedSoFar;
    for (var i = 0; i < (remainingSteps < 0 ? 0 : remainingSteps); i++) {
      final result = direction == _PageDirection.forward
          ? await planNext(prev, first: _maxResultsPerStep)
          : await planPrevious(prev, last: _maxResultsPerStep);
      if (result == null) return;
      yield result;
      if (result is! Success<Route>) return;
      collected += result.value.edges.length;
      if (collected >= targetResults) return;
      prev = result.value;
    }
  }
}

// MARK: request builders

wire.PlanLabeledLocationInput _locationToInput(Location location) {
  return switch (location) {
    CoordinateLocation(:final latitude, :final longitude) =>
      wire.PlanLabeledLocationInput(
          location: wire.PlanLocationInput(
              coordinate: wire.PlanCoordinateInput(
                  latitude: latitude, longitude: longitude))),
    StopLocation(:final id) => wire.PlanLabeledLocationInput(
        location: wire.PlanLocationInput(
            stopLocation: wire.PlanStopLocationInput(stopLocationId: id))),
  };
}

wire.PlanViaLocationInput _viaToInput(ViaLocation via) {
  switch (via) {
    case PassThroughVia(:final stopIds):
      return wire.PlanViaLocationInput(
          passThrough:
              wire.PlanPassThroughViaLocationInput(stopLocationIds: stopIds));
    case VisitVia(:final location, :final minimumWaitSeconds):
      final wait = minimumWaitSeconds > 0 ? 'PT${minimumWaitSeconds}S' : null;
      return switch (location) {
        StopLocation(:final id) => wire.PlanViaLocationInput(
            visit: wire.PlanVisitViaLocationInput(
                minimumWaitTime: wait, stopLocationIds: [id])),
        CoordinateLocation(:final latitude, :final longitude) =>
          wire.PlanViaLocationInput(
              visit: wire.PlanVisitViaLocationInput(
                  coordinate: wire.PlanCoordinateInput(
                      latitude: latitude, longitude: longitude),
                  minimumWaitTime: wait)),
      };
  }
}

wire.PlanModesInput? _modesInput(List<TransitMode> modes) {
  final transit = modes
      .where((m) => _wireTransitModes.contains(m.wire))
      .map((m) => wire.PlanTransitModePreferenceInput(
          mode: wire.TransitMode.fromWire(m.wire)))
      .toList();
  if (transit.isEmpty) return null;
  return wire.PlanModesInput(
      transit: wire.PlanTransitModesInput(transit: transit));
}

wire.PlanPreferencesInput? _preferencesInput(_PlanRequest request) {
  final maxTransfers = request.maxTransfers;
  final transit = maxTransfers != null
      ? wire.TransitPreferencesInput(
          transfer:
              wire.TransferPreferencesInput(maximumTransfers: maxTransfers))
      : null;
  final accessibility = request.wheelchairAccessible
      ? wire.AccessibilityPreferencesInput(
          wheelchair: wire.WheelchairPreferencesInput(enabled: true))
      : null;
  if (transit == null && accessibility == null) return null;
  return wire.PlanPreferencesInput(
      accessibility: accessibility, transit: transit);
}

// MARK: response mappers

Itinerary _mapItinerary(wire.Itinerary w) => Itinerary(
      start: w.start,
      end: w.end,
      durationSeconds: w.duration ?? 0,
      waitingTimeSeconds: w.waitingTime,
      numberOfTransfers: w.numberOfTransfers,
      accessibilityScore: w.accessibilityScore,
      legs: w.legs.map(_mapLeg).toList(),
    );

Leg _mapLeg(wire.Leg w) {
  final points = w.legGeometry?.points;
  return Leg(
    mode: TransitMode.fromWire(w.mode?.wire),
    startScheduled: w.start.scheduledTime,
    endScheduled: w.end.scheduledTime,
    fromName: w.from.name,
    toName: w.to.name,
    routeShortName: w.route?.shortName,
    routeLongName: w.route?.longName,
    headsign: w.headsign,
    distanceMeters: w.distance,
    durationSeconds: w.duration,
    tripGtfsId: w.trip?.gtfsId,
    bikesAllowed: BikesAllowed.fromWire(w.trip?.bikesAllowed?.wire),
    accessibilityScore: w.accessibilityScore,
    fromWheelchair:
        WheelchairBoarding.fromWire(w.from.stop?.wheelchairBoarding?.wire),
    toWheelchair:
        WheelchairBoarding.fromWire(w.to.stop?.wheelchairBoarding?.wire),
    geometry: points != null ? decodePolyline(points) : const [],
  );
}

List<Departure> _mapDepartures(wire.StopDeparturesStop stop) {
  final stopName = stop.name.trim().toLowerCase();
  final out = <Departure>[];
  for (final st in stop.stoptimesWithoutPatterns ?? const <wire.Stoptime>[]) {
    final serviceDay = st.serviceDay;
    final scheduledOffset = st.scheduledDeparture;
    if (serviceDay == null || scheduledOffset == null) continue;
    final headsign = st.headsign;
    if (headsign != null && headsign.trim().toLowerCase() == stopName) continue;
    final route = st.trip?.route;
    final rt = st.realtimeDeparture;
    out.add(Departure(
      scheduledTimeEpochMs: (serviceDay + scheduledOffset) * 1000,
      realtimeTimeEpochMs: rt != null ? (serviceDay + rt) * 1000 : null,
      isRealtime: st.realtime ?? false,
      realtimeState: RealtimeState.fromWire(st.realtimeState?.wire),
      headsign: st.headsign,
      tripGtfsId: st.trip?.gtfsId,
      routeShortName: route?.shortName,
      routeLongName: route?.longName,
      mode: TransitMode.fromWire(route?.mode?.wire),
    ));
  }
  return out;
}

TripDetails _mapTrip(wire.TripTrip w) {
  final stops = <TripStop>[];
  for (final st in w.stoptimesForDate ?? const <wire.TripStoptime>[]) {
    final s = st.stop;
    if (s == null) continue;
    final day = st.serviceDay;
    int? at(int? offset) =>
        (offset != null && day != null) ? (day + offset) * 1000 : null;
    stops.add(TripStop(
      gtfsId: s.gtfsId,
      name: s.name,
      lat: s.lat,
      lon: s.lon,
      scheduledArrivalEpochMs: at(st.scheduledArrival),
      scheduledDepartureEpochMs: at(st.scheduledDeparture),
      realtimeArrivalEpochMs: at(st.realtimeArrival),
      realtimeDepartureEpochMs: at(st.realtimeDeparture),
      isRealtime: st.realtime ?? false,
      wheelchairBoarding:
          WheelchairBoarding.fromWire(s.wheelchairBoarding?.wire),
    ));
  }
  final points = w.tripGeometry?.points;
  return TripDetails(
    gtfsId: w.gtfsId,
    routeShortName: w.route.shortName,
    routeLongName: w.route.longName,
    mode: TransitMode.fromWire(w.route.mode?.wire),
    headsign: w.tripHeadsign,
    directionId: w.directionId,
    bikesAllowed: BikesAllowed.fromWire(w.bikesAllowed?.wire),
    stops: stops,
    geometry: points != null ? decodePolyline(points) : const [],
  );
}

int _clampSeconds(int seconds) =>
    seconds < 0 ? 0 : (seconds > _intMax ? _intMax : seconds);

int _stepCount(int maxTraversalMinutes, int stepMinutes) {
  final step = stepMinutes < 1 ? 1 : stepMinutes;
  final n = maxTraversalMinutes ~/ step;
  return n < 1 ? 1 : n;
}
