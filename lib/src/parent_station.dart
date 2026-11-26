/// The station a stop belongs to (GTFS `parent_station`, a `location_type` 1 stop): the parent of a
/// [Leg]'s boarding or alighting stop, a [TripStop] or the stop of [StopDepartures]. Its [gtfsId] is a
/// station id that [Location.stop] and [SpiderRouting.departures] accept, for all the station's stops.
class ParentStation {
  /// The station's feed-prefixed id (`<feedId>:<id>`).
  final String gtfsId;

  /// The station's name, as the feed gives it.
  final String name;
  const ParentStation({required this.gtfsId, required this.name});

  @override
  bool operator ==(Object other) =>
      other is ParentStation && other.gtfsId == gtfsId && other.name == name;

  @override
  int get hashCode => Object.hash(gtfsId, name);

  @override
  String toString() => 'ParentStation($gtfsId, $name)';
}
