import 'dart:convert';

import 'contract/persisted_queries.dart';
import 'contract/routing.dart' as wire;
import 'enums.dart';
import 'errors.dart';
import 'location.dart';
import 'plan_stream_event.dart';
import 'polyline.dart';
import 'result.dart';
import 'transport.dart';

// MARK: public routing models

/// One leg of an itinerary (a single vehicle ride or walk). The realtime fields carry live schedule
/// deviation when the feed reports it: [startEstimated]/[endEstimated] are the estimated boarding/alighting
/// times, [startDelay]/[endDelay] the deviation from schedule, and [serviceDate] the GTFS service date
/// (`YYYYMMDD`) that scopes a realtime delay lookup for this trip instance.
class Leg {
  final TransitMode? mode;
  final String startScheduled;
  final String endScheduled;
  final String? startEstimated;
  final String? endEstimated;
  final Duration? startDelay;
  final Duration? endDelay;
  final bool isRealtime;
  final RealtimeState? realtimeState;
  final String? serviceDate;
  final String? fromName;
  final String? toName;
  final String? fromGtfsId;
  final String? toGtfsId;
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
    this.startEstimated,
    this.endEstimated,
    this.startDelay,
    this.endDelay,
    this.isRealtime = false,
    this.realtimeState,
    this.serviceDate,
    this.fromName,
    this.toName,
    this.fromGtfsId,
    this.toGtfsId,
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

const _defaultSearchWindowMinutes = 60;
const _defaultMaxTraversalMinutes = 360;
const _defaultTargetResults = 10;
const _defaultStreamTargetResults = 5;
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

  /// Plans a trip. Returns the first window of itineraries.
  Future<SpiderResult<Route>> plan(PlanOptions options) {
    return _page(_makeRequest(options));
  }

  /// The next window after [route], or null if there is none. Pages forward with `after` (no page-size count).
  Future<SpiderResult<Route>?> planNext(Route route) async {
    if (!route.pageInfo.hasNextPage) return null;
    return _page(route._request, after: route.pageInfo.endCursor);
  }

  /// The previous window before [route], or null if there is none. Pages backward with `before` (no page-size count).
  Future<SpiderResult<Route>?> planPrevious(Route route) async {
    if (!route.pageInfo.hasPreviousPage) return null;
    return _page(route._request, before: route.pageInfo.startCursor);
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

  /// Streams itineraries over Server-Sent Events as the router sweeps the search window forward, emitting them
  /// as they finalize instead of one batched page. Cold and cancellable: listening starts the request,
  /// cancelling the subscription stops the sweep. Each [PlanStreamChunk] carries itineraries with realtime
  /// delays already applied to their legs; a [PlanStreamPage] then carries the continuation cursors and a
  /// [PlanStreamDone] closes the stream (or a terminal [PlanStreamFailure]).
  ///
  /// [targetResults] is a soft floor the sweep aims to reach; [maxWindowMinutes] caps how far forward it
  /// searches. To continue, re-call with the same [options] plus [after] = the last [RoutePageInfo.endCursor]
  /// (or [before] = [RoutePageInfo.startCursor] to walk earlier). For a single batched page instead, use
  /// [plan]. [PlanOptions.searchWindowMinutes] is ignored here — the stream paces itself with
  /// [targetResults]/[maxWindowMinutes].
  Stream<PlanStreamEvent> planStream(
    PlanOptions options, {
    int targetResults = _defaultStreamTargetResults,
    int maxWindowMinutes = _defaultMaxTraversalMinutes,
    String? after,
    String? before,
  }) async* {
    final request = _makeRequest(options);
    final iso = request.time.toUtc().toIso8601String();
    final dateTime = request.timeKind == _TimeKind.departAt
        ? wire.PlanDateTimeInput(earliestDeparture: iso)
        : wire.PlanDateTimeInput(latestArrival: iso);
    final variables = wire.PlanConnectionStreamVariables(
      dateTime: dateTime,
      origin: _locationToInput(request.origin),
      destination: _locationToInput(request.destination),
      via: request.via.isEmpty ? null : request.via.map(_viaToInput).toList(),
      modes: _modesInput(request.allowedTransitModes),
      preferences: _preferencesInput(request),
      targetResults: targetResults,
      maxWindow: 'PT${maxWindowMinutes < 1 ? 1 : maxWindowMinutes}M',
      before: before,
      after: after,
    ).toJson();
    try {
      await for (final frame
          in _transport.sse(PersistedQueries.planstream, variables)) {
        final event = parsePlanStreamRecord(frame.event, frame.data);
        if (event != null) yield event;
      }
    } catch (e) {
      yield PlanStreamFailure(toSpiderError(e));
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
      {String? before, String? after}) async {
    try {
      return Success(await _fetchPlan(request, before: before, after: after));
    } on SpiderContractMismatchError {
      rethrow;
    } catch (e) {
      return Failure(toSpiderError(e));
    }
  }

  Future<Route> _fetchPlan(_PlanRequest request,
      {String? before, String? after}) async {
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
          ? await planNext(prev)
          : await planPrevious(prev);
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
  // The router indexes legs with leg 0 = the initial access (walk, or nothing), so its wire
  // `maximumTransfers` counts boardings = transfers + 1 (wire 0 = walk-only, not exposed here).
  // `maxTransfers` is a transfer count, so map it to boardings: 0 transfers = 1 boarding (direct).
  final transit = maxTransfers != null
      ? wire.TransitPreferencesInput(
          transfer:
              wire.TransferPreferencesInput(maximumTransfers: maxTransfers + 1))
      : null;
  final accessibility = request.wheelchairAccessible
      ? wire.AccessibilityPreferencesInput(
          wheelchair: wire.WheelchairPreferencesInput(enabled: true))
      : null;
  if (transit == null && accessibility == null) return null;
  return wire.PlanPreferencesInput(
      accessibility: accessibility, transit: transit);
}

// MARK: plan-stream record parsing

/// Parses one finished SSE record (its `event` name + accumulated `data`) into a [PlanStreamEvent]; returns
/// null for records the SDK doesn't surface (heartbeats, blank data, unknown events). A malformed payload
/// becomes a terminal [PlanStreamFailure] rather than throwing. Public so the wire-contract test exercises it
/// directly, matching the batch plan's wire→domain mapping.
PlanStreamEvent? parsePlanStreamRecord(String event, String data) {
  if (data.trim().isEmpty) return null;
  switch (event) {
    case 'chunk':
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        final itineraries = (json['results'] as List<dynamic>? ?? const [])
            .map((e) => _mapItinerary(
                wire.Itinerary.fromJson(e as Map<String, dynamic>)))
            .toList();
        return PlanStreamChunk(
          frontierSeconds: (json['frontier'] as num?)?.toInt() ?? 0,
          found: (json['found'] as num?)?.toInt() ?? 0,
          finalized: (json['finalized'] as num?)?.toInt() ?? 0,
          itineraries: itineraries,
        );
      } catch (e) {
        return PlanStreamFailure(_streamDecodingError('chunk', e));
      }
    case 'pageInfo':
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        return PlanStreamPage(RoutePageInfo(
          startCursor: json['startCursor'] as String?,
          endCursor: json['endCursor'] as String?,
          hasNextPage: json['hasNextPage'] as bool? ?? false,
          hasPreviousPage: json['hasPreviousPage'] as bool? ?? false,
          searchWindowUsed: json['searchWindowUsed'] as String?,
        ));
      } catch (e) {
        return PlanStreamFailure(_streamDecodingError('pageInfo', e));
      }
    case 'done':
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        return PlanStreamDone(
          iterations: (json['iterations'] as num?)?.toInt() ?? 0,
          windowSeconds: (json['windowSeconds'] as num?)?.toInt() ?? 0,
          resultCount: (json['resultCount'] as num?)?.toInt() ?? 0,
          stoppedBy: json['stoppedBy'] as String? ?? 'unknown',
        );
      } catch (e) {
        return PlanStreamFailure(_streamDecodingError('done', e));
      }
    case 'error':
      return PlanStreamFailure(_streamErrorToSpiderError(data));
    default:
      return null;
  }
}

SpiderError _streamDecodingError(String event, Object cause) => SpiderError(
    SpiderErrorCode.decoding, 'failed to parse plan-stream $event record',
    cause: cause);

// A stream `error` record is the same GraphQL error envelope the batch path returns, so it maps through the
// same taxonomy: a top-level BAD_REQUEST becomes a typed badRequest (with its field), anything else server.
SpiderError _streamErrorToSpiderError(String data) {
  try {
    final json = jsonDecode(data) as Map<String, dynamic>;
    final errors = json['errors'];
    if (errors is List && errors.isNotEmpty) {
      for (final e in errors) {
        final ext = e is Map ? e['extensions'] : null;
        if (ext is Map && ext['code'] == 'BAD_REQUEST') {
          return toSpiderError(TransportError(TransportErrorKind.badRequest,
              (e as Map)['message']?.toString() ?? 'bad request',
              field: ext['field'] as String?));
        }
      }
      final joined = errors.map((e) => (e as Map)['message']).join(', ');
      return toSpiderError(TransportError(
          TransportErrorKind.upstream, 'plan-stream errors: $joined'));
    }
    final message = json['message'];
    return toSpiderError(TransportError(TransportErrorKind.upstream,
        'plan-stream error: ${message is String ? message : _truncData(data)}'));
  } catch (_) {
    return toSpiderError(TransportError(
        TransportErrorKind.upstream, 'plan-stream error: ${_truncData(data)}'));
  }
}

String _truncData(String s) => s.length > 300 ? s.substring(0, 300) : s;

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
    startEstimated: w.start.estimated?.time,
    endEstimated: w.end.estimated?.time,
    startDelay: _durationFromWire(w.start.estimated?.delay),
    endDelay: _durationFromWire(w.end.estimated?.delay),
    isRealtime: w.realTime ?? false,
    realtimeState: RealtimeState.fromWire(w.realtimeState?.wire),
    serviceDate: w.serviceDate,
    fromName: w.from.name,
    toName: w.to.name,
    fromGtfsId: w.from.stop?.gtfsId,
    toGtfsId: w.to.stop?.gtfsId,
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

// Parses an ISO-8601 duration ("PT60S", "PT1M30S", optionally signed) or a bare seconds count into a
// [Duration]. Mirrors the Kotlin SDK's durationFromWire: ISO first, then a numeric-seconds fallback; an
// unparseable or absent value is null.
Duration? _durationFromWire(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final iso = _parseIsoDuration(raw);
  if (iso != null) return iso;
  final seconds = num.tryParse(raw);
  return seconds == null
      ? null
      : Duration(
          microseconds: (seconds * Duration.microsecondsPerSecond).round());
}

final _isoDurationPattern = RegExp(
    r'^(-)?P(?:T(?:(\d+(?:\.\d+)?)H)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)S)?)?$');

Duration? _parseIsoDuration(String raw) {
  final match = _isoDurationPattern.firstMatch(raw);
  if (match == null ||
      (match[2] == null && match[3] == null && match[4] == null)) {
    return null;
  }
  final sign = match[1] == '-' ? -1 : 1;
  final hours = double.tryParse(match[2] ?? '0') ?? 0;
  final minutes = double.tryParse(match[3] ?? '0') ?? 0;
  final seconds = double.tryParse(match[4] ?? '0') ?? 0;
  final micros =
      ((hours * 3600 + minutes * 60 + seconds) * Duration.microsecondsPerSecond)
          .round();
  return Duration(microseconds: sign * micros);
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
