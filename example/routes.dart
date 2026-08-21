// Route-search examples for the Spider Dart SDK. The docs site inlines the
// named regions below (between the START/END markers) as code samples.
import 'package:spider_sdk/spider_sdk.dart';

/// Search routes by free text, transit mode, and operating agency.
Future<void> routesSearch(SpiderClient client) async {
  // [START routesSearch]
  final result = await client.routes.search(const RouteFilter(
    query: 'Hlavní',
    mode: RouteMode.tram,
    agency: 'DPMB',
    limit: 20,
  ));

  if (result case Success(:final value)) {
    // Hits come back busiest-first (ranked by trip count) — the most-used
    // routes lead without an explicit sort.
    for (final route in value) {
      final name = route.shortName ?? route.longName ?? route.routeId;
      print('$name (${route.mode.name}) — ${route.tripCount} trips');
    }
  }
  // [END routesSearch]
}

/// Look up a single route by its feed-scoped id.
Future<void> routesById(SpiderClient client) async {
  // [START routesById]
  final result = await client.routes.byId('1:L4');

  switch (result) {
    case Success(value: final route?):
      final name = route.shortName ?? route.longName ?? route.routeId;
      print('found $name (${route.mode.name})');
    case Success():
      print('no route with that id');
    case Failure(:final error):
      print('lookup failed: ${error.code.name} — ${error.message}');
  }
  // [END routesById]
}
