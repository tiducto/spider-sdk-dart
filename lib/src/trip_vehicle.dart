import 'enums.dart';

/// The vehicle running a trip run, with its features: the same vehicle on a [TripUpdate], a [Leg], a
/// [Departure] and a [TripDetails]. Every member is null when the feed doesn't report it.
/// [wheelchairAccessible] is the vehicle's realtime access, separate from a trip's timetable
/// `wheelchairAccessible`.
class TripVehicle {
  /// The vehicle's id, feed-prefixed (`<feedId>:<id>`) as [LiveVehicle.vehicleId], so it names the same
  /// vehicle there.
  final String? id;

  /// The vehicle's user-visible label, as the producer gives it.
  final String? label;

  /// Whether a wheelchair user can board the vehicle, from GTFS-RT `VehicleDescriptor.wheelchair_accessible`;
  /// null when the feed gives no value or `UNKNOWN`.
  final WheelchairBoarding? wheelchairAccessible;

  /// Whether the vehicle is air-conditioned; null when unknown.
  final bool? airConditioning;

  /// Whether the vehicle offers Wi-Fi; null when unknown.
  final bool? wifi;

  /// Whether the vehicle accepts card payment on board; null when unknown.
  final bool? cardPayment;
  const TripVehicle({
    this.id,
    this.label,
    this.wheelchairAccessible,
    this.airConditioning,
    this.wifi,
    this.cardPayment,
  });
  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'wheelchairAccessible': wheelchairAccessible?.wire,
        'airConditioning': airConditioning,
        'wifi': wifi,
        'cardPayment': cardPayment,
      };
}
