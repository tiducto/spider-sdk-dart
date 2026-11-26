import 'dart:convert';

import 'contract/routing.dart' as wire;
import 'enums.dart';
import 'errors.dart';
import 'location.dart';
import 'plan_stream_event.dart';
import 'polyline.dart';
import 'result.dart';
import 'service_date.dart';
import 'transport.dart';
import 'trip_vehicle.dart';

// MARK: public routing models

/// One leg of an itinerary (a single vehicle ride or walk). The realtime fields carry live schedule
/// deviation when the feed reports it: [startEstimated]/[endEstimated] are the estimated boarding/alighting
/// times, [startDelay]/[endDelay] the deviation from schedule, and [serviceDate] the GTFS service date
/// (`YYYY-MM-DD`) that scopes a realtime delay lookup for this trip instance. The route, platform and zone
/// fields are the feed's values for display, passed through as the feed gives them; null when it has none.
class Leg {
  final TransitMode? mode;
  final String startScheduled;
  final String endScheduled;
  final String? startEstimated;
  final String? endEstimated;
  final Duration? startDelay;
  final Duration? endDelay;

  /// The typical delay planned into this leg's arrival at the requested [PlanOptions.reliability]; null when no
  /// reliability was requested or the trip has no delay history.
  final Duration? typicalArrivalDelay;
  final bool isRealtime;

  /// The realtime state of the leg's trip; [RealtimeState.scheduled] on a walk leg.
  final RealtimeState? realtimeState;
  final String? serviceDate;
  final String fromName;
  final String toName;
  final String? fromGtfsId;
  final String? toGtfsId;

  /// The boarding stop's position in the leg's trip: the [TripStop] of [SpiderRouting.trip] for [tripGtfsId]
  /// and [serviceDate] with the same [TripStop.stopPosition] is that stop. Null on a walk.
  final int? fromStopPosition;

  /// The alighting stop's position in the leg's trip, as [fromStopPosition]. Null on a walk.
  final int? toStopPosition;

  /// The platform or track code (GTFS `platform_code`) at the boarding stop.
  final String? fromPlatformCode;

  /// The platform or track code (GTFS `platform_code`) at the alighting stop.
  final String? toPlatformCode;

  /// The fare zone (GTFS `zone_id`) of the boarding stop.
  final String? fromZoneId;

  /// The fare zone (GTFS `zone_id`) of the alighting stop.
  final String? toZoneId;
  final String? routeGtfsId;
  final String? routeShortName;
  final String? routeLongName;

  /// The route colour: the raw GTFS hex without `#` (e.g. `"FF0000"`).
  final String? routeColor;

  /// The colour for text drawn on [routeColor]: the raw GTFS hex without `#` (e.g. `"FFFFFF"`).
  final String? routeTextColor;
  final String? headsign;
  final double distanceMeters;
  final int durationSeconds;
  final String? tripGtfsId;

  /// Whether the rider stays on the same vehicle from the previous leg (it continues as another trip, often
  /// under another line); such a change isn't counted in [Itinerary.numberOfTransfers].
  final bool interlineWithPreviousLeg;

  /// How the rider boards the trip at the leg's start, e.g. [PickupDropoffType.coordinateWithDriver] at a stop
  /// on request. [PickupDropoffType.scheduled] on a walk leg and on a leg with [interlineWithPreviousLeg],
  /// where the rider is already on board.
  final PickupDropoffType pickupType;

  /// How the rider alights from the trip at the leg's end. [PickupDropoffType.scheduled] on a walk leg and on
  /// a leg the next leg continues with [interlineWithPreviousLeg], where the rider stays on board.
  final PickupDropoffType dropoffType;
  final BikesAllowed? bikesAllowed;
  @Deprecated('Always null: the API sends no accessibility score.')
  final double? accessibilityScore;
  final WheelchairBoarding? fromWheelchair;
  final WheelchairBoarding? toWheelchair;
  final List<LatLon> geometry;

  /// The vehicle running the leg's trip run, as the realtime trip update names it; null on a walk leg and
  /// until a vehicle is matched to the run.
  final TripVehicle? vehicle;
  const Leg({
    this.mode,
    required this.startScheduled,
    required this.endScheduled,
    this.startEstimated,
    this.endEstimated,
    this.startDelay,
    this.endDelay,
    this.typicalArrivalDelay,
    this.isRealtime = false,
    this.realtimeState,
    this.serviceDate,
    required this.fromName,
    required this.toName,
    this.fromGtfsId,
    this.toGtfsId,
    this.fromStopPosition,
    this.toStopPosition,
    this.fromPlatformCode,
    this.toPlatformCode,
    this.fromZoneId,
    this.toZoneId,
    this.routeGtfsId,
    this.routeShortName,
    this.routeLongName,
    this.routeColor,
    this.routeTextColor,
    this.headsign,
    required this.distanceMeters,
    required this.durationSeconds,
    this.tripGtfsId,
    this.interlineWithPreviousLeg = false,
    this.pickupType = PickupDropoffType.scheduled,
    this.dropoffType = PickupDropoffType.scheduled,
    this.bikesAllowed,
    this.accessibilityScore,
    this.fromWheelchair,
    this.toWheelchair,
    this.geometry = const [],
    this.vehicle,
  });
}

/// A full origin-to-destination itinerary.
class Itinerary {
  final String start;
  final String end;
  final int durationSeconds;
  final int waitingTimeSeconds;
  final int numberOfTransfers;
  @Deprecated('Always null: the API sends no accessibility score.')
  final double? accessibilityScore;
  final List<Leg> legs;
  const Itinerary({
    required this.start,
    required this.end,
    required this.durationSeconds,
    required this.waitingTimeSeconds,
    required this.numberOfTransfers,
    this.accessibilityScore,
    required this.legs,
  });
}

/// One itinerary on a [Route] page.
class RouteEdge {
  @Deprecated(
      'Always "NoCursor": page with Route.pageInfo through planNext / planPrevious.')
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

/// A non-fatal routing problem: why the plan was declined or kept no transit itinerary in the window. An
/// unknown stop id comes back as [RoutingErrorCode.locationNotFound] with [inputField] [InputField.from],
/// [InputField.to] or [InputField.via], saying which input named it; so does an origin or destination
/// coordinate with no street near enough to link to, and one outside the area the router covers is
/// [RoutingErrorCode.outsideBounds]. A search that ran and kept no transit itinerary says why:
/// [RoutingErrorCode.noTransitConnectionInSearchWindow], or [RoutingErrorCode.walkingBetterThanTransit] when
/// walking beat every transit itinerary found.
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
  final String searchDateTime;
  // Carries the originating request so planNext/planPrevious can page without re-deriving it. Library-private.
  final _PlanRequest _request;
  const Route._({
    required this.edges,
    required this.pageInfo,
    required this.routingErrors,
    required this.searchDateTime,
    required _PlanRequest request,
  }) : _request = request;
}

/// A single departure from a stop. The route, stop and platform fields are the feed's values for display,
/// passed through as the feed gives them; null when it has none.
class Departure {
  final int scheduledTimeEpochMs;
  final int realtimeTimeEpochMs;
  final bool isRealtime;
  final RealtimeState? realtimeState;

  /// The typical delay at this stop for this trip at the requested reliability; null when no reliability is
  /// passed, the trip has live realtime, or there is no history.
  final Duration? typicalDelay;
  final String? headsign;
  final String tripGtfsId;
  final String routeGtfsId;
  final String? routeShortName;
  final String? routeLongName;

  /// The route colour: the raw GTFS hex without `#` (e.g. `"FF0000"`).
  final String? routeColor;

  /// The colour for text drawn on [routeColor]: the raw GTFS hex without `#` (e.g. `"FFFFFF"`).
  final String? routeTextColor;
  final TransitMode? mode;

  /// The stop the vehicle leaves from: for a station, the platform within it.
  final String stopGtfsId;

  /// The platform or track code (GTFS `platform_code`) of [stopGtfsId].
  final String? platformCode;

  /// Whether the trip's vehicle takes a wheelchair (GTFS `wheelchair_accessible`); null when the feed has no
  /// information.
  final WheelchairBoarding? wheelchairAccessible;

  /// The departure's position in its trip, as the trip's [TripStop.stopPosition].
  final int? stopPosition;

  /// How a rider boards here, e.g. [PickupDropoffType.coordinateWithDriver] at a stop on request. Never
  /// [PickupDropoffType.none]: the board leaves out departures nobody can board.
  final PickupDropoffType pickupType;

  /// How a rider alights here.
  final PickupDropoffType dropoffType;

  /// The GTFS service date (`YYYY-MM-DD`) this departure's trip runs on — pass it with [tripGtfsId] to
  /// [SpiderRouting.trip] and to the realtime delays lookup. An after-midnight departure can carry the
  /// previous day's date.
  final String serviceDate;

  /// The vehicle running the departure's trip run, as the realtime trip update names it; null until a vehicle
  /// is matched to the run. Its [TripVehicle.wheelchairAccessible] is the vehicle's realtime access, separate
  /// from [wheelchairAccessible], the timetable's.
  final TripVehicle? vehicle;
  const Departure({
    required this.scheduledTimeEpochMs,
    required this.realtimeTimeEpochMs,
    required this.isRealtime,
    this.realtimeState,
    this.typicalDelay,
    this.headsign,
    required this.tripGtfsId,
    required this.routeGtfsId,
    this.routeShortName,
    this.routeLongName,
    this.routeColor,
    this.routeTextColor,
    this.mode,
    required this.stopGtfsId,
    this.platformCode,
    this.wheelchairAccessible,
    this.stopPosition,
    this.pickupType = PickupDropoffType.scheduled,
    this.dropoffType = PickupDropoffType.scheduled,
    required this.serviceDate,
    this.vehicle,
  });
}

/// One stop on a trip's timetable.
class TripStop {
  final String gtfsId;
  final String name;
  final double lat;
  final double lon;
  final int scheduledArrivalEpochMs;
  final int scheduledDepartureEpochMs;
  final int realtimeArrivalEpochMs;
  final int realtimeDepartureEpochMs;
  final bool isRealtime;

  /// The typical delay at this stop for this trip at the requested reliability; null when no reliability is
  /// passed, the trip has live realtime, or there is no history.
  final Duration? typicalDelay;
  final WheelchairBoarding? wheelchairBoarding;

  /// The platform or track code (GTFS `platform_code`), when the feed gives one.
  final String? platformCode;

  /// The fare zone (GTFS `zone_id`), when the feed gives one.
  final String? zoneId;

  /// The stop's position in the trip: increasing along it, not necessarily from 0 or consecutive. A
  /// [Leg.fromStopPosition], [Leg.toStopPosition] or [Departure.stopPosition] equal to it names this stop, also
  /// on a trip that visits one stop twice. Realtime that adds or removes stops can change it.
  final int? stopPosition;

  /// The index into [TripDetails.geometry] of where the stop sits on the trip's line; null when the trip has no
  /// geometry or the stop has no point on it.
  final int? geometryIndex;

  /// How a rider boards here, e.g. [PickupDropoffType.coordinateWithDriver] at a stop on request. Null when the
  /// stop is canceled: the trip is canceled or realtime skips the stop.
  final PickupDropoffType? pickupType;

  /// How a rider alights here. Null when the stop is canceled, as [pickupType].
  final PickupDropoffType? dropoffType;
  const TripStop({
    required this.gtfsId,
    required this.name,
    required this.lat,
    required this.lon,
    required this.scheduledArrivalEpochMs,
    required this.scheduledDepartureEpochMs,
    required this.realtimeArrivalEpochMs,
    required this.realtimeDepartureEpochMs,
    required this.isRealtime,
    this.typicalDelay,
    this.wheelchairBoarding,
    this.platformCode,
    this.zoneId,
    this.stopPosition,
    this.geometryIndex,
    this.pickupType,
    this.dropoffType,
  });
}

/// A single trip's route, stops, and geometry. The route fields are the feed's values for display, passed
/// through as the feed gives them; null when it has none.
class TripDetails {
  final String gtfsId;
  final String routeGtfsId;
  final String? routeShortName;
  final String? routeLongName;

  /// The route colour: the raw GTFS hex without `#` (e.g. `"FF0000"`).
  final String? routeColor;

  /// The colour for text drawn on [routeColor]: the raw GTFS hex without `#` (e.g. `"FFFFFF"`).
  final String? routeTextColor;
  final TransitMode? mode;
  final String? headsign;
  final String? directionId;
  final BikesAllowed? bikesAllowed;

  /// Whether the trip's vehicle takes a wheelchair (GTFS `wheelchair_accessible`); null when the feed has no
  /// information.
  final WheelchairBoarding? wheelchairAccessible;

  /// The GTFS service date (`YYYY-MM-DD`) of this trip run, as requested — the value to pass to the realtime
  /// delays lookup.
  final String serviceDate;
  final List<TripStop> stops;
  final List<LatLon> geometry;

  /// The vehicle running this trip run, as the realtime trip update names it; null until a vehicle is matched
  /// to the run. Its [TripVehicle.wheelchairAccessible] is the vehicle's realtime access, separate from
  /// [wheelchairAccessible], the timetable's.
  final TripVehicle? vehicle;
  const TripDetails({
    required this.gtfsId,
    required this.routeGtfsId,
    this.routeShortName,
    this.routeLongName,
    this.routeColor,
    this.routeTextColor,
    this.mode,
    this.headsign,
    this.directionId,
    this.bikesAllowed,
    this.wheelchairAccessible,
    required this.serviceDate,
    required this.stops,
    required this.geometry,
    this.vehicle,
  });
}

/// A trip's recorded delay at one stop at each [Reliability] level, from the environment's realtime history.
class EstimatedDelays {
  /// The p50 ([Reliability.standard]).
  final Duration standard;

  /// The p70 ([Reliability.safe]).
  final Duration safe;

  /// The p90 ([Reliability.verySafe]).
  final Duration verySafe;
  const EstimatedDelays({
    required this.standard,
    required this.safe,
    required this.verySafe,
  });
}

/// Options for a trip-plan search. [departAt]/[arriveBy] are mutually exclusive (arriveBy wins if both set;
/// neither = depart now). [allowedTransitModes] empty = all modes. [excludedTransitModes] are the modes no
/// itinerary may ride, every other mode staying usable; empty excludes nothing. [TransitMode.walk] and
/// [TransitMode.unknown] are ignored in both, and both non-empty fails with [SpiderErrorCode.badRequest]
/// (field `modes.transit`, `modes.transit is invalid`) without a request. [searchWindowMinutes] defaults to
/// 60; the environment sets its maximum, and a window above it fails with [SpiderErrorCode.badRequest].
///
/// The [via] locations apply in the order given, and visit and pass-through locations may be mixed. Each takes
/// 1–10 stop ids (field `via`) and a visit waits 0–1 h ([VisitVia.minimumWaitSeconds], field
/// `via.visit.minimumWaitTime`); a visit takes a stop, so a coordinate visit is `via is invalid`. Outside that
/// the call fails with [SpiderErrorCode.badRequest] without a request. The environment sets how many via
/// locations a plan may have.
///
/// [preferences] tunes walking, transfers and boarding and leaves out routes or agencies; null keeps the
/// environment's defaults. [transitOnly] leaves out every itinerary without a transit leg.
/// [SpiderRouting.planNext] / [SpiderRouting.planPrevious] resend both from the [Route], and a stream
/// continuation sends them again from its options.
class PlanOptions {
  final Location origin;
  final Location destination;
  final DateTime? departAt;
  final DateTime? arriveBy;
  final List<ViaLocation> via;
  final List<TransitMode> allowedTransitModes;
  final int? maxTransfers;
  final int? searchWindowMinutes;

  /// Plans for a wheelchair user: rides only trips the feed marks wheelchair accessible, boards and alights only
  /// at stops it marks accessible (no information counts as not accessible), and walks strongly avoiding steps
  /// and ways mapped as not wheelchair accessible. The feed's accessibility data limits what this guarantees.
  final bool wheelchairAccessible;

  /// Plans each arrival with the trip's typical delay at this level ([Leg.typicalArrivalDelay]); null plans on
  /// the timetable.
  final Reliability? reliability;

  /// The modes no itinerary may ride; sent as `modes.transit.exclude`.
  final List<TransitMode> excludedTransitModes;

  /// Routing preferences; null, or a [RoutePreferences] with every member left out, keeps every one of the
  /// environment's defaults.
  final RoutePreferences? preferences;

  /// Leaves out every itinerary without a transit leg, such as walking the whole way. Sent as
  /// `modes.transitOnly` only when true, beside [allowedTransitModes] or [excludedTransitModes].
  final bool transitOnly;

  /// The most itineraries a [SpiderRouting.plan] page holds, from 1 up to the environment's itinerary limit;
  /// null means the limit. The API rejects a value out of range, never clamps it. Sent as `first` on the first
  /// page and after a cursor, as `last` before one. Ignored by [SpiderRouting.planStream], which sizes itself
  /// with `targetResults`.
  final int? numberOfItineraries;
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
    this.reliability,
    this.excludedTransitModes = const [],
    this.preferences,
    this.transitOnly = false,
    this.numberOfItineraries,
  });
}

/// Optional routing preferences for [PlanOptions.preferences]. Each member left out keeps the environment's
/// default, so `RoutePreferences()` asks for nothing. A value outside its range fails with
/// [SpiderErrorCode.badRequest] for the member's contract path (such as `preferences.street.walk.speed`,
/// `<path> is out of range`) without a request; the API never clamps one. The API rounds the multipliers and
/// the walking speed to its own steps.
///
/// [walkSpeed] is the walking speed on flat ground in metres per second, at least 0.1. [walkReluctance] is how
/// much worse walking is than riding for the same time, a multiplier from 0.1 to 100000: above the default it
/// walks less. [boardCost] is a generalized cost added for each boarding and [transferCost] one added for each
/// transfer, each from 0 to 1000000: higher favours fewer rides. [waitReluctance] is how much worse waiting at a
/// stop is than riding for the same time, from 0.1 to 100000: above the default it rather walks on than waits.
///
/// [transferSlack] is the least time between alighting one vehicle and boarding the next, on top of the walk
/// between the stops; [boardSlack] the least time at the stop before boarding; [alightSlack] the least time
/// needed to alight. Each is from zero to 1 hour, sent as an ISO-8601 duration.
///
/// [excludedRoutes] and [excludedAgencies] leave out every trip of those feed-prefixed route or agency ids
/// (`<feedId>:<id>`; a route id as [Leg.routeGtfsId] and [Departure.routeGtfsId] give it). An id the
/// environment's feed doesn't know excludes nothing, and empty excludes nothing.
class RoutePreferences {
  final double? walkSpeed;
  final double? walkReluctance;
  final int? boardCost;
  final int? transferCost;
  final Duration? transferSlack;
  final double? waitReluctance;
  final Duration? boardSlack;
  final Duration? alightSlack;
  final List<String> excludedRoutes;
  final List<String> excludedAgencies;
  const RoutePreferences({
    this.walkSpeed,
    this.walkReluctance,
    this.boardCost,
    this.transferCost,
    this.transferSlack,
    this.waitReluctance,
    this.boardSlack,
    this.alightSlack,
    this.excludedRoutes = const [],
    this.excludedAgencies = const [],
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
  final Reliability? reliability;
  final List<TransitMode> excludedTransitModes;
  final RoutePreferences? preferences;
  final bool transitOnly;
  final int? numberOfItineraries;
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
    this.reliability,
    required this.excludedTransitModes,
    this.preferences,
    required this.transitOnly,
    this.numberOfItineraries,
  });

  _PlanRequest withNumberOfItineraries(int? numberOfItineraries) =>
      _PlanRequest(
        origin: origin,
        destination: destination,
        timeKind: timeKind,
        time: time,
        via: via,
        allowedTransitModes: allowedTransitModes,
        maxTransfers: maxTransfers,
        searchWindowMinutes: searchWindowMinutes,
        wheelchairAccessible: wheelchairAccessible,
        reliability: reliability,
        excludedTransitModes: excludedTransitModes,
        preferences: preferences,
        transitOnly: transitOnly,
        numberOfItineraries: numberOfItineraries,
      );
}

const _defaultSearchWindowMinutes = 60;
const _defaultNumberOfDepartures = 30;
const _maxTimeRangeSeconds = 24 * 60 * 60;
const _minStreamWindowMinutes = 2 * 60;
const _maxViaStopIds = 10;
const _maxViaWaitSeconds = 60 * 60;
const _minMultiplier = 0.1;
const _maxMultiplier = 100000.0;
const _maxCost = 1000000;
const _maxSlack = Duration(hours: 1);
const _walkPreferences = 'preferences.street.walk';
const _transitPreferences = 'preferences.transit';
const _noCursor = 'NoCursor';

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

  /// Plans a trip. Returns the first window of itineraries, holding at most
  /// [PlanOptions.numberOfItineraries].
  Future<SpiderResult<Route>> plan(PlanOptions options) async {
    final invalid = _invalidVia(options.via) ??
        _invalidModes(options) ??
        _invalidPreferences(options.preferences);
    if (invalid != null) return Failure(invalid);
    return _page(_makeRequest(options));
  }

  /// The next window after [route], or null if there is none: the same request plus `after`, preferences and
  /// [PlanOptions.transitOnly] included. [numberOfItineraries] sizes this page as
  /// [PlanOptions.numberOfItineraries] does; null keeps the size [route] was asked with, and the pages after
  /// this one keep the size this page was asked with.
  Future<SpiderResult<Route>?> planNext(Route route,
      {int? numberOfItineraries}) async {
    if (!route.pageInfo.hasNextPage) return null;
    return _page(_resized(route._request, numberOfItineraries),
        after: route.pageInfo.endCursor);
  }

  /// The previous window before [route], or null if there is none: the same request plus `before`, preferences
  /// and [PlanOptions.transitOnly] included. [numberOfItineraries] sizes this page as in [planNext].
  Future<SpiderResult<Route>?> planPrevious(Route route,
      {int? numberOfItineraries}) async {
    if (!route.pageInfo.hasPreviousPage) return null;
    return _page(_resized(route._request, numberOfItineraries),
        before: route.pageInfo.startCursor);
  }

  _PlanRequest _resized(_PlanRequest request, int? numberOfItineraries) =>
      numberOfItineraries == null
          ? request
          : request.withNumberOfItineraries(numberOfItineraries);

  /// Departures from a stop, soonest first: up to [numberOfDepartures] (default 30; the environment sets the
  /// maximum) within [timeRangeSeconds] (default 24 h) of [startTime] (default now). A [timeRangeSeconds] that
  /// isn't above 0 and at most 24 h fails with [SpiderErrorCode.badRequest] (field `timeRange`) without a
  /// request. [reliability] is the level [Departure.typicalDelay] is given at; null leaves it null.
  /// [excludedModes] leaves out every departure of those modes before [numberOfDepartures] counts, so the board
  /// (and each later one paged by [startTime]) still holds up to [numberOfDepartures] departures of the other
  /// modes; empty leaves out nothing, and [TransitMode.walk] and [TransitMode.unknown] are ignored.
  Future<SpiderResult<List<Departure>>> departures(String stopId,
      {int numberOfDepartures = _defaultNumberOfDepartures,
      DateTime? startTime,
      int timeRangeSeconds = _maxTimeRangeSeconds,
      Reliability? reliability,
      List<TransitMode> excludedModes = const []}) async {
    if (timeRangeSeconds <= 0 || timeRangeSeconds > _maxTimeRangeSeconds) {
      return Failure(invalidInput('timeRange'));
    }
    try {
      final body = wire.DeparturesRequest(
        id: stopId,
        numberOfDepartures: numberOfDepartures,
        startTime: startTime == null
            ? null
            : (startTime.millisecondsSinceEpoch / 1000).floor(),
        timeRange: timeRangeSeconds,
        reliability: _reliabilityInput(reliability),
        excludeModes: _wireModes(excludedModes),
      ).toJson();
      final departures = await _transport.postJson(
          '/routing/v1/departures', body, _decodeDepartures);
      if (departures == null) {
        throw TransportError(TransportErrorKind.noData,
            'routing returned no stop or station for id=$stopId');
      }
      return Success(departures);
    } catch (e) {
      return Failure(toSpiderError(e));
    }
  }

  /// A single trip run's stops, times, and geometry. [serviceDate] (`YYYY-MM-DD`, a [Leg.serviceDate] or
  /// [Departure.serviceDate]) picks the run; a malformed date fails with [SpiderErrorCode.badRequest] without
  /// sending a request. [startTime] (GTFS `H:MM:SS` or `HH:MM:SS`, the realtime API's
  /// [LiveVehicle.startTime] or [TripUpdate.startTime]) picks the run of a frequency-based trip by its start
  /// time; null or empty answers the trip's first run on [serviceDate], and a time no run starts at is an
  /// unknown trip.
  /// [reliability] is the level [TripStop.typicalDelay] is given at; null leaves it null.
  Future<SpiderResult<TripDetails>> trip(String tripId, String serviceDate,
      {String? startTime, Reliability? reliability}) async {
    final invalid = invalidServiceDate(serviceDate);
    if (invalid != null) return Failure(invalid);
    try {
      final body = wire.TripRequest(
        id: tripId,
        serviceDate: serviceDate,
        startTime: startTime == null || startTime.isEmpty ? null : startTime,
        reliability: _reliabilityInput(reliability),
      ).toJson();
      final trip = await _transport.postJson(
          '/routing/v1/trip', body, (json) => _decodeTrip(json, serviceDate));
      if (trip == null) {
        throw TransportError(TransportErrorKind.noData,
            'routing returned no trip for id=$tripId');
      }
      return Success(trip);
    } catch (e) {
      return Failure(toSpiderError(e));
    }
  }

  /// The trip run's recorded delay at the stop at [stopPosition] (a [TripStop.stopPosition]) at each
  /// reliability level; null when the trip, the stop position or its history is unknown. History only, so live
  /// realtime never changes them: they are present for a live trip whose [TripStop.typicalDelay] is null. For a
  /// trip without live realtime they equal [trip]'s [TripStop.typicalDelay] at that level wherever that is not
  /// null; a level with no shift is zero. [startTime] picks the run of a frequency-based trip as in [trip]; a
  /// time no run starts at answers null. A malformed [serviceDate] fails with [SpiderErrorCode.badRequest]
  /// without sending a request.
  Future<SpiderResult<EstimatedDelays?>> estimatedDelays(
      String tripId, String serviceDate, int stopPosition,
      {String? startTime}) async {
    final invalid = invalidServiceDate(serviceDate);
    if (invalid != null) return Failure(invalid);
    try {
      return Success(await _transport.getJson(
          '/routing/v1/estimated-delays', _decodeEstimatedDelays,
          query: {
            'tripId': tripId,
            'serviceDate': serviceDate,
            'stopPosition': '$stopPosition',
            if (startTime != null && startTime.isNotEmpty)
              'startTime': startTime,
          }));
    } catch (e) {
      return Failure(toSpiderError(e));
    }
  }

  /// Streams the first window of itineraries over Server-Sent Events as the router sweeps the search window
  /// forward, emitting them as they finalize instead of one batched page. Cold and cancellable: listening
  /// starts the request, cancelling the subscription stops the sweep. Each [PlanStreamResult] carries
  /// itineraries with realtime delays already applied to their legs; a terminal [PlanStreamDone] then carries
  /// the continuation paging info (or a terminal [PlanStreamFailure], [SpiderErrorCode.network] when cut first).
  ///
  /// [targetResults] is how many itineraries the sweep aims for, from 1 up to the environment's result count.
  /// [maxWindowMinutes] caps how far the sweep searches: at least 120 (2 h), up to the environment's maximum
  /// search window. Below 120 the stream ends with a [PlanStreamFailure] ([SpiderErrorCode.badRequest], field
  /// `maxWindow`) without a request; a value over an environment limit fails the same way from the server. A
  /// search the router can't answer (e.g. a date outside the feed) still ends with a [PlanStreamDone], whose
  /// [PlanStreamDone.routingErrors] say why. To continue, read [PlanStreamDone.pageInfo] and call
  /// [planStreamNext] with its [RoutePageInfo.endCursor] (or [planStreamPrevious] with its
  /// [RoutePageInfo.startCursor]). For a single batched page instead, use [plan].
  /// [PlanOptions.searchWindowMinutes] and [PlanOptions.numberOfItineraries] are ignored here — the stream
  /// paces itself with [targetResults]/[maxWindowMinutes]. A continuation's cursor carries only the time and
  /// the window it continues, so pass it the same options: their preferences, mode filters and
  /// [PlanOptions.transitOnly] are sent again.
  Stream<PlanStreamEvent> planStream(
    PlanOptions options, {
    required int targetResults,
    required int maxWindowMinutes,
  }) {
    return _planStream(options, targetResults, maxWindowMinutes, null, null);
  }

  /// Continues [planStream] forward from a [PlanStreamDone.pageInfo] whose [RoutePageInfo.hasNextPage] is set,
  /// passing its [RoutePageInfo.endCursor] as [after]. Repeats [planStream]'s parameters so the sweep can be
  /// re-paced per continuation.
  Stream<PlanStreamEvent> planStreamNext(
    PlanOptions options, {
    required int targetResults,
    required int maxWindowMinutes,
    required String after,
  }) {
    return _planStream(options, targetResults, maxWindowMinutes, null, after);
  }

  /// Continues [planStream] backward from a [PlanStreamDone.pageInfo] whose [RoutePageInfo.hasPreviousPage] is
  /// set, passing its [RoutePageInfo.startCursor] as [before]. Repeats [planStream]'s parameters so the sweep
  /// can be re-paced per continuation.
  Stream<PlanStreamEvent> planStreamPrevious(
    PlanOptions options, {
    required int targetResults,
    required int maxWindowMinutes,
    required String before,
  }) {
    return _planStream(options, targetResults, maxWindowMinutes, before, null);
  }

  Stream<PlanStreamEvent> _planStream(
    PlanOptions options,
    int targetResults,
    int maxWindowMinutes,
    String? before,
    String? after,
  ) async* {
    final invalid = maxWindowMinutes < _minStreamWindowMinutes
        ? invalidInput('maxWindow')
        : _invalidVia(options.via) ??
            _invalidModes(options) ??
            _invalidPreferences(options.preferences);
    if (invalid != null) {
      yield PlanStreamFailure(invalid);
      return;
    }
    PlanStreamEvent? terminal;
    try {
      final request = _makeRequest(options);
      final iso = request.time.toUtc().toIso8601String();
      final dateTime = request.timeKind == _TimeKind.departAt
          ? wire.PlanDateTimeInput(earliestDeparture: iso)
          : wire.PlanDateTimeInput(latestArrival: iso);
      final body = wire.PlanStreamRequest(
        dateTime: dateTime,
        origin: _locationToInput(request.origin),
        destination: _locationToInput(request.destination),
        via: request.via.isEmpty ? null : request.via.map(_viaToInput).toList(),
        modes: _modesInput(request),
        preferences: _preferencesInput(request),
        targetResults: targetResults,
        maxWindow: 'PT${maxWindowMinutes}M',
        reliability: _reliabilityInput(request.reliability),
        before: before,
        after: after,
      ).toJson();
      // Drain past the terminal event: the gateway meters the stream at its own `done`.
      await for (final frame
          in _transport.sse('/routing/v1/plan-stream', body)) {
        if (terminal != null) continue;
        final event = await _parseRecordInBackground(frame.event, frame.data);
        if (event == null) continue;
        yield event;
        if (event is! PlanStreamResult) terminal = event;
      }
    } catch (e) {
      if (terminal == null) yield PlanStreamFailure(toSpiderError(e));
      return;
    }
    if (terminal == null) {
      yield const PlanStreamFailure(SpiderError(SpiderErrorCode.network,
          'POST /routing/v1/plan-stream ended without pageInfo'));
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
      reliability: options.reliability,
      excludedTransitModes: options.excludedTransitModes,
      preferences: options.preferences,
      transitOnly: options.transitOnly,
      numberOfItineraries: options.numberOfItineraries,
    );
  }

  Future<SpiderResult<Route>> _page(_PlanRequest request,
      {String? before, String? after}) async {
    try {
      return Success(await _fetchPlan(request, before: before, after: after));
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
    final body = wire.PlanTripRequest(
      dateTime: dateTime,
      origin: _locationToInput(request.origin),
      destination: _locationToInput(request.destination),
      via: request.via.isEmpty ? null : request.via.map(_viaToInput).toList(),
      modes: _modesInput(request),
      preferences: _preferencesInput(request),
      searchWindow: 'PT${request.searchWindowMinutes}M',
      first: before == null ? request.numberOfItineraries : null,
      last: before != null ? request.numberOfItineraries : null,
      reliability: _reliabilityInput(request.reliability),
      before: before,
      after: after,
    ).toJson();
    final page =
        await _transport.postJson('/routing/v1/plan', body, _decodePlanPage);
    return Route._(
        edges: page.edges,
        pageInfo: page.pageInfo,
        routingErrors: page.routingErrors,
        searchDateTime: page.searchDateTime,
        request: request);
  }
}

// MARK: response decoders

typedef _PlanPage = ({
  List<RouteEdge> edges,
  RoutePageInfo pageInfo,
  List<RoutingError> routingErrors,
  String searchDateTime,
});

_PlanPage _decodePlanPage(Map<String, dynamic> json) {
  final plan = wire.PlanTripResponse.fromJson(json);
  return (
    edges: plan.itineraries
        .map((i) => RouteEdge(_noCursor, _mapItinerary(i)))
        .toList(),
    pageInfo: RoutePageInfo(
      startCursor: plan.pageInfo.startCursor,
      endCursor: plan.pageInfo.endCursor,
      hasNextPage: plan.pageInfo.hasNextPage,
      hasPreviousPage: plan.pageInfo.hasPreviousPage,
      searchWindowUsed: plan.pageInfo.searchWindowUsed,
    ),
    routingErrors: plan.routingErrors.map(_mapRoutingError).toList(),
    searchDateTime: plan.searchDateTime,
  );
}

List<Departure>? _decodeDepartures(Map<String, dynamic> json) {
  final stop = wire.DeparturesResponse.fromJson(json).stop;
  return stop == null ? null : _mapDepartures(stop);
}

TripDetails? _decodeTrip(Map<String, dynamic> json, String serviceDate) {
  final trip = wire.TripResponse.fromJson(json).trip;
  return trip == null ? null : _mapTrip(trip, serviceDate);
}

EstimatedDelays? _decodeEstimatedDelays(Map<String, dynamic> json) {
  final List<wire.EstimatedDelay>? entries;
  try {
    entries = wire.EstimatedDelaysResponse.fromJson(json).estimatedDelays;
  } catch (e) {
    throw SpiderDecodingError(
        'failed to decode GET /routing/v1/estimated-delays', e);
  }
  if (entries == null) return null;
  final byLevel = {for (final e in entries) e.reliability: e.delay};
  Duration level(wire.Reliability reliability) {
    final seconds = byLevel[reliability];
    if (seconds == null) {
      throw SpiderDecodingError(
          'failed to decode GET /routing/v1/estimated-delays',
          'no ${reliability.wire} entry');
    }
    return Duration(seconds: seconds);
  }

  return EstimatedDelays(
    standard: level(wire.Reliability.standard),
    safe: level(wire.Reliability.safe),
    verySafe: level(wire.Reliability.verySafe),
  );
}

Future<PlanStreamEvent?> _parseRecordInBackground(String event, String data) =>
    decodeInBackground(data, () => parsePlanStreamRecord(event, data));

// MARK: request builders

// Fixed platform limits on each via location. How many via locations a plan may have is an environment
// setting, so the server checks that.
SpiderError? _invalidVia(List<ViaLocation> via) {
  for (final location in via) {
    final invalid = switch (location) {
      PassThroughVia(:final stopIds) =>
        stopIds.isEmpty || stopIds.length > _maxViaStopIds
            ? invalidInput('via')
            : null,
      VisitVia(:final minimumWaitSeconds) =>
        minimumWaitSeconds < 0 || minimumWaitSeconds > _maxViaWaitSeconds
            ? invalidInput('via.visit.minimumWaitTime')
            : null,
    };
    if (invalid != null) return invalid;
  }
  return null;
}

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
        CoordinateLocation() => throw invalidInput('via', malformed: true),
      };
  }
}

// The modes a filter sends, dropping WALK/UNKNOWN (no wire transit mode); null when none is left.
List<wire.TransitMode>? _wireModes(List<TransitMode> modes) {
  final wireModes = modes
      .where((m) => _wireTransitModes.contains(m.wire))
      .map((m) => wire.TransitMode.fromWire(m.wire))
      .toList();
  return wireModes.isEmpty ? null : wireModes;
}

// The API takes an allow-list or an exclude-list, never both.
SpiderError? _invalidModes(PlanOptions options) =>
    _wireModes(options.allowedTransitModes) != null &&
            _wireModes(options.excludedTransitModes) != null
        ? invalidInput('modes.transit', malformed: true)
        : null;

wire.PlanModesInput? _modesInput(_PlanRequest request) {
  final transit = _wireModes(request.allowedTransitModes)
      ?.map((mode) => wire.PlanTransitModePreferenceInput(mode: mode))
      .toList();
  final exclude = _wireModes(request.excludedTransitModes);
  final transitModes = transit == null && exclude == null
      ? null
      : wire.PlanTransitModesInput(transit: transit, exclude: exclude);
  if (transitModes == null && !request.transitOnly) return null;
  return wire.PlanModesInput(
      transitOnly: request.transitOnly ? true : null, transit: transitModes);
}

SpiderError? _invalidPreferences(RoutePreferences? preferences) {
  if (preferences == null) return null;
  bool multiplier(double value) =>
      value >= _minMultiplier && value <= _maxMultiplier;
  bool cost(int value) => value >= 0 && value <= _maxCost;
  bool slack(Duration value) => value >= Duration.zero && value <= _maxSlack;
  final checks = <(String, bool)>[
    if (preferences.walkSpeed case final speed?)
      ('$_walkPreferences.speed', speed.isFinite && speed >= _minMultiplier),
    if (preferences.walkReluctance case final value?)
      ('$_walkPreferences.reluctance', multiplier(value)),
    if (preferences.boardCost case final value?)
      ('$_walkPreferences.boardCost', cost(value)),
    if (preferences.transferCost case final value?)
      ('$_transitPreferences.transfer.cost', cost(value)),
    if (preferences.transferSlack case final value?)
      ('$_transitPreferences.transfer.slack', slack(value)),
    if (preferences.waitReluctance case final value?)
      ('$_transitPreferences.board.waitReluctance', multiplier(value)),
    if (preferences.boardSlack case final value?)
      ('$_transitPreferences.board.slack', slack(value)),
    if (preferences.alightSlack case final value?)
      ('$_transitPreferences.alight.slack', slack(value)),
  ];
  for (final (field, valid) in checks) {
    if (!valid) return invalidInput(field);
  }
  return null;
}

wire.PlanPreferencesInput? _preferencesInput(_PlanRequest request) {
  final maxTransfers = request.maxTransfers;
  final preferences = request.preferences;
  final transferCost = preferences?.transferCost;
  final transferSlack = preferences?.transferSlack;
  // The router indexes legs with leg 0 = the initial access (walk, or nothing), so its wire
  // `maximumTransfers` counts boardings = transfers + 1 (wire 0 = walk-only, not exposed here).
  // `maxTransfers` is a transfer count, so map it to boardings: 0 transfers = 1 boarding (direct).
  final transfer =
      maxTransfers != null || transferCost != null || transferSlack != null
          ? wire.TransferPreferencesInput(
              cost: transferCost,
              slack: transferSlack == null ? null : _isoDuration(transferSlack),
              maximumTransfers: maxTransfers == null ? null : maxTransfers + 1)
          : null;
  final waitReluctance = preferences?.waitReluctance;
  final boardSlack = preferences?.boardSlack;
  final board = waitReluctance != null || boardSlack != null
      ? wire.BoardPreferencesInput(
          waitReluctance: waitReluctance,
          slack: boardSlack == null ? null : _isoDuration(boardSlack))
      : null;
  final alightSlack = preferences?.alightSlack;
  final alight = alightSlack == null
      ? null
      : wire.AlightPreferencesInput(slack: _isoDuration(alightSlack));
  final filters = preferences == null ? null : _filtersInput(preferences);
  final transit =
      transfer != null || board != null || alight != null || filters != null
          ? wire.TransitPreferencesInput(
              transfer: transfer,
              board: board,
              alight: alight,
              filters: filters)
          : null;
  final walkSpeed = preferences?.walkSpeed;
  final walkReluctance = preferences?.walkReluctance;
  final boardCost = preferences?.boardCost;
  final street =
      walkSpeed != null || walkReluctance != null || boardCost != null
          ? wire.PlanStreetPreferencesInput(
              walk: wire.WalkPreferencesInput(
                  speed: walkSpeed,
                  reluctance: walkReluctance,
                  boardCost: boardCost))
          : null;
  final accessibility = request.wheelchairAccessible
      ? wire.AccessibilityPreferencesInput(
          wheelchair: wire.WheelchairPreferencesInput(enabled: true))
      : null;
  if (street == null && transit == null && accessibility == null) return null;
  return wire.PlanPreferencesInput(
      street: street, accessibility: accessibility, transit: transit);
}

List<wire.TransitFilterInput>? _filtersInput(RoutePreferences preferences) {
  final selectors = [
    if (preferences.excludedRoutes.isNotEmpty)
      wire.TransitFilterSelectInput(routes: preferences.excludedRoutes),
    if (preferences.excludedAgencies.isNotEmpty)
      wire.TransitFilterSelectInput(agencies: preferences.excludedAgencies),
  ];
  return selectors.isEmpty
      ? null
      : [wire.TransitFilterInput(exclude: selectors)];
}

String _isoDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final micros =
      duration.inMicroseconds.remainder(Duration.microsecondsPerMinute);
  final seconds = micros ~/ Duration.microsecondsPerSecond;
  final fraction = micros.remainder(Duration.microsecondsPerSecond);
  final secondsText = fraction == 0
      ? '$seconds'
      : '$seconds.${'$fraction'.padLeft(6, '0').replaceFirst(RegExp(r'0+$'), '')}';
  return [
    'PT',
    if (hours != 0) '${hours}H',
    if (minutes != 0) '${minutes}M',
    if (micros != 0 || duration == Duration.zero) '${secondsText}S',
  ].join();
}

wire.Reliability? _reliabilityInput(Reliability? reliability) =>
    reliability == null ? null : wire.Reliability.fromWire(reliability.wire);

// MARK: plan-stream record parsing

/// One SSE record as a [PlanStreamEvent], a [PlanStreamFailure] when malformed, or null when not surfaced.
PlanStreamEvent? parsePlanStreamRecord(String event, String data) {
  if (data.trim().isEmpty) return null;
  switch (event) {
    case 'chunk':
      try {
        final chunk = wire.PlanStreamChunkEvent.fromJson(
            jsonDecode(data) as Map<String, dynamic>);
        return PlanStreamResult(chunk.results.map(_mapItinerary).toList());
      } catch (e) {
        return PlanStreamFailure(_streamDecodingError('chunk', e));
      }
    case 'pageInfo':
      try {
        final page = wire.PlanStreamPageInfoEvent.fromJson(
            jsonDecode(data) as Map<String, dynamic>);
        return PlanStreamDone(
          RoutePageInfo(
            startCursor: page.startCursor,
            endCursor: page.endCursor,
            hasNextPage: page.hasNextPage,
            hasPreviousPage: page.hasPreviousPage,
            searchWindowUsed: page.searchWindowUsed,
          ),
          routingErrors: page.routingErrors.map(_mapRoutingError).toList(),
        );
      } catch (e) {
        return PlanStreamFailure(_streamDecodingError('pageInfo', e));
      }
    default:
      return null;
  }
}

SpiderError _streamDecodingError(String event, Object cause) => SpiderError(
    SpiderErrorCode.decoding, 'failed to parse plan-stream $event record',
    cause: cause);

// MARK: response mappers

RoutingError _mapRoutingError(wire.RoutingError w) => RoutingError(
    RoutingErrorCode.fromWire(w.code.wire),
    w.description,
    InputField.fromWire(w.inputField?.wire));

Itinerary _mapItinerary(wire.Itinerary w) => Itinerary(
      start: w.start,
      end: w.end,
      durationSeconds: w.duration,
      waitingTimeSeconds: w.waitingTime,
      numberOfTransfers: w.numberOfTransfers,
      legs: w.legs.map(_mapLeg).toList(),
    );

Leg _mapLeg(wire.Leg w) {
  final startEstimated = w.start.estimated;
  final endEstimated = w.end.estimated;
  final fromStop = w.from.stop;
  final toStop = w.to.stop;
  final route = w.route;
  final trip = w.trip;
  return Leg(
    mode: TransitMode.fromWire(w.mode.wire),
    startScheduled: w.start.scheduledTime,
    endScheduled: w.end.scheduledTime,
    startEstimated: startEstimated?.time,
    endEstimated: endEstimated?.time,
    startDelay: _durationFromWire(startEstimated?.delay),
    endDelay: _durationFromWire(endEstimated?.delay),
    typicalArrivalDelay: _durationFromSeconds(w.typicalArrivalDelay),
    isRealtime: w.realTime,
    realtimeState: RealtimeState.fromWire(w.realtimeState.wire),
    serviceDate: w.serviceDate,
    fromName: w.from.name,
    toName: w.to.name,
    fromGtfsId: fromStop?.gtfsId,
    toGtfsId: toStop?.gtfsId,
    fromStopPosition: w.from.stopPosition,
    toStopPosition: w.to.stopPosition,
    fromPlatformCode: fromStop?.platformCode,
    toPlatformCode: toStop?.platformCode,
    fromZoneId: fromStop?.zoneId,
    toZoneId: toStop?.zoneId,
    routeGtfsId: route?.gtfsId,
    routeShortName: route?.shortName,
    routeLongName: route?.longName,
    routeColor: route?.color,
    routeTextColor: route?.textColor,
    headsign: w.headsign,
    distanceMeters: w.distance,
    durationSeconds: w.duration,
    tripGtfsId: trip?.gtfsId,
    interlineWithPreviousLeg: w.interlineWithPreviousLeg,
    pickupType: PickupDropoffType.fromWire(w.pickupType.wire),
    dropoffType: PickupDropoffType.fromWire(w.dropoffType.wire),
    bikesAllowed: BikesAllowed.fromWire(trip?.bikesAllowed.wire),
    fromWheelchair:
        WheelchairBoarding.fromWire(fromStop?.wheelchairBoarding.wire),
    toWheelchair: WheelchairBoarding.fromWire(toStop?.wheelchairBoarding.wire),
    geometry: decodePolyline(w.legGeometry.points),
    vehicle: _mapTripVehicle(w.vehicle),
  );
}

TripVehicle? _mapTripVehicle(wire.TripVehicle? w) => w == null
    ? null
    : TripVehicle(
        id: w.id,
        label: w.label,
        wheelchairAccessible:
            WheelchairBoarding.fromWire(w.wheelchairAccessible.wire),
        airConditioning: w.airConditioning,
        wifi: w.wifi,
        cardPayment: w.cardPayment,
      );

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

PickupDropoffType? _pickupDropoff(wire.PickupDropoffType? w) =>
    w == null ? null : PickupDropoffType.fromWire(w.wire);

Duration? _durationFromSeconds(int? seconds) =>
    seconds == null ? null : Duration(seconds: seconds);

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

List<Departure> _mapDepartures(wire.DepartureBoard stop) => [
      for (final st in stop.stoptimesWithoutPatterns)
        Departure(
          scheduledTimeEpochMs: (st.serviceDay + st.scheduledDeparture) * 1000,
          realtimeTimeEpochMs: (st.serviceDay + st.realtimeDeparture) * 1000,
          isRealtime: st.realtime,
          realtimeState: RealtimeState.fromWire(st.realtimeState.wire),
          typicalDelay: _durationFromSeconds(st.typicalDelay),
          headsign: st.headsign,
          tripGtfsId: st.trip.gtfsId,
          routeGtfsId: st.trip.route.gtfsId,
          routeShortName: st.trip.route.shortName,
          routeLongName: st.trip.route.longName,
          routeColor: st.trip.route.color,
          routeTextColor: st.trip.route.textColor,
          mode: TransitMode.fromWire(st.trip.route.mode.wire),
          stopGtfsId: st.stop.gtfsId,
          platformCode: st.stop.platformCode,
          wheelchairAccessible:
              WheelchairBoarding.fromWire(st.trip.wheelchairAccessible.wire),
          stopPosition: st.stopPosition,
          pickupType: PickupDropoffType.fromWire(st.pickupType.wire),
          dropoffType: PickupDropoffType.fromWire(st.dropoffType.wire),
          serviceDate: st.serviceDate,
          vehicle: _mapTripVehicle(st.vehicle),
        ),
    ];

TripDetails _mapTrip(wire.TripTimetable w, String serviceDate) {
  final stoptimes = w.stoptimesForDate;
  final geometry = w.tripGeometry;
  return TripDetails(
    gtfsId: w.gtfsId,
    routeGtfsId: w.route.gtfsId,
    routeShortName: w.route.shortName,
    routeLongName: w.route.longName,
    routeColor: w.route.color,
    routeTextColor: w.route.textColor,
    mode: TransitMode.fromWire(w.route.mode.wire),
    headsign: w.tripHeadsign,
    directionId: w.directionId,
    bikesAllowed: BikesAllowed.fromWire(w.bikesAllowed.wire),
    wheelchairAccessible:
        WheelchairBoarding.fromWire(w.wheelchairAccessible.wire),
    serviceDate: serviceDate,
    stops: [
      for (final st in stoptimes)
        TripStop(
          gtfsId: st.stop.gtfsId,
          name: st.stop.name,
          lat: st.stop.lat,
          lon: st.stop.lon,
          scheduledArrivalEpochMs: (st.serviceDay + st.scheduledArrival) * 1000,
          scheduledDepartureEpochMs:
              (st.serviceDay + st.scheduledDeparture) * 1000,
          realtimeArrivalEpochMs: (st.serviceDay + st.realtimeArrival) * 1000,
          realtimeDepartureEpochMs:
              (st.serviceDay + st.realtimeDeparture) * 1000,
          isRealtime: st.realtime,
          typicalDelay: _durationFromSeconds(st.typicalDelay),
          wheelchairBoarding:
              WheelchairBoarding.fromWire(st.stop.wheelchairBoarding.wire),
          platformCode: st.stop.platformCode,
          zoneId: st.stop.zoneId,
          stopPosition: st.stopPosition,
          geometryIndex: st.geometryIndex,
          pickupType: _pickupDropoff(st.pickupType),
          dropoffType: _pickupDropoff(st.dropoffType),
        ),
    ],
    geometry: geometry == null ? const [] : decodePolyline(geometry.points),
    vehicle: _mapTripVehicle(w.vehicle),
  );
}
