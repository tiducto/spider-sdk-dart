import 'errors.dart';
import 'result.dart';
import 'stops.dart' show GeoPoint;
import 'transport.dart';

/// What a [PlaceHit] is.
enum PlaceType {
  /// A transit stop; its [PlaceHit.id] is the feed-prefixed stop id routing takes.
  stop('stop'),

  /// A single address. Listed when the query holds a house number.
  address('address'),

  /// A street, standing for its addresses when the query holds no house number.
  street('street'),

  /// A municipality.
  place('place'),

  /// A point of interest.
  poi('poi'),

  /// A type this SDK doesn't know yet; new types may be added to the API.
  unknown('unknown');

  const PlaceType(this.wire);
  final String wire;

  static PlaceType fromWire(String value) {
    for (final e in values) {
      if (e != unknown && e.wire == value) return e;
    }
    return unknown;
  }
}

/// One place search hit: a stop, an address, a street, a municipality or a point of interest. Every hit carries
/// the same administrative labels a [Stop] does, so hits of different types are labelled alike.
class PlaceHit {
  /// For a [PlaceType.stop], the stop's feed-prefixed id (`<feedId>:<id>`), usable wherever routing takes a stop
  /// id. For any other type, an opaque id, stable across searches.
  final String id;
  final PlaceType type;

  /// Display name; a stop's is the operator's own.
  final String name;
  final double lat;
  final double lon;

  /// What kind of place it is, e.g. `university` or `hospital` for a point of interest, `municipality` for a
  /// municipality, `building` for an address, `street` for a street. Null for a stop. New values may be added.
  final String? category;
  final String? country;
  final String? region;
  final String? district;
  final String? city;
  final String? suburb;

  /// Metres from the location passed to [SpiderPlaces.search]; null when no location was passed.
  final int? distance;

  const PlaceHit({
    required this.id,
    required this.type,
    required this.name,
    required this.lat,
    required this.lon,
    this.category,
    this.country,
    this.region,
    this.district,
    this.city,
    this.suburb,
    this.distance,
  });
}

const _defaultLimit = 10;
const _maxLimit = 20;

/// The places surface: one search over the environment's service area across stops, addresses, streets,
/// municipalities and points of interest.
class SpiderPlaces {
  final Transport _transport;
  SpiderPlaces(this._transport);

  /// Searches places by free text, best match first. [query] is 2 to 100 characters after trimming; abbreviated
  /// and spelled-out forms find each other, and text without diacritics matches text with them. A query with a
  /// house number (`Údolní 53`) lists individual addresses; without one, a street stands for its addresses.
  ///
  /// With [near], the nearer of two equally good matches comes first and every hit carries
  /// [PlaceHit.distance].
  ///
  /// [limit] is the most hits to return, 1–20 (default 10). Outside that range the search fails with
  /// [SpiderErrorCode.badRequest] (field `limit`) without a request.
  Future<SpiderResult<List<PlaceHit>>> search(String query,
      {GeoPoint? near, int limit = _defaultLimit}) async {
    if (limit < 1 || limit > _maxLimit) {
      return Failure(invalidInput('limit'));
    }
    try {
      final hits = await _transport.getJson(
        '/places/v1/search',
        _parseSearchResponse,
        query: {
          'q': query,
          'limit': '$limit',
          if (near != null) 'latitude': '${near.lat}',
          if (near != null) 'longitude': '${near.lng}',
        },
      );
      return Success(hits);
    } catch (e) {
      return Failure(toSpiderError(e));
    }
  }
}

List<PlaceHit> _parseSearchResponse(Map<String, dynamic> json) {
  try {
    return (json['hits'] as List<dynamic>)
        .map((h) => _toPlaceHit(h as Map<String, dynamic>))
        .toList();
  } catch (e) {
    throw SpiderDecodingError('failed to decode GET /places/v1/search', e);
  }
}

PlaceHit _toPlaceHit(Map<String, dynamic> hit) => PlaceHit(
      id: hit['id'] as String,
      type: PlaceType.fromWire(hit['type'] as String),
      name: hit['name'] as String,
      lat: (hit['lat'] as num).toDouble(),
      lon: (hit['lon'] as num).toDouble(),
      category: hit['category'] as String?,
      country: hit['country'] as String?,
      region: hit['region'] as String?,
      district: hit['district'] as String?,
      city: hit['city'] as String?,
      suburb: hit['suburb'] as String?,
      distance: (hit['distance'] as num?)?.toInt(),
    );
