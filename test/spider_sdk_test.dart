import 'dart:convert';
import 'package:spider_sdk/spider_sdk.dart';
import 'package:spider_sdk/src/polyline.dart' show decodePolyline;
import 'package:test/test.dart';

class MockHttpClient implements SpiderHttpClient {
  final List<SpiderHttpRequest> requests = [];
  final SpiderHttpResponse Function(SpiderHttpRequest) handler;
  MockHttpClient(this.handler);

  @override
  Future<SpiderHttpResponse> send(SpiderHttpRequest request) async {
    requests.add(request);
    return handler(request);
  }
}

SpiderHttpResponse resp(String body,
    {int status = 200, String? contractVersion = '0.1'}) {
  final headers = <String, String>{};
  if (contractVersion != null) {
    headers['x-spider-contract-version'] = contractVersion;
  }
  return SpiderHttpResponse(status, headers, body);
}

(SpiderClient, MockHttpClient) makeClient(
    SpiderHttpResponse Function(SpiderHttpRequest) handler) {
  final mock = MockHttpClient(handler);
  final client = SpiderClient('https://env.api.example.com', 'secret-key',
      SpiderClientOptions(httpClient: mock));
  return (client, mock);
}

Map<String, dynamic> bodyOf(SpiderHttpRequest req) =>
    jsonDecode(req.body!) as Map<String, dynamic>;

const planBody = '''
{"data":{"planConnection":{
  "edges":[{"cursor":"c1","node":{
    "start":"2026-08-21T10:00:00Z","end":"2026-08-21T10:30:00Z","duration":1800,"waitingTime":120,"numberOfTransfers":1,"accessibilityScore":0.9,
    "legs":[{
      "start":{"scheduledTime":"2026-08-21T10:00:00Z"},"end":{"scheduledTime":"2026-08-21T10:15:00Z"},
      "from":{"name":"A","stop":{"gtfsId":"S1","wheelchairBoarding":"POSSIBLE"}},
      "to":{"name":"B","stop":{"gtfsId":"S2","wheelchairBoarding":"NOT_POSSIBLE"}},
      "mode":"BUS","route":{"shortName":"12","longName":"Line 12"},"headsign":"Downtown",
      "distance":1500.0,"duration":900.0,"accessibilityScore":1.0,
      "trip":{"gtfsId":"T1","bikesAllowed":"ALLOWED"},
      "legGeometry":{"points":"_p~iF~ps|U_ulLnnqC_mqNvxq`@"}
    }]
  }}],
  "pageInfo":{"hasNextPage":true,"hasPreviousPage":false,"startCursor":"c1","endCursor":"c1","searchWindowUsed":"PT60M"},
  "routingErrors":[],"searchDateTime":"2026-08-21T10:00:00Z"
}}}
''';

void main() {
  group('routing', () {
    test('plan posts the persisted query with headers and maps the route',
        () async {
      final (client, mock) = makeClient((_) => resp(planBody));
      final result = await client.routing.plan(const PlanOptions(
        origin: Location.coordinate(49.19, 16.61),
        destination: Location.coordinate(49.22, 16.52),
      ));
      expect(result, isA<Success<Route>>());
      final route = (result as Success<Route>).value;
      expect(route.edges.length, 1);
      final leg = route.edges[0].itinerary.legs[0];
      expect(leg.mode, TransitMode.bus);
      expect(leg.fromWheelchair, WheelchairBoarding.possible);
      expect(leg.toWheelchair, WheelchairBoarding.notPossible);
      expect(leg.bikesAllowed, BikesAllowed.allowed);
      expect(leg.geometry.length, 3);
      expect(route.pageInfo.hasNextPage, true);

      final req = mock.requests[0];
      expect(req.uri.path, '/routing/plan');
      expect(req.method, 'POST');
      expect(req.headers['apikey'], 'secret-key');
      expect(req.headers['x-spider-contract-version'], '0.1');
      expect(req.headers['x-spider-sdk'], 'dart/0.1.0');
      expect(req.headers['content-type'], 'application/json');
      final body = bodyOf(req);
      expect(body['id'],
          'dad4f190af803a8cb50ec99c5852544297e94db8edc0d94220c8f79d98f065a7');
      final vars = body['variables'] as Map<String, dynamic>;
      expect(vars.containsKey('first'), false);
      expect(vars.containsKey('last'), false);
      expect(vars['searchWindow'], 'PT60M');
      expect((vars['dateTime'] as Map)['earliestDeparture'], isNotNull);
      expect((vars['dateTime'] as Map)['latestArrival'], isNull);
    });

    test('plan with no filters omits modes/preferences (null-omission)',
        () async {
      final (client, mock) = makeClient((_) => resp(planBody));
      await client.routing.plan(const PlanOptions(
          origin: Location.stop('S1'), destination: Location.stop('S2')));
      final vars =
          bodyOf(mock.requests[0])['variables'] as Map<String, dynamic>;
      expect(vars.containsKey('modes'), false);
      expect(vars.containsKey('preferences'), false);
      expect(vars.containsKey('via'), false);
      expect(vars.containsKey('last'), false);
      expect(vars['searchWindow'], 'PT60M');
      final loc = (vars['origin'] as Map)['location'] as Map;
      expect((loc['stopLocation'] as Map)['stopLocationId'], 'S1');
    });

    test('plan maps modes, transfers, wheelchair, and search window', () async {
      final (client, mock) = makeClient((_) => resp(planBody));
      await client.routing.plan(const PlanOptions(
        origin: Location.coordinate(49.19, 16.61),
        destination: Location.coordinate(49.22, 16.52),
        allowedTransitModes: [
          TransitMode.bus,
          TransitMode.walk,
          TransitMode.tram
        ],
        maxTransfers: 2,
        searchWindowMinutes: 30,
        wheelchairAccessible: true,
      ));
      final vars =
          bodyOf(mock.requests[0])['variables'] as Map<String, dynamic>;
      expect(vars['searchWindow'], 'PT30M');
      final transit =
          ((vars['modes'] as Map)['transit'] as Map)['transit'] as List;
      expect(transit.map((e) => (e as Map)['mode']).toList(),
          ['BUS', 'TRAM']); // WALK dropped
      final prefs = vars['preferences'] as Map;
      expect(
          (((prefs['transit'] as Map)['transfer']) as Map)['maximumTransfers'],
          2);
      expect(
          (((prefs['accessibility'] as Map)['wheelchair']) as Map)['enabled'],
          true);
    });

    test('plan with arriveBy sets latestArrival', () async {
      final (client, mock) = makeClient((_) => resp(planBody));
      await client.routing.plan(PlanOptions(
        origin: const Location.stop('S1'),
        destination: const Location.stop('S2'),
        arriveBy:
            DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true),
      ));
      final dt =
          (bodyOf(mock.requests[0])['variables'] as Map)['dateTime'] as Map;
      expect(dt['latestArrival'], isNotNull);
      expect(dt['earliestDeparture'], isNull);
    });

    test('planNext pages forward with after and no count', () async {
      const page2 =
          '{"data":{"planConnection":{"edges":[],"pageInfo":{"hasNextPage":false,"hasPreviousPage":true,"startCursor":"c2","endCursor":"c2","searchWindowUsed":"PT60M"},"routingErrors":[],"searchDateTime":null}}}';
      final (client, mock) = makeClient((req) {
        final vars = bodyOf(req)['variables'] as Map<String, dynamic>;
        return resp(vars['after'] == 'c1' ? page2 : planBody);
      });
      final first = await client.routing.plan(const PlanOptions(
          origin: Location.stop('A'), destination: Location.stop('B')));
      final next =
          await client.routing.planNext((first as Success<Route>).value);
      expect(next, isNotNull);
      final vars =
          bodyOf(mock.requests[1])['variables'] as Map<String, dynamic>;
      expect(vars['after'], 'c1');
      expect(vars.containsKey('first'), false);
      expect(vars.containsKey('before'), false);
      expect(vars.containsKey('last'), false);
    });

    test('http error becomes a failure with a mapped code', () async {
      final (client, _) = makeClient(
          (_) => resp('{"code":"boom","message":"nope"}', status: 503));
      final result = await client.routing.plan(const PlanOptions(
          origin: Location.stop('A'), destination: Location.stop('B')));
      final error = (result as Failure<Route>).error;
      expect(error.code, SpiderErrorCode.server);
      expect(error.httpStatus, 503);
      expect(error.serverCode, 'boom');
    });

    test('upstream GraphQL errors become a failure', () async {
      final (client, _) =
          makeClient((_) => resp('{"errors":[{"message":"bad var"}]}'));
      final result = await client.routing.plan(const PlanOptions(
          origin: Location.stop('A'), destination: Location.stop('B')));
      final error = (result as Failure<Route>).error;
      expect(error.code, SpiderErrorCode.server);
      expect(error.message, contains('bad var'));
    });

    test(
        'a top-level BAD_REQUEST error becomes a badRequest failure '
        'with field and message', () async {
      const body = '{"data":null,"errors":[{'
          '"message":"searchWindow exceeds the maximum of PT2H",'
          '"extensions":{"code":"BAD_REQUEST","field":"searchWindow"}}]}';
      final (client, _) = makeClient((_) => resp(body));
      final result = await client.routing.plan(const PlanOptions(
          origin: Location.stop('A'), destination: Location.stop('B')));
      final error = (result as Failure<Route>).error;
      expect(error.code, SpiderErrorCode.badRequest);
      expect(error.field, 'searchWindow');
      expect(error.message, 'searchWindow exceeds the maximum of PT2H');
    });

    test('contract mismatch throws instead of returning', () async {
      final (client, _) =
          makeClient((_) => resp(planBody, contractVersion: '4.0'));
      await expectLater(
        client.routing.plan(const PlanOptions(
            origin: Location.stop('A'), destination: Location.stop('B'))),
        throwsA(isA<SpiderContractMismatchError>()),
      );
    });

    test('departures maps and drops sibling-terminating trips', () async {
      const body = '''
      {"data":{"asStop":{"gtfsId":"S","name":"Main Square","wheelchairBoarding":"POSSIBLE","stoptimesWithoutPatterns":[
        {"serviceDay":1700000000,"scheduledDeparture":36000,"realtimeDeparture":36060,"realtime":true,"realtimeState":"UPDATED","headsign":"Airport","trip":{"gtfsId":"T1","bikesAllowed":"ALLOWED","route":{"shortName":"12","longName":"Line 12","mode":"BUS"}}},
        {"serviceDay":1700000000,"scheduledDeparture":36300,"realtime":false,"headsign":"main square","trip":{"gtfsId":"T2","route":{"shortName":"5","mode":"TRAM"}}}
      ]}}}''';
      final (client, _) = makeClient((_) => resp(body));
      final result =
          await client.routing.departures('S', numberOfDepartures: 10);
      final departures = (result as Success<List<Departure>>).value;
      expect(departures.length, 1);
      expect(departures[0].scheduledTimeEpochMs, (1700000000 + 36000) * 1000);
      expect(departures[0].mode, TransitMode.bus);
      expect(departures[0].realtimeState, RealtimeState.updated);
      expect(departures[0].isRealtime, true);
    });

    test('trip maps stops, geometry and enums', () async {
      const body = '''
      {"data":{"trip":{"gtfsId":"T1","directionId":"0","tripHeadsign":"Airport","bikesAllowed":"NOT_ALLOWED","route":{"shortName":"12","longName":"Line 12","mode":"BUS"},"stoptimesForDate":[
        {"serviceDay":1700000000,"scheduledArrival":36000,"scheduledDeparture":36030,"realtimeArrival":36050,"realtimeDeparture":36080,"realtime":true,"stop":{"gtfsId":"S1","name":"A","lat":49.19,"lon":16.61,"wheelchairBoarding":"POSSIBLE"}}
      ],"tripGeometry":{"points":"_p~iF~ps|U","length":2}}}}''';
      final (client, _) = makeClient((_) => resp(body));
      final result = await client.routing.trip('T1', serviceDate: '2026-08-21');
      final trip = (result as Success<TripDetails>).value;
      expect(trip.mode, TransitMode.bus);
      expect(trip.bikesAllowed, BikesAllowed.notAllowed);
      expect(trip.stops.length, 1);
      expect(
          trip.stops[0].scheduledArrivalEpochMs, (1700000000 + 36000) * 1000);
      expect(trip.geometry.length, 1);
    });
  });

  group('stops', () {
    test('search builds the filter expression with escaping and maps hits',
        () async {
      const body =
          '{"hits":[{"gtfsId":"S1","name":"Main","lat":49.1,"lon":16.6,"country":"CZ","city":"Example City"}],"query":"Main"}';
      final (client, mock) = makeClient((_) => resp(body));
      final result = await client.stops
          .search(const StopFilter(name: 'Main', country: 'CZ', city: 'Br"no'));
      final stops = (result as Success<List<Stop>>).value;
      expect(stops.length, 1);
      expect(stops[0].city, 'Example City');
      final body2 = bodyOf(mock.requests[0]);
      expect(body2['q'], 'Main');
      expect(body2['filter'], r'country = "CZ" AND city = "Br\"no"');
    });

    test('search with only a name omits the filter', () async {
      final (client, mock) = makeClient((_) => resp('{"hits":[]}'));
      await client.stops.search(const StopFilter(name: 'Main'));
      final body = bodyOf(mock.requests[0]);
      expect(body['q'], 'Main');
      expect(body.containsKey('filter'), false);
    });

    test('admin-level (city) filter uses bare attribute names', () async {
      final (client, mock) = makeClient((_) => resp('{"hits":[]}'));
      await client.stops.search(const StopFilter(city: 'Example City'));
      final body = bodyOf(mock.requests[0]);
      expect(body['q'], '');
      expect(body['filter'], 'city = "Example City"');
    });

    test('near composes a geoRadius filter, geoPoint sort, and empty query',
        () async {
      final (client, mock) = makeClient((_) => resp('{"hits":[]}'));
      await client.stops.near(49.19, 16.61, radiusMeters: 500, limit: 10);
      final body = bodyOf(mock.requests[0]);
      expect(body['q'], '');
      expect(body['filter'], '_geoRadius(49.19, 16.61, 500)');
      expect(body['sort'], ['_geoPoint(49.19, 16.61):asc']);
      expect(body['limit'], 10);
    });

    test('near without a radius sorts by distance but adds no filter',
        () async {
      final (client, mock) = makeClient((_) => resp('{"hits":[]}'));
      await client.stops.near(49.19, 16.61);
      final body = bodyOf(mock.requests[0]);
      expect(body.containsKey('filter'), false);
      expect(body['sort'], ['_geoPoint(49.19, 16.61):asc']);
    });

    test('within composes a geoBoundingBox filter (max corner, then min)',
        () async {
      final (client, mock) = makeClient((_) => resp('{"hits":[]}'));
      await client.stops.within(49.18, 16.59, 49.21, 16.63);
      final body = bodyOf(mock.requests[0]);
      expect(body['filter'], '_geoBoundingBox([49.21, 16.63], [49.18, 16.59])');
      expect(body.containsKey('sort'), false);
    });

    test('byId filters on gtfsId, caps to 1, and maps the first hit', () async {
      const body =
          '{"hits":[{"gtfsId":"1:39822","name":"Hlavní nádraží","lat":49.19,"lon":16.61,"city":"Example City"}],"query":""}';
      final (client, mock) = makeClient((_) => resp(body));
      final result = await client.stops.byId('1:39822');
      final stop = (result as Success<Stop?>).value;
      expect(stop, isNotNull);
      expect(stop!.name, 'Hlavní nádraží');
      final sent = bodyOf(mock.requests[0]);
      expect(sent['q'], '');
      expect(sent['filter'], 'gtfsId = "1:39822"');
      expect(sent['limit'], 1);
    });

    test('byId returns null when there are no hits', () async {
      final (client, _) = makeClient((_) => resp('{"hits":[]}'));
      final result = await client.stops.byId('nope');
      expect((result as Success<Stop?>).value, isNull);
    });

    test('radiusMeters without near throws before any request', () async {
      final (client, mock) = makeClient((_) => resp('{"hits":[]}'));
      await expectLater(
        client.stops.search(const StopFilter(radiusMeters: 500)),
        throwsA(isA<ArgumentError>()),
      );
      expect(mock.requests, isEmpty);
    });
  });

  group('realtime', () {
    test('vehicles maps and converts seconds to millis', () async {
      const body =
          '{"vehicles":[{"tripId":"T1","latitude":49.1,"longitude":16.6,"occupancyStatus":"FEW_SEATS_AVAILABLE","timestamp":1700000000}],"missing":["T9"],"feedTimestamp":1700000000,"staleSeconds":3.5}';
      final (client, mock) = makeClient((_) => resp(body));
      final result = await client.realtime.vehicles(['T1', 'T9']);
      final positions = (result as Success<VehiclePositions>).value;
      expect(positions.vehicles[0].timestampEpochMs, 1700000000 * 1000);
      expect(
          positions.vehicles[0].occupancy, OccupancyStatus.fewSeatsAvailable);
      expect(positions.missing, ['T9']);
      expect(positions.freshness.feedTimestampEpochMs, 1700000000 * 1000);
      expect(mock.requests[0].uri.queryParameters['tripIds'], 'T1,T9');
    });

    test('vehicles with empty ids short-circuits without a request', () async {
      final (client, mock) = makeClient((_) => resp('{}'));
      final result = await client.realtime.vehicles([]);
      expect((result as Success<VehiclePositions>).value.vehicles, isEmpty);
      expect(mock.requests, isEmpty);
    });

    test('vehicleForTrip 404 is a soft null', () async {
      final (client, _) = makeClient((_) => resp('{}', status: 404));
      final result = await client.realtime.vehicleForTrip('T1');
      expect((result as Success<LiveVehicleUpdate>).value.vehicle, isNull);
    });
  });

  group('enums and polyline', () {
    test('open and closed enum mapping', () {
      expect(TransitMode.fromWire('BUS'), TransitMode.bus);
      expect(TransitMode.fromWire('SOMETHING_NEW'), TransitMode.unknown);
      expect(TransitMode.fromWire(null), isNull);
      expect(WheelchairBoarding.fromWire('NO_INFORMATION'), isNull);
      expect(OccupancyStatus.fromWire('NO_DATA_AVAILABLE'), isNull);
      expect(OccupancyStatus.fromWire('WEIRD'), OccupancyStatus.unknown);
    });

    test('polyline decodes the Google example', () {
      final points = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
      expect(points.length, 3);
      expect(points[0].lat, closeTo(38.5, 1e-5));
      expect(points[0].lon, closeTo(-120.2, 1e-5));
      expect(points[2].lat, closeTo(43.252, 1e-5));
    });

    test('client exposes contract version', () {
      final (client, _) = makeClient((_) => resp('{}'));
      expect(client.contractVersion, '0.1');
    });
  });
}
