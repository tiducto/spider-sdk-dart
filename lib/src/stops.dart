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

/// Search criteria. [name] is a free-text query; the admin fields narrow it by administrative area.
class StopFilter {
  final String? name;
  final String? country;
  final String? region;
  final String? district;
  final String? city;
  final String? suburb;
  const StopFilter(
      {this.name,
      this.country,
      this.region,
      this.district,
      this.city,
      this.suburb});
}

/// The stops surface: text + administrative-area stop search.
class SpiderStops {
  final Transport _transport;
  SpiderStops(this._transport);

  /// Searches stops by free text and/or administrative area.
  Future<SpiderResult<List<Stop>>> search(StopFilter filter) async {
    try {
      final body = <String, dynamic>{'q': filter.name ?? ''};
      final expr = _buildFilterExpression(filter);
      if (expr != null) body['filter'] = expr;
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

String? _buildFilterExpression(StopFilter filter) {
  final pairs = <MapEntry<String, String?>>[
    MapEntry('country', filter.country),
    MapEntry('region', filter.region),
    MapEntry('district', filter.district),
    MapEntry('city', filter.city),
    MapEntry('suburb', filter.suburb),
  ];
  final clauses = <String>[];
  for (final pair in pairs) {
    final value = pair.value;
    if (value == null || value.isEmpty) continue;
    clauses.add('"${_escapeFilter(pair.key)}" = "${_escapeFilter(value)}"');
  }
  return clauses.isEmpty ? null : clauses.join(' AND ');
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
