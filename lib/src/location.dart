/// An origin, destination, or via point: either a coordinate or a stop id.
sealed class Location {
  const Location();

  /// A geographic coordinate.
  const factory Location.coordinate(double latitude, double longitude) =
      CoordinateLocation;

  /// A stop by its GTFS id.
  const factory Location.stop(String id) = StopLocation;
}

final class CoordinateLocation extends Location {
  final double latitude;
  final double longitude;
  const CoordinateLocation(this.latitude, this.longitude);
}

final class StopLocation extends Location {
  final String id;
  const StopLocation(this.id);
}

/// A via constraint on a trip plan: pass through a set of stops, or visit a place with a minimum dwell.
sealed class ViaLocation {
  const ViaLocation();

  /// Require the route to pass through any of the given stops (no dwell).
  const factory ViaLocation.passThrough(List<String> stopIds) = PassThroughVia;

  /// Require the route to visit a place, optionally dwelling at least [minimumWaitSeconds] there.
  const factory ViaLocation.visit(Location location, {int minimumWaitSeconds}) =
      VisitVia;
}

final class PassThroughVia extends ViaLocation {
  final List<String> stopIds;
  const PassThroughVia(this.stopIds);
}

final class VisitVia extends ViaLocation {
  final Location location;
  final int minimumWaitSeconds;
  const VisitVia(this.location, {this.minimumWaitSeconds = 0});
}
