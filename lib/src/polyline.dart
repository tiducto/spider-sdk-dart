/// A decoded geographic point.
class LatLon {
  final double lat;
  final double lon;
  const LatLon(this.lat, this.lon);

  @override
  bool operator ==(Object other) =>
      other is LatLon && other.lat == lat && other.lon == lon;

  @override
  int get hashCode => Object.hash(lat, lon);

  Map<String, dynamic> toJson() => {'lat': lat, 'lon': lon};
}

/// Decodes a Google-encoded polyline (precision 1e5) into points. Truncation-tolerant: a string that ends
/// mid-group returns the points decoded so far rather than throwing.
List<LatLon> decodePolyline(String encoded) {
  final points = <LatLon>[];
  final length = encoded.length;
  var index = 0;
  var lat = 0;
  var lon = 0;

  int? nextDelta() {
    var result = 0;
    var shift = 0;
    int byte;
    do {
      if (index >= length) return null;
      byte = encoded.codeUnitAt(index) - 63;
      index++;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    return (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
  }

  while (index < length) {
    final dLat = nextDelta();
    if (dLat == null) break;
    lat += dLat;
    final dLon = nextDelta();
    if (dLon == null) break;
    lon += dLon;
    points.add(LatLon(lat / 1e5, lon / 1e5));
  }
  return points;
}
