// The public, consumer-facing enums. They map from the raw wire strings via `fromWire`. Two kinds:
//  - OPEN (TransitMode, OccupancyStatus, RealtimeState, RoutingErrorCode, InputField): an unrecognized wire
//    value maps to `.unknown` so a producer adding a value never breaks decoding.
//  - CLOSED (WheelchairBoarding, BikesAllowed): only known values map; anything else maps to null.

/// A transit or street mode. Open: unrecognized values map to [TransitMode.unknown].
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

/// Whether a stop is wheelchair accessible. Closed: unknown wire values map to null.
enum WheelchairBoarding {
  possible('POSSIBLE'),
  notPossible('NOT_POSSIBLE');

  const WheelchairBoarding(this.wire);
  final String wire;

  static WheelchairBoarding? fromWire(String? value) => switch (value) {
        'POSSIBLE' => WheelchairBoarding.possible,
        'NOT_POSSIBLE' => WheelchairBoarding.notPossible,
        _ => null,
      };
}

/// Whether bikes are allowed on a trip. Closed: unknown wire values map to null.
enum BikesAllowed {
  allowed('ALLOWED'),
  notAllowed('NOT_ALLOWED');

  const BikesAllowed(this.wire);
  final String wire;

  static BikesAllowed? fromWire(String? value) => switch (value) {
        'ALLOWED' => BikesAllowed.allowed,
        'NOT_ALLOWED' => BikesAllowed.notAllowed,
        _ => null,
      };
}

/// GTFS-RT vehicle occupancy. Open: unrecognized values map to [OccupancyStatus.unknown]; `NO_DATA_AVAILABLE`
/// maps to null.
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

/// The realtime state of a departure/leg. Open: unrecognized values map to [RealtimeState.unknown].
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

/// Why routing failed. Open: unrecognized values map to [RoutingErrorCode.unknown].
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

/// Which input a routing error refers to. Open: unrecognized values map to [InputField.unknown].
enum InputField {
  dateTime('DATE_TIME'),
  from('FROM'),
  to('TO'),
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
