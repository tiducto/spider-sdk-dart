import 'dart:convert';
import 'enums.dart';
import 'errors.dart';
import 'polyline.dart';
import 'result.dart';
import 'service_date.dart';
import 'transport.dart';
import 'trip_vehicle.dart';

// MARK: public realtime models (toJson is used by the poll* streams to de-duplicate consecutive results)

/// How fresh a realtime feed is. Timestamps are epoch milliseconds; `staleSeconds` is age in seconds.
class FeedFreshness {
  final int? feedTimestampEpochMs;
  final int? staleSeconds;
  const FeedFreshness({this.feedTimestampEpochMs, this.staleSeconds});
  Map<String, dynamic> toJson() => {
        'feedTimestampEpochMs': feedTimestampEpochMs,
        'staleSeconds': staleSeconds
      };
}

/// A vehicle's live position. GTFS-RT producers populate different subsets, so beyond the trip and position every
/// field is optional.
/// [tripId], [routeId], [stopId] and [vehicleId] are feed-prefixed (`<feedId>:<id>`), like routing's ids.
class LiveVehicle {
  final String tripId;

  /// The GTFS service date (`YYYY-MM-DD`) of the trip run the vehicle is on.
  final String serviceDate;

  /// The start time of the trip run (GTFS `HH:MM:SS`, may exceed `24:00:00`), as the feed's GTFS-RT
  /// `start_time` gives it; it tells apart the runs of a frequency-based trip. Null when the feed gives none.
  final String? startTime;
  final String? routeId;
  final String? vehicleId;
  final String? label;
  final double latitude;
  final double longitude;
  final double? bearing;
  final double? speed;
  final String? stopId;
  final String? currentStatus;
  final OccupancyStatus? occupancy;
  final int? timestampEpochMs;

  /// Whether a wheelchair user can board the vehicle reported for the trip, from GTFS-RT
  /// `VehicleDescriptor.wheelchair_accessible`; null when the feed gives no value or `UNKNOWN`.
  final WheelchairBoarding? wheelchairAccessible;

  /// Whether the vehicle reported for the trip is air-conditioned; null when unknown.
  final bool? airConditioning;

  /// Whether the vehicle reported for the trip offers Wi-Fi; null when unknown.
  final bool? wifi;

  /// Whether the vehicle reported for the trip accepts card payment on board; null when unknown.
  final bool? cardPayment;
  const LiveVehicle({
    required this.tripId,
    required this.serviceDate,
    this.startTime,
    this.routeId,
    this.vehicleId,
    this.label,
    required this.latitude,
    required this.longitude,
    this.bearing,
    this.speed,
    this.stopId,
    this.currentStatus,
    this.occupancy,
    this.timestampEpochMs,
    this.wheelchairAccessible,
    this.airConditioning,
    this.wifi,
    this.cardPayment,
  });
  Map<String, dynamic> toJson() => {
        'tripId': tripId,
        'serviceDate': serviceDate,
        'startTime': startTime,
        'routeId': routeId,
        'vehicleId': vehicleId,
        'label': label,
        'latitude': latitude,
        'longitude': longitude,
        'bearing': bearing,
        'speed': speed,
        'stopId': stopId,
        'currentStatus': currentStatus,
        'occupancy': occupancy?.wire,
        'timestampEpochMs': timestampEpochMs,
        'wheelchairAccessible': wheelchairAccessible?.wire,
        'airConditioning': airConditioning,
        'wifi': wifi,
        'cardPayment': cardPayment,
      };
}

/// A single trip's live vehicle plus feed freshness (`vehicle` null = none currently reporting).
class LiveVehicleUpdate {
  final LiveVehicle? vehicle;
  final FeedFreshness freshness;
  const LiveVehicleUpdate(this.vehicle, this.freshness);
  Map<String, dynamic> toJson() =>
      {'vehicle': vehicle?.toJson(), 'freshness': freshness.toJson()};
}

/// Live positions for a set of trips, plus the trip ids that had no live vehicle.
class VehiclePositions {
  final List<LiveVehicle> vehicles;
  final List<String> missing;
  final FeedFreshness freshness;
  const VehiclePositions(this.vehicles, this.missing, this.freshness);
  Map<String, dynamic> toJson() => {
        'vehicles': vehicles.map((v) => v.toJson()).toList(),
        'missing': missing,
        'freshness': freshness.toJson()
      };
}

/// One stop's realtime deviation within a trip.
class StopTimeUpdate {
  final String? stopId;
  final int? stopSequence;
  final int? arrivalDelay;
  final int? departureDelay;
  final String? scheduleRelationship;
  const StopTimeUpdate(
      {this.stopId,
      this.stopSequence,
      this.arrivalDelay,
      this.departureDelay,
      this.scheduleRelationship});
  Map<String, dynamic> toJson() => {
        'stopId': stopId,
        'stopSequence': stopSequence,
        'arrivalDelay': arrivalDelay,
        'departureDelay': departureDelay,
        'scheduleRelationship': scheduleRelationship,
      };
}

/// A trip's live schedule deviation. Delay values are in seconds. [tripId], [routeId] and each
/// [StopTimeUpdate.stopId] are feed-prefixed (`<feedId>:<id>`).
class TripDelay {
  final String tripId;
  final String? routeId;
  final int? delaySeconds;
  final String? scheduleRelationship;
  final List<StopTimeUpdate> stopTimeUpdates;
  const TripDelay(
      {required this.tripId,
      this.routeId,
      this.delaySeconds,
      this.scheduleRelationship,
      this.stopTimeUpdates = const []});
  Map<String, dynamic> toJson() => {
        'tripId': tripId,
        'routeId': routeId,
        'delaySeconds': delaySeconds,
        'scheduleRelationship': scheduleRelationship,
        'stopTimeUpdates': stopTimeUpdates.map((s) => s.toJson()).toList(),
      };
}

/// Live delays for one GTFS service date: those the feed reported, and the [missing] trip ids it didn't,
/// exactly as requested. Look one up with [delayFor].
class TripDelays {
  final String serviceDate;
  final List<TripDelay> delays;
  final List<String> missing;
  final FeedFreshness freshness;
  const TripDelays(this.serviceDate, this.delays, this.missing, this.freshness);

  /// The delay for [tripId] on [serviceDate], if the feed reported one.
  TripDelay? delayFor(String tripId) {
    for (final delay in delays) {
      if (delay.tripId == tripId) return delay;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'serviceDate': serviceDate,
        'delays': delays.map((d) => d.toJson()).toList(),
        'missing': missing,
        'freshness': freshness.toJson(),
      };
}

/// An original stop time of a trip, by [stopSequence] and/or [stopId] as the feed gives it. Experimental, as
/// GTFS-RT `StopSelector`. [stopId] is feed-prefixed (`<feedId>:<id>`).
class StopSelector {
  final int? stopSequence;
  final String? stopId;
  const StopSelector({this.stopSequence, this.stopId});
  Map<String, dynamic> toJson() =>
      {'stopSequence': stopSequence, 'stopId': stopId};
}

/// A stop a modified trip visits in place of the replaced span. Experimental, as GTFS-RT `ReplacementStop`.
/// [stopId] is feed-prefixed (`<feedId>:<id>`); [name], [latitude] and [longitude] are set only when the feed
/// defines the stop as a realtime `Stop` entity, otherwise the stop is a static one that stop search returns.
class ReplacementStop {
  final String? stopId;

  /// Seconds from the arrival at the reference stop (the stop before [TripModification.startStop], or the
  /// trip's first stop when the modification starts there) to the arrival here.
  final int? travelTimeToStopSeconds;
  final String? name;
  final double? latitude;
  final double? longitude;
  const ReplacementStop(
      {this.stopId,
      this.travelTimeToStopSeconds,
      this.name,
      this.latitude,
      this.longitude});
  Map<String, dynamic> toJson() => {
        'stopId': stopId,
        'travelTimeToStopSeconds': travelTimeToStopSeconds,
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
      };
}

/// A detour of a trip run: the span of its stop times from [startStop] to [endStop] replaced by
/// [replacementStops]. Experimental, as GTFS-RT `TripModifications.Modification`: its shape may change in a
/// later contract version. A member the feed doesn't set is null.
class TripModification {
  /// Feed-prefixed (`<feedId>:<id>`) id of the feed entity holding the trip modifications.
  final String id;

  /// GTFS times (`HH:MM:SS`) of the runs of a frequency-based trip the modification applies to; null when it
  /// applies to every run of the trip on the service date.
  final List<String>? startTimes;

  /// The first original stop time replaced.
  final StopSelector? startStop;

  /// The last original stop time replaced, inclusive; null when no stop time is replaced.
  final StopSelector? endStop;

  /// The stops the trip now visits in place of the replaced span, in order; empty when the feed lists none.
  final List<ReplacementStop> replacementStops;

  /// Seconds added to every arrival and departure after the end of the modification; 0 when the feed doesn't
  /// set it.
  final int propagatedModificationDelaySeconds;

  /// Feed-prefixed id of the [ServiceAlert] describing the modification, as [SpiderRealtime.alerts] returns it.
  final String? alertId;

  /// When the modification last changed, epoch milliseconds.
  final int? lastModifiedEpochMs;

  /// The modified trip's path, from the feed's realtime `Shape` entity; null when the feed has none for it.
  final List<LatLon>? shape;
  const TripModification({
    required this.id,
    this.startTimes,
    this.startStop,
    this.endStop,
    this.replacementStops = const [],
    this.propagatedModificationDelaySeconds = 0,
    this.alertId,
    this.lastModifiedEpochMs,
    this.shape,
  });
  Map<String, dynamic> toJson() => {
        'id': id,
        'startTimes': startTimes,
        'startStop': startStop?.toJson(),
        'endStop': endStop?.toJson(),
        'replacementStops': replacementStops.map((s) => s.toJson()).toList(),
        'propagatedModificationDelaySeconds':
            propagatedModificationDelaySeconds,
        'alertId': alertId,
        'lastModifiedEpochMs': lastModifiedEpochMs,
        'shape': shape?.map((p) => p.toJson()).toList(),
      };
}

/// The live update of one trip run: its schedule deviation (seconds, as in [TripDelay]) and the
/// [modifications] (detours) that select it. A run that only modifications select has empty [stopTimeUpdates]
/// and null [delaySeconds], [scheduleRelationship] and [routeId]. [tripId], [routeId] and each
/// [StopTimeUpdate.stopId] are feed-prefixed (`<feedId>:<id>`).
class TripUpdate {
  final String tripId;

  /// The start time of the trip run (GTFS `HH:MM:SS`, may exceed `24:00:00`), as the feed gives it; each run of
  /// a frequency-based trip is its own [TripUpdate]. Null when the feed gives none.
  final String? startTime;
  final String? routeId;
  final int? delaySeconds;
  final String? scheduleRelationship;
  final List<StopTimeUpdate> stopTimeUpdates;

  /// The trip modifications that apply to this run, in feed order; their delays accumulate along the trip.
  /// Empty when none applies. Experimental, as GTFS-RT `TripModifications`.
  final List<TripModification> modifications;

  /// The vehicle the update names for this run, with its features; null when the feed names none.
  final TripVehicle? vehicle;
  const TripUpdate(
      {required this.tripId,
      this.startTime,
      this.routeId,
      this.delaySeconds,
      this.scheduleRelationship,
      this.stopTimeUpdates = const [],
      this.modifications = const [],
      this.vehicle});
  Map<String, dynamic> toJson() => {
        'tripId': tripId,
        'startTime': startTime,
        'routeId': routeId,
        'delaySeconds': delaySeconds,
        'scheduleRelationship': scheduleRelationship,
        'stopTimeUpdates': stopTimeUpdates.map((s) => s.toJson()).toList(),
        'modifications': modifications.map((m) => m.toJson()).toList(),
        'vehicle': vehicle?.toJson(),
      };
}

/// Live trip updates for one GTFS service date, one per trip run, and the [missing] trip ids with neither a live
/// update nor a trip modification, exactly as requested. Look a trip's runs up with [updatesFor].
class TripUpdates {
  final String serviceDate;
  final List<TripUpdate> tripUpdates;
  final List<String> missing;
  final FeedFreshness freshness;
  const TripUpdates(
      this.serviceDate, this.tripUpdates, this.missing, this.freshness);

  /// The updates of [tripId]'s runs on [serviceDate], in order of [TripUpdate.startTime] (a run without one
  /// first); empty when the feed reported none.
  List<TripUpdate> updatesFor(String tripId) =>
      tripUpdates.where((u) => u.tripId == tripId).toList();

  Map<String, dynamic> toJson() => {
        'serviceDate': serviceDate,
        'tripUpdates': tripUpdates.map((u) => u.toJson()).toList(),
        'missing': missing,
        'freshness': freshness.toJson(),
      };
}

/// A time window an alert is active for. Epoch milliseconds.
class AlertActivePeriod {
  final int? startEpochMs;
  final int? endEpochMs;
  const AlertActivePeriod(this.startEpochMs, this.endEpochMs);
  Map<String, dynamic> toJson() =>
      {'startEpochMs': startEpochMs, 'endEpochMs': endEpochMs};
}

/// What an alert applies to.
class AlertInformedEntity {
  final String? agencyId;
  final String? routeId;
  final String? tripId;
  final String? stopId;
  const AlertInformedEntity(
      {this.agencyId, this.routeId, this.tripId, this.stopId});
  Map<String, dynamic> toJson() => {
        'agencyId': agencyId,
        'routeId': routeId,
        'tripId': tripId,
        'stopId': stopId
      };
}

/// A service alert. Text is already resolved to one language; cause/effect/severity are raw GTFS-RT strings.
class ServiceAlert {
  final String id;
  final String? cause;
  final String? effect;
  final String? severityLevel;
  final String? headerText;
  final String? descriptionText;
  final String? url;
  final List<AlertActivePeriod> activePeriods;
  final List<AlertInformedEntity> informedEntities;
  const ServiceAlert({
    required this.id,
    this.cause,
    this.effect,
    this.severityLevel,
    this.headerText,
    this.descriptionText,
    this.url,
    this.activePeriods = const [],
    this.informedEntities = const [],
  });
  Map<String, dynamic> toJson() => {
        'id': id,
        'cause': cause,
        'effect': effect,
        'severityLevel': severityLevel,
        'headerText': headerText,
        'descriptionText': descriptionText,
        'url': url,
        'activePeriods': activePeriods.map((p) => p.toJson()).toList(),
        'informedEntities': informedEntities.map((e) => e.toJson()).toList(),
      };
}

/// All active alerts for the environment plus feed freshness.
class ServiceAlerts {
  final List<ServiceAlert> alerts;
  final FeedFreshness freshness;
  const ServiceAlerts(this.alerts, this.freshness);
  Map<String, dynamic> toJson() => {
        'alerts': alerts.map((a) => a.toJson()).toList(),
        'freshness': freshness.toJson()
      };
}

const _emptyFreshness = FeedFreshness();

const _maxTripIds = 50;

/// The realtime surface: live vehicle positions, schedule deviations, and service alerts. Poll-based —
/// see the `poll*` methods (extension below) for change-detecting streams.
class SpiderRealtime {
  final Transport _transport;
  SpiderRealtime(this._transport);

  /// Live positions for up to 50 trips running on one GTFS [serviceDate] (`YYYY-MM-DD`) — pass a plan leg's or
  /// departure's `serviceDate`, the run the vehicle is on. No trip ids returns empty positions without a
  /// request; a malformed date or more than 50 ids fails with [SpiderErrorCode.badRequest] (field
  /// `serviceDate` or `tripIds`) without a request.
  Future<SpiderResult<VehiclePositions>> vehicles(
      String serviceDate, List<String> tripIds) async {
    final invalidDate = invalidServiceDate(serviceDate);
    if (invalidDate != null) return Failure(invalidDate);
    if (tripIds.isEmpty) {
      return const Success(VehiclePositions([], [], _emptyFreshness));
    }
    if (tripIds.length > _maxTripIds) return Failure(invalidInput('tripIds'));
    try {
      final json = await _transport.getJson('/realtime/v1/vehicles', _identity,
          query: {'serviceDate': serviceDate, 'tripIds': tripIds.join(',')});
      final vehicles = (json['vehicles'] as List<dynamic>? ?? const [])
          .map((v) => _mapVehicle(v as Map<String, dynamic>))
          .toList();
      return Success(VehiclePositions(
        vehicles,
        (json['missing'] as List<dynamic>? ?? const [])
            .map((e) => e as String)
            .toList(),
        _mapFreshness(json),
      ));
    } catch (e) {
      return Failure(toSpiderError(e));
    }
  }

  /// The live vehicle for a single trip run on GTFS [serviceDate] (`YYYY-MM-DD`) — pass the leg's or
  /// departure's `serviceDate`. A 404 is a normal "no vehicle currently reporting", not an error. A malformed
  /// date fails with [SpiderErrorCode.badRequest] (field `serviceDate`) without a request. [startTime] (GTFS
  /// `H:MM:SS` or `HH:MM:SS`, a [LiveVehicle.startTime] or [TripUpdate.startTime]) picks the run of a
  /// frequency-based trip the feed reports with that start time; null or empty answers the run with the earliest
  /// one.
  Future<SpiderResult<LiveVehicleUpdate>> vehicleForTrip(
      String tripId, String serviceDate,
      {String? startTime}) async {
    final invalidDate = invalidServiceDate(serviceDate);
    if (invalidDate != null) return Failure(invalidDate);
    try {
      final path =
          '/realtime/v1/vehicles/by-trip/${Uri.encodeComponent(tripId)}';
      final resp = await _transport.getRaw(path, query: {
        'serviceDate': serviceDate,
        if (startTime != null && startTime.isNotEmpty) 'startTime': startTime,
      });
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        final failure = httpFailure('GET $path', resp.statusCode, resp.body);
        // A 404 means no vehicle is reporting, unless its body names a plan-limit refusal.
        if (resp.statusCode == 404 && failure.kind == TransportErrorKind.http) {
          return const Success(LiveVehicleUpdate(null, _emptyFreshness));
        }
        throw failure;
      }
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final vehicle = json['vehicle'];
      return Success(LiveVehicleUpdate(
        vehicle == null ? null : _mapVehicle(vehicle as Map<String, dynamic>),
        _mapFreshness(json),
      ));
    } catch (e) {
      return Failure(toSpiderError(e));
    }
  }

  /// Live trip updates for up to 50 feed-prefixed [tripIds] (`<feedId>:<id>`) running on one GTFS [serviceDate]
  /// (`YYYY-MM-DD`) — pass a plan leg's, departure's or trip's `serviceDate` and its trip id through. One
  /// [TripUpdate] per trip run, so a frequency-based trip may have several, each with its
  /// [TripUpdate.startTime], and each carries the experimental [TripUpdate.modifications] (detours) that select
  /// it. The ids are de-duplicated and sorted, so equal requests share a cached response. A malformed date, no
  /// ids, a blank id or more than 50 distinct ids fails with [SpiderErrorCode.badRequest] (field `serviceDate`
  /// or `tripIds`) without a request.
  Future<SpiderResult<TripUpdates>> tripUpdates(
      String serviceDate, List<String> tripIds) async {
    final (ids, invalid) = _tripIdsQuery(serviceDate, tripIds);
    if (invalid != null) return Failure(invalid);
    try {
      final json = await _transport.getJson(
          '/realtime/v1/trip-updates', _identity,
          query: {'serviceDate': serviceDate, 'tripIds': ids.join(',')});
      return Success(TripUpdates(
        json['serviceDate'] as String,
        (json['tripUpdates'] as List<dynamic>)
            .map((u) => _mapTripUpdate(u as Map<String, dynamic>))
            .toList(),
        (json['missing'] as List<dynamic>).map((e) => e as String).toList(),
        _mapFreshness(json),
      ));
    } catch (e) {
      return Failure(toSpiderError(e));
    }
  }

  /// Live delays for up to 50 feed-prefixed [tripIds] (`<feedId>:<id>`) running on one GTFS [serviceDate]
  /// (`YYYY-MM-DD`) — pass a plan leg's, departure's or trip's `serviceDate` and its trip id through. A
  /// frequency-based trip answers its run with the earliest start time. The ids are de-duplicated and sorted,
  /// so equal requests share a cached response. A malformed date, no ids, a blank id or more than 50 distinct
  /// ids fails with [SpiderErrorCode.badRequest] (field `serviceDate` or `tripIds`) without a request.
  @Deprecated(
      'Use tripUpdates, its successor: the API retires GET /realtime/v1/delays '
      'with notice, no earlier than 2027-05-24.')
  Future<SpiderResult<TripDelays>> delays(
      String serviceDate, List<String> tripIds) async {
    final (ids, invalid) = _tripIdsQuery(serviceDate, tripIds);
    if (invalid != null) return Failure(invalid);
    try {
      final json = await _transport.getJson('/realtime/v1/delays', _identity,
          query: {'serviceDate': serviceDate, 'tripIds': ids.join(',')});
      return Success(TripDelays(
        json['serviceDate'] as String,
        (json['delays'] as List<dynamic>)
            .map((d) => _mapDelay(d as Map<String, dynamic>))
            .toList(),
        (json['missing'] as List<dynamic>).map((e) => e as String).toList(),
        _mapFreshness(json),
      ));
    } catch (e) {
      return Failure(toSpiderError(e));
    }
  }

  /// All active service alerts for the environment.
  Future<SpiderResult<ServiceAlerts>> alerts() async {
    try {
      final json = await _transport.getJson('/realtime/v1/alerts', _identity);
      final alerts = (json['alerts'] as List<dynamic>? ?? const [])
          .map((a) => _mapAlert(a as Map<String, dynamic>))
          .toList();
      return Success(ServiceAlerts(alerts, _mapFreshness(json)));
    } catch (e) {
      return Failure(toSpiderError(e));
    }
  }
}

/// Change-detecting realtime polling. Each stream calls the underlying surface on an interval and yields a
/// value only when the result changes from the previous one. Cancel the subscription to stop polling.
extension SpiderRealtimePolling on SpiderRealtime {
  Stream<SpiderResult<VehiclePositions>> pollVehicles(
          String serviceDate, List<String> tripIds, {int? intervalMs}) =>
      _poll(intervalMs, (v) => jsonEncode(v.toJson()),
          () => vehicles(serviceDate, tripIds));

  Stream<SpiderResult<LiveVehicleUpdate>> pollVehicleForTrip(
          String tripId, String serviceDate,
          {String? startTime, int? intervalMs}) =>
      _poll(intervalMs, (v) => jsonEncode(v.toJson()),
          () => vehicleForTrip(tripId, serviceDate, startTime: startTime));

  Stream<SpiderResult<TripUpdates>> pollTripUpdates(
          String serviceDate, List<String> tripIds, {int? intervalMs}) =>
      _poll(intervalMs, (v) => jsonEncode(v.toJson()),
          () => tripUpdates(serviceDate, tripIds));

  @Deprecated(
      'Use pollTripUpdates, its successor: the API retires GET /realtime/v1/delays '
      'with notice, no earlier than 2027-05-24.')
  Stream<SpiderResult<TripDelays>> pollDelays(
          String serviceDate, List<String> tripIds, {int? intervalMs}) =>
      _poll(intervalMs, (v) => jsonEncode(v.toJson()),
          () => delays(serviceDate, tripIds));

  Stream<SpiderResult<ServiceAlerts>> pollAlerts({int? intervalMs}) =>
      _poll(intervalMs, (v) => jsonEncode(v.toJson()), () => alerts());
}

Map<String, dynamic> _identity(Map<String, dynamic> json) => json;

(List<String>, SpiderError?) _tripIdsQuery(
    String serviceDate, List<String> tripIds) {
  final invalidDate = invalidServiceDate(serviceDate);
  if (invalidDate != null) return (const [], invalidDate);
  if (tripIds.isEmpty) return (const [], missingInput('tripIds'));
  if (tripIds.any((id) => id.trim().isEmpty)) {
    return (const [], invalidInput('tripIds', malformed: true));
  }
  final ids = tripIds.toSet().toList()..sort();
  if (ids.length > _maxTripIds) return (const [], invalidInput('tripIds'));
  return (ids, null);
}

Stream<SpiderResult<T>> _poll<T>(
  int? intervalMs,
  String Function(T) keyOf,
  Future<SpiderResult<T>> Function() fetch,
) async* {
  final interval = Duration(milliseconds: intervalMs ?? 15000);
  String? last;
  while (true) {
    final result = await fetch();
    final key = switch (result) {
      Success<T>(:final value) => 'ok:${keyOf(value)}',
      Failure<T>(:final error) => 'err:${error.code.name}:${error.message}',
    };
    if (key != last) {
      last = key;
      yield result;
    }
    await Future<void>.delayed(interval);
  }
}

// Wire timestamps are epoch SECONDS; public models use epoch MILLIS.
int? _secondsToMs(Object? value) => value is num ? value.toInt() * 1000 : null;

FeedFreshness _mapFreshness(Map<String, dynamic> json) => FeedFreshness(
      feedTimestampEpochMs: _secondsToMs(json['feedTimestamp']),
      staleSeconds: (json['staleSeconds'] as num?)?.toInt(),
    );

LiveVehicle _mapVehicle(Map<String, dynamic> v) => LiveVehicle(
      tripId: v['tripId'] as String,
      serviceDate: v['serviceDate'] as String,
      startTime: v['startTime'] as String?,
      routeId: v['routeId'] as String?,
      vehicleId: v['vehicleId'] as String?,
      label: v['label'] as String?,
      latitude: (v['latitude'] as num).toDouble(),
      longitude: (v['longitude'] as num).toDouble(),
      bearing: (v['bearing'] as num?)?.toDouble(),
      speed: (v['speed'] as num?)?.toDouble(),
      stopId: v['stopId'] as String?,
      currentStatus: v['currentStatus'] as String?,
      occupancy: OccupancyStatus.fromWire(v['occupancyStatus'] as String?),
      timestampEpochMs: _secondsToMs(v['timestamp']),
      wheelchairAccessible:
          _vehicleWheelchair(v['wheelchairAccessible'] as String?),
      airConditioning: v['airConditioning'] as bool?,
      wifi: v['wifi'] as bool?,
      cardPayment: v['cardPayment'] as bool?,
    );

WheelchairBoarding? _vehicleWheelchair(String? value) => switch (value) {
      null || 'UNKNOWN' => null,
      'WHEELCHAIR_ACCESSIBLE' => WheelchairBoarding.possible,
      'WHEELCHAIR_INACCESSIBLE' => WheelchairBoarding.notPossible,
      _ => WheelchairBoarding.unknown,
    };

TripUpdate _mapTripUpdate(Map<String, dynamic> u) => TripUpdate(
      tripId: u['tripId'] as String,
      startTime: u['startTime'] as String?,
      routeId: u['routeId'] as String?,
      delaySeconds: (u['delaySeconds'] as num?)?.toInt(),
      scheduleRelationship: u['scheduleRelationship'] as String?,
      stopTimeUpdates: (u['stopTimeUpdates'] as List<dynamic>)
          .map((s) => _mapStopTimeUpdate(s as Map<String, dynamic>))
          .toList(),
      modifications: (u['modifications'] as List<dynamic>? ?? const [])
          .map((m) => _mapModification(m as Map<String, dynamic>))
          .toList(),
      vehicle: _mapTripVehicle(u['vehicle']),
    );

TripVehicle? _mapTripVehicle(Object? v) => v is Map<String, dynamic>
    ? TripVehicle(
        id: v['id'] as String?,
        label: v['label'] as String?,
        wheelchairAccessible:
            _vehicleWheelchair(v['wheelchairAccessible'] as String?),
        airConditioning: v['airConditioning'] as bool?,
        wifi: v['wifi'] as bool?,
        cardPayment: v['cardPayment'] as bool?,
      )
    : null;

TripModification _mapModification(Map<String, dynamic> m) => TripModification(
      id: m['id'] as String,
      startTimes:
          (m['startTimes'] as List<dynamic>?)?.map((e) => e as String).toList(),
      startStop: _mapStopSelector(m['startStop']),
      endStop: _mapStopSelector(m['endStop']),
      replacementStops: (m['replacementStops'] as List<dynamic>? ?? const [])
          .map((s) => _mapReplacementStop(s as Map<String, dynamic>))
          .toList(),
      propagatedModificationDelaySeconds:
          (m['propagatedModificationDelay'] as num?)?.toInt() ?? 0,
      alertId: m['alertId'] as String?,
      lastModifiedEpochMs: _secondsToMs(m['lastModifiedTime']),
      shape: m['shape'] == null
          ? null
          : decodePolyline(m['shape'] as String, factor: 1e5),
    );

StopSelector? _mapStopSelector(Object? s) => s is Map<String, dynamic>
    ? StopSelector(
        stopSequence: (s['stopSequence'] as num?)?.toInt(),
        stopId: s['stopId'] as String?,
      )
    : null;

ReplacementStop _mapReplacementStop(Map<String, dynamic> s) => ReplacementStop(
      stopId: s['stopId'] as String?,
      travelTimeToStopSeconds: (s['travelTimeToStop'] as num?)?.toInt(),
      name: s['name'] as String?,
      latitude: (s['latitude'] as num?)?.toDouble(),
      longitude: (s['longitude'] as num?)?.toDouble(),
    );

TripDelay _mapDelay(Map<String, dynamic> d) => TripDelay(
      tripId: d['tripId'] as String,
      routeId: d['routeId'] as String?,
      delaySeconds: (d['delaySeconds'] as num?)?.toInt(),
      scheduleRelationship: d['scheduleRelationship'] as String?,
      stopTimeUpdates: (d['stopTimeUpdates'] as List<dynamic>)
          .map((s) => _mapStopTimeUpdate(s as Map<String, dynamic>))
          .toList(),
    );

StopTimeUpdate _mapStopTimeUpdate(Map<String, dynamic> s) => StopTimeUpdate(
      stopId: s['stopId'] as String?,
      stopSequence: (s['stopSequence'] as num?)?.toInt(),
      arrivalDelay: (s['arrivalDelay'] as num?)?.toInt(),
      departureDelay: (s['departureDelay'] as num?)?.toInt(),
      scheduleRelationship: s['scheduleRelationship'] as String?,
    );

ServiceAlert _mapAlert(Map<String, dynamic> a) => ServiceAlert(
      id: a['id'] as String,
      cause: a['cause'] as String?,
      effect: a['effect'] as String?,
      severityLevel: a['severityLevel'] as String?,
      headerText: a['headerText'] as String?,
      descriptionText: a['descriptionText'] as String?,
      url: a['url'] as String?,
      activePeriods: (a['activePeriods'] as List<dynamic>? ?? const [])
          .map((p) => AlertActivePeriod(
              _secondsToMs((p as Map<String, dynamic>)['start']),
              _secondsToMs(p['end'])))
          .toList(),
      informedEntities: (a['informedEntities'] as List<dynamic>? ?? const [])
          .map((e) => AlertInformedEntity(
                agencyId: (e as Map<String, dynamic>)['agencyId'] as String?,
                routeId: e['routeId'] as String?,
                tripId: e['tripId'] as String?,
                stopId: e['stopId'] as String?,
              ))
          .toList(),
    );
