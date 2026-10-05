// The public, consumer-facing enums. They map from the raw wire strings via `fromWire`: a value this SDK
// doesn't know maps to `.unknown`, so a producer adding a value never breaks decoding. The wire's
// "no information" values (`NO_INFORMATION`, `NO_DATA_AVAILABLE`) map to null, like an absent value.

/// A transit or street mode. Unrecognized values map to [TransitMode.unknown].
enum TransitMode {
  airplane('AIRPLANE'),
  bicycle('BICYCLE'),
  bus('BUS'),
  cableCar('CABLE_CAR'),
  car('CAR'),
  carpool('CARPOOL'),
  coach('COACH'),
  ferry('FERRY'),
  flex('FLEX'),
  flexible('FLEXIBLE'),
  funicular('FUNICULAR'),
  gondola('GONDOLA'),
  legSwitch('LEG_SWITCH'),
  monorail('MONORAIL'),
  rail('RAIL'),
  scooter('SCOOTER'),
  snowAndIce('SNOW_AND_ICE'),
  subway('SUBWAY'),
  taxi('TAXI'),
  tram('TRAM'),
  transit('TRANSIT'),
  trolleybus('TROLLEYBUS'),
  walk('WALK'),
  unknown('UNKNOWN');

  const TransitMode(this.wire);
  final String wire;

  static TransitMode? fromWire(String? value) {
    if (value == null) return null;
    for (final e in values) {
      if (e.wire == value) return e;
    }
    return TransitMode.unknown;
  }
}

/// Whether a wheelchair user can board: at a stop, or on a trip's vehicle. Unrecognized values map to
/// [WheelchairBoarding.unknown]; `NO_INFORMATION` maps to null.
enum WheelchairBoarding {
  possible('POSSIBLE'),
  notPossible('NOT_POSSIBLE'),
  unknown('UNKNOWN');

  const WheelchairBoarding(this.wire);
  final String wire;

  static WheelchairBoarding? fromWire(String? value) {
    if (value == null || value == 'NO_INFORMATION') return null;
    for (final e in values) {
      if (e.wire == value) return e;
    }
    return WheelchairBoarding.unknown;
  }
}

/// Whether bikes are allowed on a trip. Unrecognized values map to [BikesAllowed.unknown];
/// `NO_INFORMATION` maps to null.
enum BikesAllowed {
  allowed('ALLOWED'),
  notAllowed('NOT_ALLOWED'),
  unknown('UNKNOWN');

  const BikesAllowed(this.wire);
  final String wire;

  static BikesAllowed? fromWire(String? value) {
    if (value == null || value == 'NO_INFORMATION') return null;
    for (final e in values) {
      if (e.wire == value) return e;
    }
    return BikesAllowed.unknown;
  }
}

/// GTFS-RT vehicle occupancy. Unrecognized values map to [OccupancyStatus.unknown]; `NO_DATA_AVAILABLE` maps
/// to null.
enum OccupancyStatus {
  empty('EMPTY'),
  manySeatsAvailable('MANY_SEATS_AVAILABLE'),
  fewSeatsAvailable('FEW_SEATS_AVAILABLE'),
  standingRoomOnly('STANDING_ROOM_ONLY'),
  crushedStandingRoomOnly('CRUSHED_STANDING_ROOM_ONLY'),
  full('FULL'),
  notAcceptingPassengers('NOT_ACCEPTING_PASSENGERS'),
  notBoardable('NOT_BOARDABLE'),
  unknown('UNKNOWN');

  const OccupancyStatus(this.wire);
  final String wire;

  static OccupancyStatus? fromWire(String? value) {
    if (value == null || value == 'NO_DATA_AVAILABLE') return null;
    for (final e in values) {
      if (e.wire == value) return e;
    }
    return OccupancyStatus.unknown;
  }
}

/// The realtime state of a departure/leg. Unrecognized values map to [RealtimeState.unknown].
enum RealtimeState {
  added('ADDED'),
  canceled('CANCELED'),
  modified('MODIFIED'),
  scheduled('SCHEDULED'),
  updated('UPDATED'),
  unknown('UNKNOWN');

  const RealtimeState(this.wire);
  final String wire;

  static RealtimeState? fromWire(String? value) {
    if (value == null) return null;
    for (final e in values) {
      if (e.wire == value) return e;
    }
    return RealtimeState.unknown;
  }
}

/// Why routing failed. Unrecognized values map to [RoutingErrorCode.unknown].
enum RoutingErrorCode {
  locationNotFound('LOCATION_NOT_FOUND'),
  noStopsInRange('NO_STOPS_IN_RANGE'),
  noTransitConnection('NO_TRANSIT_CONNECTION'),
  noTransitConnectionInSearchWindow('NO_TRANSIT_CONNECTION_IN_SEARCH_WINDOW'),
  outsideBounds('OUTSIDE_BOUNDS'),
  outsideServicePeriod('OUTSIDE_SERVICE_PERIOD'),
  walkingBetterThanTransit('WALKING_BETTER_THAN_TRANSIT'),
  unknown('UNKNOWN');

  const RoutingErrorCode(this.wire);
  final String wire;

  static RoutingErrorCode fromWire(String? value) {
    if (value == null) return RoutingErrorCode.unknown;
    for (final e in values) {
      if (e.wire == value) return e;
    }
    return RoutingErrorCode.unknown;
  }
}

/// Which input a routing error refers to. Unrecognized values map to [InputField.unknown].
enum InputField {
  /// The requested departure or arrival time.
  dateTime('DATE_TIME'),

  /// The origin, e.g. an unknown origin stop id ([RoutingErrorCode.locationNotFound]).
  from('FROM'),

  /// The destination, e.g. an unknown destination stop id ([RoutingErrorCode.locationNotFound]).
  to('TO'),

  /// A via location, e.g. an unknown via stop id ([RoutingErrorCode.locationNotFound]).
  via('VIA'),
  unknown('UNKNOWN');

  const InputField(this.wire);
  final String wire;

  static InputField? fromWire(String? value) {
    if (value == null) return null;
    for (final e in values) {
      if (e.wire == value) return e;
    }
    return InputField.unknown;
  }
}

/// How much typical delay a plan budgets for at each arrival: [standard] the median (p50), [safe] the 70th
/// percentile, [verySafe] the 90th.
enum Reliability {
  standard('STANDARD'),
  safe('SAFE'),
  verySafe('VERY_SAFE');

  const Reliability(this.wire);
  final String wire;
}
