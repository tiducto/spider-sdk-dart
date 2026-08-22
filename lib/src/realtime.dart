import 'dart:convert';
import 'enums.dart';
import 'errors.dart';
import 'result.dart';
import 'transport.dart';

// MARK: public realtime models (toJson is used by the poll* streams to de-duplicate consecutive results)

/// How fresh a realtime feed is. Timestamps are epoch milliseconds; `staleSeconds` is age in seconds.
class FeedFreshness {
  final int? feedTimestampEpochMs;
  final double? staleSeconds;
  const FeedFreshness({this.feedTimestampEpochMs, this.staleSeconds});
  Map<String, dynamic> toJson() => {
        'feedTimestampEpochMs': feedTimestampEpochMs,
        'staleSeconds': staleSeconds
      };
}

/// A vehicle's live position. GTFS-RT producers populate wildly different subsets, so every field is optional.
class LiveVehicle {
  final String? tripId;
  final String? routeId;
  final String? vehicleId;
  final String? label;
  final double? latitude;
  final double? longitude;
  final double? bearing;
  final double? speed;
  final String? stopId;
  final String? currentStatus;
  final OccupancyStatus? occupancy;
  final int? timestampEpochMs;
  const LiveVehicle({
    this.tripId,
    this.routeId,
    this.vehicleId,
    this.label,
    this.latitude,
    this.longitude,
    this.bearing,
    this.speed,
    this.stopId,
    this.currentStatus,
    this.occupancy,
    this.timestampEpochMs,
  });
  Map<String, dynamic> toJson() => {
        'tripId': tripId,
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

/// A trip's live schedule deviation. Delay values are in seconds.
class TripDelay {
  final String? tripId;
  final String? routeId;
  final int? delaySeconds;
  final String? scheduleRelationship;
  final List<StopTimeUpdate> stopTimeUpdates;
  const TripDelay(
      {this.tripId,
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

/// Live deviations for a set of trips, plus the trip ids with no live delay.
class TripDelays {
  final List<TripDelay> delays;
  final List<String> missing;
  final FeedFreshness freshness;
  const TripDelays(this.delays, this.missing, this.freshness);
  Map<String, dynamic> toJson() => {
        'delays': delays.map((d) => d.toJson()).toList(),
        'missing': missing,
        'freshness': freshness.toJson()
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
  final String? id;
  final String? cause;
  final String? effect;
  final String? severityLevel;
  final String? headerText;
  final String? descriptionText;
  final String? url;
  final List<AlertActivePeriod> activePeriods;
  final List<AlertInformedEntity> informedEntities;
  const ServiceAlert({
    this.id,
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
const _emptyPositions = VehiclePositions([], [], _emptyFreshness);
const _emptyDelays = TripDelays([], [], _emptyFreshness);

/// The realtime surface: live vehicle positions, schedule deviations, and service alerts. Poll-based —
/// see the `poll*` methods (extension below) for change-detecting streams.
class SpiderRealtime {
  final Transport _transport;
  SpiderRealtime(this._transport);

  /// Live positions for the given trips. An empty input returns an empty result without a request.
  Future<SpiderResult<VehiclePositions>> vehicles(List<String> tripIds) async {
    if (tripIds.isEmpty) return const Success(_emptyPositions);
    try {
      final json = await _transport.getJson('/realtime/vehicles', _identity,
          query: {'tripIds': tripIds.join(',')});
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
    } on SpiderContractMismatchError {
      rethrow;
    } catch (e) {
      return Failure(toSpiderError(e));
    }
  }

  /// The live vehicle for a single trip. A 404 is a normal "no vehicle currently reporting", not an error.
  Future<SpiderResult<LiveVehicleUpdate>> vehicleForTrip(String tripId) async {
    try {
      final path = '/realtime/vehicles/by-trip/${Uri.encodeComponent(tripId)}';
      final resp = await _transport.getRaw(path);
      if (resp.statusCode == 404) {
        return const Success(LiveVehicleUpdate(null, _emptyFreshness));
      }
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        final detail =
            resp.body.length > 300 ? resp.body.substring(0, 300) : resp.body;
        throw TransportError(
            TransportErrorKind.http, 'GET $path -> ${resp.statusCode}: $detail',
            httpStatus: resp.statusCode);
      }
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final vehicle = json['vehicle'];
      return Success(LiveVehicleUpdate(
        vehicle == null ? null : _mapVehicle(vehicle as Map<String, dynamic>),
        _mapFreshness(json),
      ));
    } on SpiderContractMismatchError {
      rethrow;
    } catch (e) {
      return Failure(toSpiderError(e));
    }
  }

  /// Live schedule deviation for the given trips. An empty input returns an empty result without a request.
  Future<SpiderResult<TripDelays>> delays(List<String> tripIds) async {
    if (tripIds.isEmpty) return const Success(_emptyDelays);
    try {
      final json = await _transport.getJson('/realtime/delays', _identity,
          query: {'tripIds': tripIds.join(',')});
      final delays = (json['delays'] as List<dynamic>? ?? const [])
          .map((d) => _mapDelay(d as Map<String, dynamic>))
          .toList();
      return Success(TripDelays(
        delays,
        (json['missing'] as List<dynamic>? ?? const [])
            .map((e) => e as String)
            .toList(),
        _mapFreshness(json),
      ));
    } on SpiderContractMismatchError {
      rethrow;
    } catch (e) {
      return Failure(toSpiderError(e));
    }
  }

  /// All active service alerts for the environment.
  Future<SpiderResult<ServiceAlerts>> alerts() async {
    try {
      final json = await _transport.getJson('/realtime/alerts', _identity);
      final alerts = (json['alerts'] as List<dynamic>? ?? const [])
          .map((a) => _mapAlert(a as Map<String, dynamic>))
          .toList();
      return Success(ServiceAlerts(alerts, _mapFreshness(json)));
    } on SpiderContractMismatchError {
      rethrow;
    } catch (e) {
      return Failure(toSpiderError(e));
    }
  }
}

/// Change-detecting realtime polling. Each stream calls the underlying surface on an interval and yields a
/// value only when the result changes from the previous one. Cancel the subscription to stop polling.
extension SpiderRealtimePolling on SpiderRealtime {
  Stream<SpiderResult<VehiclePositions>> pollVehicles(List<String> tripIds,
          {int? intervalMs}) =>
      _poll(intervalMs, (v) => jsonEncode(v.toJson()), () => vehicles(tripIds));

  Stream<SpiderResult<LiveVehicleUpdate>> pollVehicleForTrip(String tripId,
          {int? intervalMs}) =>
      _poll(intervalMs, (v) => jsonEncode(v.toJson()),
          () => vehicleForTrip(tripId));

  Stream<SpiderResult<TripDelays>> pollDelays(List<String> tripIds,
          {int? intervalMs}) =>
      _poll(intervalMs, (v) => jsonEncode(v.toJson()), () => delays(tripIds));

  Stream<SpiderResult<ServiceAlerts>> pollAlerts({int? intervalMs}) =>
      _poll(intervalMs, (v) => jsonEncode(v.toJson()), () => alerts());
}

Map<String, dynamic> _identity(Map<String, dynamic> json) => json;

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
      staleSeconds: (json['staleSeconds'] as num?)?.toDouble(),
    );

LiveVehicle _mapVehicle(Map<String, dynamic> v) => LiveVehicle(
      tripId: v['tripId'] as String?,
      routeId: v['routeId'] as String?,
      vehicleId: v['vehicleId'] as String?,
      label: v['label'] as String?,
      latitude: (v['latitude'] as num?)?.toDouble(),
      longitude: (v['longitude'] as num?)?.toDouble(),
      bearing: (v['bearing'] as num?)?.toDouble(),
      speed: (v['speed'] as num?)?.toDouble(),
      stopId: v['stopId'] as String?,
      currentStatus: v['currentStatus'] as String?,
      occupancy: OccupancyStatus.fromWire(v['occupancyStatus'] as String?),
      timestampEpochMs: _secondsToMs(v['timestamp']),
    );

TripDelay _mapDelay(Map<String, dynamic> d) => TripDelay(
      tripId: d['tripId'] as String?,
      routeId: d['routeId'] as String?,
      delaySeconds: (d['delaySeconds'] as num?)?.toInt(),
      scheduleRelationship: d['scheduleRelationship'] as String?,
      stopTimeUpdates: (d['stopTimeUpdates'] as List<dynamic>? ?? const [])
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
      id: a['id'] as String?,
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
