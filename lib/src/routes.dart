import 'dart:convert';
import 'errors.dart';
import 'result.dart';
import 'transport.dart';

/// Coarse transit-mode bucket for a [TransitRoute], derived from its GTFS `route_type`.
///
/// A closed vocabulary the `routes_env_{envId}` index stamps on each document so callers can filter and
/// badge routes without decoding raw `route_type` numbers. Open in the decoding direction: an unrecognized
/// wire value maps to [RouteMode.other] so a new backend value never breaks decoding.
enum RouteMode {
  bus('BUS'),
  tram('TRAM'),
  rail('RAIL'),
  subway('SUBWAY'),
  ferry('FERRY'),
  trolleybus('TROLLEYBUS'),
  aerial('AERIAL'),
  funicular('FUNICULAR'),
  cableTram('CABLE_TRAM'),
  monorail('MONORAIL'),
  other('OTHER');

  const RouteMode(this.wire);
  final String wire;

  /// Unknown/absent bucket strings collapse to [other] so a new backend value never breaks decoding.
  static RouteMode fromWire(String? value) {
    for (final e in values) {
      if (e.wire == value) return e;
    }
    return RouteMode.other;
  }
}

/// A transit route (a GTFS "route" — a named line such as tram 4 or bus 25), as indexed for search.
///
/// Named [TransitRoute] rather than `Route` because the routing surface already owns a public `Route`
/// (the result of a trip-plan); the two are unrelated and must not collide.
class TransitRoute {
  final String routeId;
  final String? shortName;
  final String? longName;
  final RouteMode mode;
  final int routeType;
  final String? agencyName;
  final int tripCount;
  const TransitRoute({
    required this.routeId,
    this.shortName,
    this.longName,
    required this.mode,
    required this.routeType,
    this.agencyName,
    required this.tripCount,
  });
}

/// Search criteria for [SpiderRoutes.search]. [query] is a free-text match against the route's short and
/// long names; [mode] and [agency] narrow it server-side.
class RouteFilter {
  /// Free-text query, matched against the route's short and long names.
  final String? query;

  /// Restrict results to a single [RouteMode].
  final RouteMode? mode;

  /// Restrict results to routes operated by this agency (exact match on the indexed agency name).
  final String? agency;

  /// Cap on the number of hits returned.
  final int? limit;

  const RouteFilter({this.query, this.mode, this.agency, this.limit});
}

/// The routes surface: route text/attribute search and single-route lookup.
class SpiderRoutes {
  final Transport _transport;
  SpiderRoutes(this._transport);

  /// Searches routes by free text, mode, and/or agency. Hits come back busiest-first (ranked by trip
  /// count), so the most-used routes lead without an explicit sort.
  Future<SpiderResult<List<TransitRoute>>> search(RouteFilter filter) async {
    final body = _buildSearchRequest(filter);
    try {
      final routes = await _transport.postJson(
          '/routes/search', body, _parseSearchResponse,
          errorMessage: _extractRouteError);
      return Success(routes);
    } on SpiderContractMismatchError {
      rethrow;
    } catch (e) {
      return Failure(toSpiderError(e));
    }
  }

  /// Look up a single route by its opaque, feed-prefixed [routeId] (e.g. `"1:L4"`). Returns the hit, or
  /// `null` when no route carries that id. Transport failures surface as [Failure].
  Future<SpiderResult<TransitRoute?>> byId(String routeId) async {
    try {
      final body = <String, dynamic>{
        'q': '',
        'filter': 'routeId = "${_escapeFilter(routeId)}"',
        'limit': 1,
      };
      final routes = await _transport.postJson(
          '/routes/search', body, _parseSearchResponse,
          errorMessage: _extractRouteError);
      return Success(routes.isEmpty ? null : routes.first);
    } on SpiderContractMismatchError {
      rethrow;
    } catch (e) {
      return Failure(toSpiderError(e));
    }
  }
}

Map<String, dynamic> _buildSearchRequest(RouteFilter filter) {
  final body = <String, dynamic>{'q': filter.query ?? ''};
  final expr = _buildFilterExpression(filter);
  if (expr != null) body['filter'] = expr;
  if (filter.limit != null) body['limit'] = filter.limit;
  return body;
}

// Composes the Meilisearch filter expression: `mode = "TRAM" AND agencyName = "…"`. Attribute names are
// bare identifiers (Meili doesn't quote them); only string values are double-quoted, with embedded `"`/`\`
// escaped so a value can't break out of its clause. The mode value comes from the closed RouteMode
// vocabulary, so its wire string is safe to interpolate directly.
String? _buildFilterExpression(RouteFilter filter) {
  final clauses = <String>[];
  final mode = filter.mode;
  if (mode != null) clauses.add('mode = "${mode.wire}"');
  final agency = filter.agency;
  if (agency != null && agency.isNotEmpty) {
    clauses.add('agencyName = "${_escapeFilter(agency)}"');
  }
  return clauses.isEmpty ? null : clauses.join(' AND ');
}

List<TransitRoute> _parseSearchResponse(Map<String, dynamic> json) {
  final hits = json['hits'] as List<dynamic>? ?? const [];
  return hits.map((h) => _toRoute(h as Map<String, dynamic>)).toList();
}

TransitRoute _toRoute(Map<String, dynamic> hit) => TransitRoute(
      routeId: hit['routeId'] as String,
      shortName: hit['shortName'] as String?,
      longName: hit['longName'] as String?,
      mode: RouteMode.fromWire(hit['mode'] as String?),
      routeType: (hit['routeType'] as num?)?.toInt() ?? 0,
      agencyName: hit['agencyName'] as String?,
      tripCount: (hit['tripCount'] as num?)?.toInt() ?? 0,
    );

// Escape backslashes then double-quotes (order matters) for a Meilisearch filter literal.
String _escapeFilter(String value) =>
    value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');

String _extractRouteError(String text) {
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
