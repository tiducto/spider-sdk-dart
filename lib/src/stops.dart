import 'dart:convert';
import 'errors.dart';
import 'result.dart';
import 'transport.dart';

/// A stop returned by search.
class Stop {
  final String gtfsId;
  final String name;
  final double? lat;
  final double? lon;
  final String? country;
  final String? region;
  final String? district;
  final String? city;
  final String? suburb;
  const Stop({
    required this.gtfsId,
    required this.name,
    this.lat,
    this.lon,
    this.country,
    this.region,
    this.district,
    this.city,
    this.suburb,
  });
}

/// A WGS84 point. `lng` mirrors the transit-industry `lon`, but the input side reads as lat/lng.
class GeoPoint {
  final double lat;
  final double lng;
  const GeoPoint(this.lat, this.lng);
}

/// A WGS84 bounding box: south-west corner (`min*`) to north-east corner (`max*`).
class GeoBoundingBox {
  final double minLat;
  final double minLng;
  final double maxLat;
  final double maxLng;
  const GeoBoundingBox({
    required this.minLat,
    required this.minLng,
    required this.maxLat,
    required this.maxLng,
  });
}

/// Search criteria. [name] is a free-text query; the admin fields narrow it by administrative area; the geo
/// fields ([near]/[radiusMeters]/[bbox]/[sortByDistance]) constrain and order it spatially.
class StopFilter {
  final String? name;
  final String? country;
  final String? region;
  final String? district;
  final String? city;
  final String? suburb;

  /// Geographic anchor for [radiusMeters] and [sortByDistance].
  final GeoPoint? near;

  /// Restrict to stops within this many metres of [near]. Requires [near].
  final int? radiusMeters;

  /// Restrict to stops inside this box. Independent of [near].
  final GeoBoundingBox? bbox;

  /// Sort results by distance from [near], nearest first. Requires [near].
  final bool? sortByDistance;

  /// Cap on the number of hits returned.
  final int? limit;

  const StopFilter({
    this.name,
    this.country,
    this.region,
    this.district,
    this.city,
    this.suburb,
    this.near,
    this.radiusMeters,
    this.bbox,
    this.sortByDistance,
    this.limit,
  });
}

/// The stops surface: text + administrative-area + geographic stop search, and single-stop lookup.
class SpiderStops {
  final Transport _transport;
  SpiderStops(this._transport);

  /// Searches stops by free text, administrative area, and/or geography.
  Future<SpiderResult<List<Stop>>> search(StopFilter filter) async {
    // Build + validate before the try so misuse (radius/sort without `near`) surfaces as a thrown
    // ArgumentError rather than being folded into a Failure — mirrors the Kotlin/TS surfaces.
    final body = _buildSearchRequest(filter);
    try {
      final stops = await _transport.postJson(
          '/stops/search', body, _parseSearchResponse,
          errorMessage: _extractStopError);
      return Success(stops);
    } on SpiderContractMismatchError {
      rethrow;
    } catch (e) {
      return Failure(toSpiderError(e));
    }
  }

  /// Look up a single stop by its opaque, feed-prefixed [gtfsId] (e.g. `"1:39822"`). Returns the hit, or
  /// `null` when no stop carries that id. Transport failures surface as [Failure].
  Future<SpiderResult<Stop?>> byId(String gtfsId) async {
    try {
      final body = <String, dynamic>{
        'q': '',
        'filter': 'gtfsId = "${_escapeFilter(gtfsId)}"',
        'limit': 1,
      };
      final stops = await _transport.postJson(
          '/stops/search', body, _parseSearchResponse,
          errorMessage: _extractStopError);
      return Success(stops.isEmpty ? null : stops.first);
    } on SpiderContractMismatchError {
      rethrow;
    } catch (e) {
      return Failure(toSpiderError(e));
    }
  }

  /// Stops nearest ([lat], [lng]), closest first. With [radiusMeters] the search is capped to that radius;
  /// without it, the nearest [limit] stops overall are returned. Convenience over a `near` + `sortByDistance`
  /// [search].
  Future<SpiderResult<List<Stop>>> near(double lat, double lng,
          {int? radiusMeters, int? limit}) =>
      search(StopFilter(
        near: GeoPoint(lat, lng),
        radiusMeters: radiusMeters,
        sortByDistance: true,
        limit: limit,
      ));

  /// Stops inside the axis-aligned bounding box defined by its south-west (min) and north-east (max)
  /// corners. Convenience over `search(StopFilter(bbox: ...))`.
  Future<SpiderResult<List<Stop>>> within(
          double minLat, double minLng, double maxLat, double maxLng,
          {int? limit}) =>
      search(StopFilter(
        bbox: GeoBoundingBox(
            minLat: minLat, minLng: minLng, maxLat: maxLat, maxLng: maxLng),
        limit: limit,
      ));
}

Map<String, dynamic> _buildSearchRequest(StopFilter filter) {
  if (filter.radiusMeters != null && filter.near == null) {
    throw ArgumentError('stops.search: `radiusMeters` requires `near`');
  }
  if (filter.sortByDistance == true && filter.near == null) {
    throw ArgumentError('stops.search: `sortByDistance` requires `near`');
  }
  final body = <String, dynamic>{'q': filter.name ?? ''};
  final expr = _buildFilterExpression(filter);
  if (expr != null) body['filter'] = expr;
  final sort = _buildSort(filter);
  if (sort != null) body['sort'] = sort;
  if (filter.limit != null) body['limit'] = filter.limit;
  return body;
}

List<Stop> _parseSearchResponse(Map<String, dynamic> json) {
  final hits = json['hits'] as List<dynamic>? ?? const [];
  return hits.map((h) => _toStop(h as Map<String, dynamic>)).toList();
}

Stop _toStop(Map<String, dynamic> hit) => Stop(
      gtfsId: hit['gtfsId'] as String,
      name: hit['name'] as String,
      lat: (hit['lat'] as num?)?.toDouble(),
      lon: (hit['lon'] as num?)?.toDouble(),
      country: hit['country'] as String?,
      region: hit['region'] as String?,
      district: hit['district'] as String?,
      city: hit['city'] as String?,
      suburb: hit['suburb'] as String?,
    );

// Composes the Meilisearch filter expression: `city = "…" AND gtfsId = "…" AND _geoRadius(…) AND …`.
// Attribute names are bare identifiers (Meili doesn't quote them); only string values are double-quoted,
// with embedded `"`/`\` escaped so a value can't break out of its clause. Coordinates are interpolated via
// Dart's Locale-invariant `double.toString` ('.' decimal) — never a Locale formatter that could emit a comma
// and corrupt the geo call.
String? _buildFilterExpression(StopFilter filter) {
  final clauses = <String>[];
  final admin = <MapEntry<String, String?>>[
    MapEntry('country', filter.country),
    MapEntry('region', filter.region),
    MapEntry('district', filter.district),
    MapEntry('city', filter.city),
    MapEntry('suburb', filter.suburb),
  ];
  for (final pair in admin) {
    final value = pair.value;
    if (value == null || value.isEmpty) continue;
    clauses.add('${pair.key} = "${_escapeFilter(value)}"');
  }
  final near = filter.near;
  if (near != null && filter.radiusMeters != null) {
    clauses.add('_geoRadius(${near.lat}, ${near.lng}, ${filter.radiusMeters})');
  }
  final bbox = filter.bbox;
  if (bbox != null) {
    clauses.add(
        '_geoBoundingBox([${bbox.maxLat}, ${bbox.maxLng}], [${bbox.minLat}, ${bbox.minLng}])');
  }
  return clauses.isEmpty ? null : clauses.join(' AND ');
}

// Nearest-first ordering. Requires an anchor point; without one, sortByDistance is rejected before we get
// here, so a null anchor simply means "no sort".
List<String>? _buildSort(StopFilter filter) {
  final near = filter.near;
  if (filter.sortByDistance == true && near != null) {
    return ['_geoPoint(${near.lat}, ${near.lng}):asc'];
  }
  return null;
}

// Escape backslashes then double-quotes (order matters) for a Meilisearch filter literal.
String _escapeFilter(String value) =>
    value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');

String _extractStopError(String text) {
  try {
    final obj = jsonDecode(text);
    if (obj is Map<String, dynamic> && obj['message'] is String) {
      return obj['message'] as String;
    }
  } catch (_) {
    // fall through
  }
  return text.length > 300 ? text.substring(0, 300) : text;
}
