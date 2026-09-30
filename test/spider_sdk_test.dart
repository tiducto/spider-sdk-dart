import 'dart:convert';
import 'package:spider_sdk/spider_sdk.dart';
import 'package:spider_sdk/src/contract/contract_version.dart'
    show contractVersion;
import 'package:spider_sdk/src/contract/persisted_queries.dart'
    show PersistedQueries;
import 'package:spider_sdk/src/contract/routing.dart' as wire;
import 'package:spider_sdk/src/polyline.dart' show decodePolyline;
import 'package:spider_sdk/src/routing.dart' show parsePlanStreamRecord;
import 'package:spider_sdk/src/service_date.dart' show serviceDateOf;
import 'package:spider_sdk/src/version.dart' show sdkVersion;
import 'package:test/test.dart';

class MockHttpClient implements SpiderHttpClient {
  final List<SpiderHttpRequest> requests = [];
  final SpiderHttpResponse Function(SpiderHttpRequest) handler;
  final SpiderHttpStreamedResponse Function(SpiderHttpRequest)? streamHandler;
  MockHttpClient(this.handler, {this.streamHandler});

  @override
  Future<SpiderHttpResponse> send(SpiderHttpRequest request) async {
    requests.add(request);
    return handler(request);
  }

  @override
  Future<SpiderHttpStreamedResponse> sendStreaming(
      SpiderHttpRequest request) async {
    requests.add(request);
    final handle = streamHandler;
    if (handle == null) {
      throw StateError('no stream handler configured for this mock');
    }
    return handle(request);
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

Map<String, dynamic> varsOf(SpiderHttpRequest req) =>
    bodyOf(req)['variables'] as Map<String, dynamic>;

(SpiderClient, MockHttpClient) makeStreamClient(int status, String body,
    {String contentType = 'text/event-stream'}) {
  final mock = MockHttpClient((_) => resp('{}'),
      streamHandler: (_) => SpiderHttpStreamedResponse(status,
          {'content-type': contentType}, Stream.value(utf8.encode(body))));
  final client = SpiderClient('https://env.api.example.com', 'secret-key',
      SpiderClientOptions(httpClient: mock));
  return (client, mock);
}

const stopsAB =
    PlanOptions(origin: Location.stop('A'), destination: Location.stop('B'));

const emptyPlanBody =
    '{"data":{"planConnection":{"edges":[],"pageInfo":{"hasNextPage":false,"hasPreviousPage":false},"routingErrors":[]}}}';

const planBody = '''
{"data":{"planConnection":{
  "edges":[{"cursor":"c1","node":{
    "start":"2026-08-21T10:00:00Z","end":"2026-08-21T10:30:00Z","duration":1800,"waitingTime":120,"numberOfTransfers":1,"accessibilityScore":0.9,
    "legs":[{
      "start":{"scheduledTime":"2026-08-21T10:00:00Z"},"end":{"scheduledTime":"2026-08-21T10:15:00Z"},
      "from":{"name":"A","stop":{"gtfsId":"S1","wheelchairBoarding":"POSSIBLE","platformCode":"1","zoneId":"P"}},
      "to":{"name":"B","stop":{"gtfsId":"S2","wheelchairBoarding":"NOT_POSSIBLE","platformCode":"B2","zoneId":"0"}},
      "mode":"BUS","route":{"gtfsId":"1:R12","shortName":"12","longName":"Line 12","color":"FF0000","textColor":"FFFFFF"},"headsign":"Downtown",
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
      expect(leg.routeGtfsId, '1:R12');
      expect(leg.routeColor, 'FF0000');
      expect(leg.routeTextColor, 'FFFFFF');
      expect(leg.fromPlatformCode, '1');
      expect(leg.toPlatformCode, 'B2');
      expect(leg.fromZoneId, 'P');
      expect(leg.toZoneId, '0');
      expect(route.pageInfo.hasNextPage, true);

      final req = mock.requests[0];
      expect(req.uri.path, '/routing/plan');
      expect(req.method, 'POST');
      expect(req.headers['apikey'], 'secret-key');
      expect(req.headers['x-spider-contract-version'], contractVersion);
      expect(req.headers['x-spider-sdk'], 'dart/$sdkVersion');
      expect(req.headers['content-type'], 'application/json');
      final body = bodyOf(req);
      expect(body['id'], PersistedQueries.plan.id);
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
        // 2 transfers ⇒ wire maximumTransfers = 3 (the router counts boardings = transfers + 1).
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
          3);
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
          '"message":"searchWindow is out of range",'
          '"extensions":{"code":"BAD_REQUEST","field":"searchWindow"}}]}';
      final (client, _) = makeClient((_) => resp(body));
      final result = await client.routing.plan(const PlanOptions(
          origin: Location.stop('A'), destination: Location.stop('B')));
      final error = (result as Failure<Route>).error;
      expect(error.code, SpiderErrorCode.badRequest);
      expect(error.field, 'searchWindow');
      expect(error.message, 'searchWindow is out of range');
    });

    test('plan sends the search window as given, without clamping', () async {
      final (client, mock) = makeClient((_) => resp(planBody));
      await client.routing.plan(const PlanOptions(
          origin: Location.stop('A'),
          destination: Location.stop('B'),
          searchWindowMinutes: 0));
      expect(varsOf(mock.requests.single)['searchWindow'], 'PT0M');
    });

    test('plan maps LOCATION_NOT_FOUND on from, to and via', () async {
      const body = '{"data":{"planConnection":{"edges":[],'
          '"pageInfo":{"hasNextPage":false,"hasPreviousPage":false},'
          '"routingErrors":['
          '{"code":"LOCATION_NOT_FOUND","inputField":"FROM","description":"unknown origin"},'
          '{"code":"LOCATION_NOT_FOUND","inputField":"TO","description":"unknown destination"},'
          '{"code":"LOCATION_NOT_FOUND","inputField":"VIA","description":"unknown via stop"}'
          ']}}}';
      final (client, _) = makeClient((_) => resp(body));
      final result = await client.routing.plan(const PlanOptions(
          origin: Location.stop('A'),
          destination: Location.stop('B'),
          via: [
            ViaLocation.passThrough(['X'])
          ]));
      final errors = (result as Success<Route>).value.routingErrors;
      expect(errors.map((e) => e.code),
          everyElement(RoutingErrorCode.locationNotFound));
      expect(errors.map((e) => e.inputField),
          [InputField.from, InputField.to, InputField.via]);
    });

    group('via limits', () {
      Future<(SpiderResult<Route>, MockHttpClient)> planVia(
          List<ViaLocation> via) async {
        final (client, mock) = makeClient((_) => resp(emptyPlanBody));
        final result = await client.routing.plan(PlanOptions(
            origin: const Location.stop('A'),
            destination: const Location.stop('B'),
            via: via));
        return (result, mock);
      }

      test('reject 0 or more than 10 stop ids without a request', () async {
        for (final count in [0, 11]) {
          final (result, mock) = await planVia(
              [ViaLocation.passThrough(List.generate(count, (i) => 'S$i'))]);
          final error = (result as Failure<Route>).error;
          expect(error.code, SpiderErrorCode.badRequest, reason: '$count');
          expect(error.field, 'via');
          expect(error.message, 'via is out of range');
          expect(mock.requests, isEmpty);
        }
      });

      test('reject a visit wait below 0 or above 24 h without a request',
          () async {
        for (final wait in [-1, 86401]) {
          final (result, mock) = await planVia([
            ViaLocation.visit(const Location.stop('V'),
                minimumWaitSeconds: wait)
          ]);
          final error = (result as Failure<Route>).error;
          expect(error.field, 'via', reason: '$wait');
          expect(mock.requests, isEmpty);
        }
      });

      test('send 10 stop ids and a 24 h wait', () async {
        final (result, mock) = await planVia([
          ViaLocation.passThrough(List.generate(10, (i) => 'S$i')),
          ViaLocation.visit(const Location.stop('V'),
              minimumWaitSeconds: 86400),
        ]);
        expect(result, isA<Success<Route>>());
        final via = varsOf(mock.requests.single)['via'] as List;
        expect(
            ((via[0] as Map)['passThrough'] as Map)['stopLocationIds'] as List,
            hasLength(10));
        expect(
            ((via[1] as Map)['visit'] as Map)['minimumWaitTime'], 'PT86400S');
      });

      test('leave the number of via locations to the server', () async {
        final (result, mock) = await planVia(
            List.generate(5, (i) => ViaLocation.passThrough(['S$i'])));
        expect(result, isA<Success<Route>>());
        expect(varsOf(mock.requests.single)['via'] as List, hasLength(5));
      });
    });

    test('a different contract major declared by the gateway is ignored',
        () async {
      final (client, _) =
          makeClient((_) => resp(planBody, contractVersion: '4.0'));
      final result = await client.routing.plan(const PlanOptions(
          origin: Location.stop('A'), destination: Location.stop('B')));
      expect(result, isA<Success<Route>>());
    });

    test('a retired persisted query (410 query_retired) is queryRetired',
        () async {
      final (client, _) = makeClient((_) => resp(
          '{"error":"query_retired","message":"persisted query is retired"}',
          status: 410));
      final result = await client.routing.plan(stopsAB);
      final error = (result as Failure<Route>).error;
      expect(error.code, SpiderErrorCode.queryRetired);
      expect(error.httpStatus, 410);
      expect(error.serverCode, 'query_retired');
      expect(error.message, contains('persisted query is retired'));
      expect(error.message.toLowerCase(), isNot(contains('update')));
    });

    test('the query_retired body code wins over the status', () async {
      final (client, _) =
          makeClient((_) => resp('{"error":"query_retired"}', status: 400));
      final result = await client.routing.trip('T1');
      expect((result as Failure<TripDetails>).error.code,
          SpiderErrorCode.queryRetired);
    });

    test('a bare 410 falls back to queryRetired', () async {
      final (client, _) = makeClient((_) => resp('', status: 410));
      final result = await client.routing.departures('S');
      final error = (result as Failure<List<Departure>>).error;
      expect(error.code, SpiderErrorCode.queryRetired);
      expect(error.serverCode, 'query_retired');
    });

    test('an unknown persisted-query id (403) is unauthorized', () async {
      final (client, _) = makeClient((_) => resp(
          '{"error":"persisted_query_rejected","message":"unknown persisted-query id: abc"}',
          status: 403));
      final result = await client.routing.plan(stopsAB);
      final error = (result as Failure<Route>).error;
      expect(error.code, SpiderErrorCode.unauthorized);
      expect(error.httpStatus, 403);
      expect(error.serverCode, 'persisted_query_rejected');
      expect(error.message,
          'routing plan -> 403: unknown persisted-query id: abc');
      expect(error.message.toLowerCase(), isNot(contains('update')));
    });

    test('a routing 400 is a badRequest naming the field its message names',
        () async {
      final (client, _) = makeClient((_) =>
          resp('{"message":"searchWindow is out of range"}', status: 400));
      final result = await client.routing.plan(stopsAB);
      final error = (result as Failure<Route>).error;
      expect(error.code, SpiderErrorCode.badRequest);
      expect(error.httpStatus, 400);
      expect(error.field, 'searchWindow');
    });

    test('a 400 names a field only in the fixed message shapes', () async {
      for (final (message, field) in [
        ('limit is out of range', 'limit'),
        ('limit is required', 'limit'),
        ('body is invalid', 'body'),
        ('limit must be an integer', null),
        ('limit is out of range: 0', null),
        ('missing or unreadable body', null),
      ]) {
        final (client, _) = makeClient((_) => resp(
            jsonEncode({'error': 'bad_request', 'message': message}),
            status: 400));
        final result = await client.stops.search(const StopFilter(name: 'M'));
        final error = (result as Failure<List<Stop>>).error;
        expect(error.code, SpiderErrorCode.badRequest, reason: message);
        expect(error.field, field, reason: message);
      }
    });

    test('any other 403 keeps the gateway message', () async {
      final (client, _) = makeClient((_) => resp(
          '{"error":"Access to this API has been disallowed"}',
          status: 403));
      final result = await client.routing.departures('S');
      final error = (result as Failure<List<Departure>>).error;
      expect(error.code, SpiderErrorCode.unauthorized);
      expect(error.serverCode, isNull);
    });

    // serviceDay 1784066400 = 2026-07-14T22:00Z, noon minus 12 h on 2026-07-15 in Europe/Prague (CEST).
    test(
        'departures keeps every row the router returns and carries the '
        'service date', () async {
      const body = '''
      {"data":{"asStop":{"gtfsId":"S","name":"Main Square","wheelchairBoarding":"POSSIBLE","stoptimesWithoutPatterns":[
        {"serviceDay":1784066400,"scheduledDeparture":36000,"realtimeDeparture":36060,"realtime":true,"realtimeState":"UPDATED","headsign":"Airport","trip":{"gtfsId":"T1","bikesAllowed":"ALLOWED","route":{"gtfsId":"1:R12","shortName":"12","longName":"Line 12","mode":"BUS"}}},
        {"serviceDay":1784066400,"scheduledDeparture":88800,"realtime":false,"headsign":"main square","trip":{"gtfsId":"T2","route":{"gtfsId":"1:R5","shortName":"5","mode":"TRAM"}}}
      ]}}}''';
      final (client, mock) = makeClient((_) => resp(body));
      final result =
          await client.routing.departures('S', numberOfDepartures: 10);
      final departures = (result as Success<List<Departure>>).value;
      expect(varsOf(mock.requests.single)['numberOfDepartures'], 10);
      expect(departures.length, 2);
      expect(departures[0].scheduledTimeEpochMs, (1784066400 + 36000) * 1000);
      expect(departures[0].mode, TransitMode.bus);
      expect(departures[0].realtimeState, RealtimeState.updated);
      expect(departures[0].isRealtime, true);
      expect(departures[0].serviceDate, '2026-07-15');
      // A row whose headsign is the stop's own name is a real departure, not a terminating trip.
      expect(departures[1].headsign, 'main square');
      // 24:40 on the 15th's timetable runs on the 16th's clock but keeps the 15th's service date.
      expect(departures[1].serviceDate, '2026-07-15');
    });

    test('departures maps the route, stop and accessibility display fields',
        () async {
      const body = '''
      {"data":{"asStation":{"gtfsId":"1:ST","name":"Central","stoptimesWithoutPatterns":[
        {"serviceDay":1784066400,"scheduledDeparture":36000,"stop":{"gtfsId":"1:ST-P2","platformCode":"2"},"trip":{"gtfsId":"T1","wheelchairAccessible":"NOT_POSSIBLE","route":{"gtfsId":"1:R12","shortName":"12","color":"FF0000","textColor":"FFFFFF"}}},
        {"serviceDay":1784066400,"scheduledDeparture":36600,"trip":{"gtfsId":"T2","wheelchairAccessible":"NO_INFORMATION","route":{"gtfsId":"1:R5"}}}
      ]}}}''';
      final (client, _) = makeClient((_) => resp(body));
      final result = await client.routing.departures('1:ST');
      final departures = (result as Success<List<Departure>>).value;
      final full = departures[0];
      expect(full.routeGtfsId, '1:R12');
      expect(full.routeColor, 'FF0000');
      expect(full.routeTextColor, 'FFFFFF');
      expect(full.stopGtfsId, '1:ST-P2');
      expect(full.platformCode, '2');
      expect(full.wheelchairAccessible, WheelchairBoarding.notPossible);
      final bare = departures[1];
      expect(bare.routeGtfsId, '1:R5');
      expect(bare.routeColor, isNull);
      expect(bare.routeTextColor, isNull);
      expect(bare.stopGtfsId, isNull);
      expect(bare.platformCode, isNull);
      expect(bare.wheelchairAccessible, isNull);
    });

    test('departures always sends the default count and a 24 h time range',
        () async {
      final (client, mock) = makeClient(
          (_) => resp('{"data":{"asStop":{"gtfsId":"S","name":"S"}}}'));
      await client.routing.departures('S');
      final vars = varsOf(mock.requests.single);
      expect(vars['numberOfDepartures'], 30);
      expect(vars['timeRange'], 86400);
      expect(vars.containsKey('startTime'), false);
    });

    test('departures rejects a time range outside (0, 24 h] without a request',
        () async {
      for (final range in [0, -60, 86401]) {
        final (client, mock) = makeClient((_) => resp('{}'));
        final result =
            await client.routing.departures('S', timeRangeSeconds: range);
        final error = (result as Failure<List<Departure>>).error;
        expect(error.code, SpiderErrorCode.badRequest, reason: '$range');
        expect(error.field, 'timeRange');
        expect(error.message, 'timeRange is out of range');
        expect(mock.requests, isEmpty);
      }
      final (client, mock) = makeClient(
          (_) => resp('{"data":{"asStop":{"gtfsId":"S","name":"S"}}}'));
      await client.routing.departures('S', timeRangeSeconds: 1);
      expect(varsOf(mock.requests.single)['timeRange'], 1);
    });

    test('trip without a service date leaves it to the server (today)',
        () async {
      final (client, mock) = makeClient((_) => resp(
          '{"data":{"trip":{"gtfsId":"T1","route":{"gtfsId":"R1"},"stoptimesForDate":[]}}}'));
      final result = await client.routing.trip('T1');
      expect(result, isA<Success<TripDetails>>());
      expect(varsOf(mock.requests.single).containsKey('serviceDate'), false);
    });

    test('trip maps stops, geometry and enums', () async {
      const body = '''
      {"data":{"trip":{"gtfsId":"T1","directionId":"0","tripHeadsign":"Airport","bikesAllowed":"NOT_ALLOWED","route":{"gtfsId":"1:R12","shortName":"12","longName":"Line 12","mode":"BUS"},"stoptimesForDate":[
        {"serviceDay":1787263200,"scheduledArrival":36000,"scheduledDeparture":36030,"realtimeArrival":36050,"realtimeDeparture":36080,"realtime":true,"stop":{"gtfsId":"S1","name":"A","lat":49.19,"lon":16.61,"wheelchairBoarding":"POSSIBLE"}}
      ],"tripGeometry":{"points":"_p~iF~ps|U","length":2}}}}''';
      final (client, mock) = makeClient((_) => resp(body));
      final result = await client.routing.trip('T1', serviceDate: '2026-08-21');
      final trip = (result as Success<TripDetails>).value;
      expect(trip.mode, TransitMode.bus);
      expect(trip.bikesAllowed, BikesAllowed.notAllowed);
      expect(trip.serviceDate, '2026-08-21');
      expect(trip.stops.length, 1);
      expect(
          trip.stops[0].scheduledArrivalEpochMs, (1787263200 + 36000) * 1000);
      expect(trip.geometry.length, 1);
      expect((bodyOf(mock.requests.single)['variables'] as Map)['serviceDate'],
          '2026-08-21');
    });

    test('trip maps the route, accessibility and stop display fields',
        () async {
      const body = '''
      {"data":{"trip":{"gtfsId":"T1","wheelchairAccessible":"POSSIBLE","route":{"gtfsId":"1:R12","shortName":"12","color":"00A0E2","textColor":"000000"},"stoptimesForDate":[
        {"serviceDay":1787263200,"scheduledArrival":36000,"stop":{"gtfsId":"S1","name":"A","platformCode":"3","zoneId":"P"}},
        {"serviceDay":1787263200,"scheduledArrival":36600,"stop":{"gtfsId":"S2","name":"B"}}
      ]}}}''';
      final (client, _) = makeClient((_) => resp(body));
      final trip =
          ((await client.routing.trip('T1')) as Success<TripDetails>).value;
      expect(trip.routeGtfsId, '1:R12');
      expect(trip.routeColor, '00A0E2');
      expect(trip.routeTextColor, '000000');
      expect(trip.wheelchairAccessible, WheelchairBoarding.possible);
      expect(trip.stops[0].platformCode, '3');
      expect(trip.stops[0].zoneId, 'P');
      expect(trip.stops[1].platformCode, isNull);
      expect(trip.stops[1].zoneId, isNull);

      final (bareClient, _) = makeClient((_) => resp(
          '{"data":{"trip":{"gtfsId":"T1","route":{"gtfsId":"1:R12"},"stoptimesForDate":[]}}}'));
      final bare =
          ((await bareClient.routing.trip('T1')) as Success<TripDetails>).value;
      expect(bare.routeColor, isNull);
      expect(bare.routeTextColor, isNull);
      expect(bare.wheelchairAccessible, isNull);
    });

    test('trip rejects a malformed service date without a request', () async {
      for (final date in ['20260821', '2026-02-30', '2026-8-21', 'today']) {
        final (client, mock) = makeClient((_) => resp('{}'));
        final result = await client.routing.trip('T1', serviceDate: date);
        final error = (result as Failure<TripDetails>).error;
        expect(error.code, SpiderErrorCode.badRequest, reason: date);
        expect(error.field, 'serviceDate');
        expect(error.message, 'serviceDate is invalid');
        expect(mock.requests, isEmpty);
      }
    });

    test('service date is the UTC date of noon on the service day', () {
      expect(serviceDateOf(1784066400), '2026-07-15'); // Prague, summer
      expect(serviceDateOf(1774735200), '2026-03-29'); // Prague, spring-forward
      expect(serviceDateOf(1792882800), '2026-10-25'); // Prague, fall-back
      expect(serviceDateOf(1784098800), '2026-07-15'); // Los Angeles, summer
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

    test('search maps code, location type and wheelchair boarding', () async {
      const body = '{"hits":['
          '{"gtfsId":"1:U1","name":"Station","code":"ZV","locationType":1,"wheelchairBoarding":1},'
          '{"gtfsId":"1:U2","name":"Stop","wheelchairBoarding":2},'
          '{"gtfsId":"1:U3","name":"Bare","wheelchairBoarding":0},'
          '{"gtfsId":"1:U4","name":"Odd","wheelchairBoarding":7}'
          ']}';
      final (client, _) = makeClient((_) => resp(body));
      final result = await client.stops.search(const StopFilter(name: 'S'));
      final stops = (result as Success<List<Stop>>).value;
      expect(stops[0].code, 'ZV');
      expect(stops[0].locationType, 1);
      expect(stops[0].wheelchairBoarding, WheelchairBoarding.possible);
      expect(stops[1].code, isNull);
      expect(stops[1].locationType, isNull);
      expect(stops[1].wheelchairBoarding, WheelchairBoarding.notPossible);
      expect(stops[2].wheelchairBoarding, isNull);
      expect(stops[3].wheelchairBoarding, WheelchairBoarding.unknown);
    });

    test('search with only a name omits the filter and sends limit 20',
        () async {
      final (client, mock) = makeClient((_) => resp('{"hits":[]}'));
      await client.stops.search(const StopFilter(name: 'Main'));
      final body = bodyOf(mock.requests[0]);
      expect(body['q'], 'Main');
      expect(body.containsKey('filter'), false);
      expect(body['limit'], 20);
    });

    test('search maps modes, an unknown mode to unknown, absent to empty',
        () async {
      const body = '{"hits":['
          '{"gtfsId":"1:U1","name":"Hub","modes":["BUS","RAIL","HOVERCRAFT"]},'
          '{"gtfsId":"1:U2","name":"Unserved"}'
          ']}';
      final (client, _) = makeClient((_) => resp(body));
      final result = await client.stops.search(const StopFilter(name: 'H'));
      final stops = (result as Success<List<Stop>>).value;
      expect(stops[0].modes,
          [TransitMode.bus, TransitMode.rail, TransitMode.unknown]);
      expect(stops[1].modes, isEmpty);
    });

    test('a modes filter matches stops served by any of the modes', () async {
      final (client, mock) = makeClient((_) => resp('{"hits":[]}'));
      await client.stops.search(const StopFilter(
          city: 'Example City', modes: [TransitMode.rail, TransitMode.tram]));
      expect(bodyOf(mock.requests.single)['filter'],
          'city = "Example City" AND modes IN ["RAIL", "TRAM"]');
    });

    test('a modes filter ignores unknown', () async {
      final (client, mock) = makeClient((_) => resp('{"hits":[]}'));
      await client.stops.search(const StopFilter(
          name: 'M', modes: [TransitMode.unknown, TransitMode.rail]));
      await client.stops
          .search(const StopFilter(name: 'M', modes: [TransitMode.unknown]));
      expect(bodyOf(mock.requests[0])['filter'], 'modes IN ["RAIL"]');
      expect(bodyOf(mock.requests[1]).containsKey('filter'), false);
    });

    test('search rejects a limit outside 1–50 without a request', () async {
      for (final limit in [0, 51]) {
        final (client, mock) = makeClient((_) => resp('{"hits":[]}'));
        final result =
            await client.stops.search(StopFilter(name: 'Main', limit: limit));
        final error = (result as Failure<List<Stop>>).error;
        expect(error.code, SpiderErrorCode.badRequest, reason: '$limit');
        expect(error.field, 'limit');
        expect(error.message, 'limit is out of range');
        expect(mock.requests, isEmpty);
      }
      for (final limit in [1, 50]) {
        final (client, mock) = makeClient((_) => resp('{"hits":[]}'));
        await client.stops.search(StopFilter(name: 'Main', limit: limit));
        expect(bodyOf(mock.requests.single)['limit'], limit);
      }
    });

    test('a gateway 400 is a badRequest naming the field', () async {
      final (client, _) = makeClient((_) => resp(
          '{"error":"bad_request","message":"limit is out of range"}',
          status: 400));
      final result = await client.stops.search(const StopFilter(name: 'M'));
      final error = (result as Failure<List<Stop>>).error;
      expect(error.code, SpiderErrorCode.badRequest);
      expect(error.httpStatus, 400);
      expect(error.field, 'limit');
    });

    test('a search-index 400 is a badRequest without a field', () async {
      final (client, _) = makeClient((_) => resp(
          '{"message":"Attribute `name` is not filterable.","code":"invalid_search_filter","type":"invalid_request"}',
          status: 400));
      final result = await client.stops.search(const StopFilter(name: 'M'));
      final error = (result as Failure<List<Stop>>).error;
      expect(error.code, SpiderErrorCode.badRequest);
      expect(error.serverCode, 'invalid_search_filter');
      expect(error.field, isNull);
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
      expect(body['limit'], 20);
    });

    test('within composes a geoBoundingBox filter (max corner, then min)',
        () async {
      final (client, mock) = makeClient((_) => resp('{"hits":[]}'));
      await client.stops.within(49.18, 16.59, 49.21, 16.63);
      final body = bodyOf(mock.requests[0]);
      expect(body['filter'], '_geoBoundingBox([49.21, 16.63], [49.18, 16.59])');
      expect(body.containsKey('sort'), false);
      expect(body['limit'], 20);
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

    test('vehicles keeps feed-prefixed ids as the service sends them',
        () async {
      const body =
          '{"vehicles":[{"tripId":"1:T1","routeId":"1:R1","vehicleId":"1:V7","stopId":"1:S1"}],"missing":[]}';
      final (client, _) = makeClient((_) => resp(body));
      final result = await client.realtime.vehicles(['1:T1']);
      final vehicle = (result as Success<VehiclePositions>).value.vehicles[0];
      expect(vehicle.vehicleId, '1:V7');
      expect(vehicle.tripId, '1:T1');
      expect(vehicle.stopId, '1:S1');
    });

    test('vehicles with no trip ids is an empty success without a request',
        () async {
      final (client, mock) = makeClient((_) => resp('{}'));
      final result = await client.realtime.vehicles(const []);
      final positions = (result as Success<VehiclePositions>).value;
      expect(positions.vehicles, isEmpty);
      expect(positions.missing, isEmpty);
      expect(positions.freshness.feedTimestampEpochMs, isNull);
      expect(mock.requests, isEmpty);
    });

    test('vehicles takes up to 50 trip ids and rejects more without a request',
        () async {
      final (client, mock) = makeClient((_) => resp('{}'));
      final result =
          await client.realtime.vehicles(List.generate(51, (i) => '1:T$i'));
      final error = (result as Failure<VehiclePositions>).error;
      expect(error.code, SpiderErrorCode.badRequest);
      expect(error.field, 'tripIds');
      expect(error.message, 'tripIds is out of range');
      expect(mock.requests, isEmpty);
      final (okClient, okMock) = makeClient((_) => resp('{"vehicles":[]}'));
      await okClient.realtime.vehicles(List.generate(50, (i) => '1:T$i'));
      expect(okMock.requests, hasLength(1));
    });

    test('a realtime 400 is a badRequest naming the field', () async {
      final (client, _) =
          makeClient((_) => resp('tripIds is out of range', status: 400));
      final result = await client.realtime.vehicles(['1:T1']);
      final error = (result as Failure<VehiclePositions>).error;
      expect(error.code, SpiderErrorCode.badRequest);
      expect(error.field, 'tripIds');
    });

    test('a vehicleForTrip 400 is a badRequest naming the field', () async {
      final (client, _) =
          makeClient((_) => resp('tripId is invalid', status: 400));
      final result = await client.realtime.vehicleForTrip('T1');
      final error = (result as Failure<LiveVehicleUpdate>).error;
      expect(error.code, SpiderErrorCode.badRequest);
      expect(error.field, 'tripId');
    });

    test('vehicleForTrip 404 is a soft null', () async {
      final (client, _) = makeClient((_) => resp('{}', status: 404));
      final result = await client.realtime.vehicleForTrip('T1');
      expect((result as Success<LiveVehicleUpdate>).value.vehicle, isNull);
    });

    test('delays posts grouped queries and resolves per (tripId, serviceDate)',
        () async {
      const body =
          '{"results":[{"serviceDate":"2026-07-15","delays":[{"tripId":"T1","routeId":"R1","delaySeconds":120,"scheduleRelationship":"SCHEDULED","stopTimeUpdates":[{"stopId":"S1","stopSequence":3,"arrivalDelay":120,"departureDelay":90}]}],"missing":["T2"]}],"feedTimestamp":1700000000,"staleSeconds":2.0}';
      final (client, mock) = makeClient((_) => resp(body));
      final result = await client.realtime.delays(['T1', 'T2'], '2026-07-15');
      final delays = (result as Success<TripDelays>).value;

      final req = mock.requests[0];
      expect(req.method, 'POST');
      expect(req.uri.path, '/realtime/delays');
      expect(bodyOf(req)['queries'], [
        {
          'serviceDate': '2026-07-15',
          'tripIds': ['T1', 'T2']
        }
      ]);

      final d = delays.delayFor('T1', '2026-07-15');
      expect(d?.delaySeconds, 120);
      expect(d?.stopTimeUpdates.first.arrivalDelay, 120);
      expect(delays.groups.single.missing, ['T2']);
      expect(delays.freshness.feedTimestampEpochMs, 1700000000 * 1000);
      // The same trip id on another service date is a different instance.
      expect(delays.delayFor('T1', '2026-07-16'), isNull);
    });

    test('delays with no trip ids is an empty success without a request',
        () async {
      for (final groups in [
        <String, List<String>>{},
        {'2026-07-15': <String>[]},
        {'2026-07-15': <String>[], '2026-07-16': <String>[]},
      ]) {
        final (client, mock) = makeClient((_) => resp('{}'));
        final result = await client.realtime.delaysByServiceDate(groups);
        final delays = (result as Success<TripDelays>).value;
        expect(delays.groups, isEmpty);
        expect(delays.freshness.feedTimestampEpochMs, isNull);
        expect(mock.requests, isEmpty);
      }
      final (client, mock) = makeClient((_) => resp('{}'));
      final result = await client.realtime.delays(const [], '2026-07-15');
      expect(result, isA<Success<TripDelays>>());
      expect(mock.requests, isEmpty);
    });

    test('delays counts trip ids across all service dates', () async {
      List<String> ids(int n, String p) => List.generate(n, (i) => '$p$i');
      final (overClient, overMock) = makeClient((_) => resp('{}'));
      final over = await overClient.realtime.delaysByServiceDate(
          {'2026-07-15': ids(30, 'A'), '2026-07-16': ids(21, 'B')});
      final error = (over as Failure<TripDelays>).error;
      expect(error.code, SpiderErrorCode.badRequest);
      expect(error.field, 'tripIds');
      expect(error.message, 'tripIds is out of range');
      expect(overMock.requests, isEmpty);
      final (client, mock) = makeClient((_) => resp('{"results":[]}'));
      final result = await client.realtime.delaysByServiceDate(
          {'2026-07-15': ids(25, 'A'), '2026-07-16': ids(25, 'B')});
      expect(result, isA<Success<TripDelays>>());
      expect(mock.requests, hasLength(1));
    });

    test('delays rejects a malformed service date without a request', () async {
      final (client, mock) = makeClient((_) => resp('{}'));
      final result = await client.realtime.delaysByServiceDate({
        '2026-07-15': ['T1'],
        '20260716': ['T2'],
      });
      final error = (result as Failure<TripDelays>).error;
      expect(error.code, SpiderErrorCode.badRequest);
      expect(error.field, 'serviceDate');
      expect(error.message, 'serviceDate is invalid');
      expect(mock.requests, isEmpty);
    });
  });

  group('warmup', () {
    test(
        'issues one apikey-authenticated GET to /ping and returns the elapsed duration',
        () async {
      final (client, mock) = makeClient((_) => resp('pong'));
      final elapsed = await client.warmup();
      expect(elapsed, isA<Duration>());
      expect(mock.requests.length, 1);
      final req = mock.requests[0];
      expect(req.method, 'GET');
      expect(req.uri.path, '/ping');
      expect(req.headers['apikey'], 'secret-key');
      expect(req.body, isNull);
    });

    test(
        'treats a non-2xx (404 before the route deploys) as a warmed '
        'connection, not a failure', () async {
      final (client, mock) = makeClient((_) => resp('not found', status: 404));
      final elapsed = await client.warmup();
      expect(elapsed, isA<Duration>());
      expect(mock.requests.length, 1);
    });

    test('never throws when the request fails outright', () async {
      final (client, _) = makeClient((_) => throw Exception('connection down'));
      final elapsed = await client.warmup();
      expect(elapsed, isA<Duration>());
    });
  });

  group('enums and polyline', () {
    test('open and closed enum mapping', () {
      expect(TransitMode.fromWire('BUS'), TransitMode.bus);
      expect(TransitMode.fromWire('SOMETHING_NEW'), TransitMode.unknown);
      expect(TransitMode.fromWire(null), isNull);
      expect(
          WheelchairBoarding.fromWire('POSSIBLE'), WheelchairBoarding.possible);
      expect(WheelchairBoarding.fromWire('NO_INFORMATION'), isNull);
      expect(WheelchairBoarding.fromWire(null), isNull);
      expect(WheelchairBoarding.fromWire('SOMETHING_NEW'),
          WheelchairBoarding.unknown);
      expect(BikesAllowed.fromWire('ALLOWED'), BikesAllowed.allowed);
      expect(BikesAllowed.fromWire('NO_INFORMATION'), isNull);
      expect(BikesAllowed.fromWire('SOMETHING_NEW'), BikesAllowed.unknown);
      expect(OccupancyStatus.fromWire('NO_DATA_AVAILABLE'), isNull);
      expect(OccupancyStatus.fromWire('WEIRD'), OccupancyStatus.unknown);
      expect(RealtimeState.fromWire('UPDATED'), RealtimeState.updated);
      expect(RealtimeState.fromWire('SOMETHING_NEW'), RealtimeState.unknown);
      expect(RoutingErrorCode.fromWire('OUTSIDE_BOUNDS'),
          RoutingErrorCode.outsideBounds);
      expect(
          RoutingErrorCode.fromWire('SOMETHING_NEW'), RoutingErrorCode.unknown);
      expect(InputField.fromWire('VIA'), InputField.via);
      expect(InputField.fromWire('FROM_PLACE'), InputField.unknown);
    });

    test('an unknown wire value decodes to unknown through the plan mapping',
        () {
      const data = '{ "hasNextPage": false, "hasPreviousPage": false, '
          '"routingErrors": [{ "code": "SOMETHING_NEW", "inputField": "SOMEWHERE", "description": "x" }] }';
      final done = parsePlanStreamRecord('pageInfo', data) as PlanStreamDone;
      expect(done.routingErrors.single.code, RoutingErrorCode.unknown);
      expect(done.routingErrors.single.inputField, InputField.unknown);
      const chunk =
          '{"results":[{"numberOfTransfers":0,"legs":[{"mode":"HOVERCRAFT",'
          '"realtimeState":"SOMETHING_NEW","start":{"scheduledTime":"t"},"end":{"scheduledTime":"t"},'
          '"from":{"name":"A"},"to":{"name":"B"}}]}]}';
      final leg = (parsePlanStreamRecord('chunk', chunk) as PlanStreamResult)
          .itineraries
          .single
          .legs
          .single;
      expect(leg.mode, TransitMode.unknown);
      expect(leg.realtimeState, RealtimeState.unknown);
    });

    test('wheelchair and bikes decode unknown and NO_INFORMATION in the models',
        () async {
      const data = '{"results":[{"numberOfTransfers":0,"legs":['
          '{"start":{"scheduledTime":"t"},"end":{"scheduledTime":"t"},'
          '"from":{"name":"A","stop":{"gtfsId":"1:A","wheelchairBoarding":"RAMP_ONLY"}},'
          '"to":{"name":"B","stop":{"gtfsId":"1:B","wheelchairBoarding":"NO_INFORMATION"}},'
          '"trip":{"gtfsId":"1:T","bikesAllowed":"FOLDING_ONLY"}},'
          '{"start":{"scheduledTime":"t"},"end":{"scheduledTime":"t"},'
          '"from":{"name":"B"},"to":{"name":"C"},'
          '"trip":{"gtfsId":"1:T2","bikesAllowed":"NO_INFORMATION"}}'
          ']}]}';
      final legs = (parsePlanStreamRecord('chunk', data) as PlanStreamResult)
          .itineraries
          .single
          .legs;
      expect(legs[0].fromWheelchair, WheelchairBoarding.unknown);
      expect(legs[0].toWheelchair, isNull);
      expect(legs[0].bikesAllowed, BikesAllowed.unknown);
      expect(legs[1].bikesAllowed, isNull);

      final (client, _) = makeClient((_) => resp(
          '{"data":{"trip":{"gtfsId":"T1","wheelchairAccessible":"SOMETHING_NEW",'
          '"route":{"gtfsId":"R1"},"stoptimesForDate":[]}}}'));
      final trip =
          ((await client.routing.trip('T1')) as Success<TripDetails>).value;
      expect(trip.wheelchairAccessible, WheelchairBoarding.unknown);
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
      expect(client.contractVersion, contractVersion);
    });
  });

  group('plan-stream', () {
    // A `chunk` carries itinerary nodes; realtime delays ride on each leg's estimated{time,delay} +
    // realtimeState + realTime + serviceDate and must land on the domain Leg exactly as the batch plan maps.
    test('chunk maps itineraries with realtime delays', () {
      const data = '''
        {
          "results": [
            {
              "numberOfTransfers": 1,
              "start": "2026-07-15T08:00:00Z", "end": "2026-07-15T08:30:00Z", "duration": 1800,
              "legs": [
                {
                  "mode": "BUS",
                  "start": { "scheduledTime": "2026-07-15T08:00:00Z", "estimated": { "time": "2026-07-15T08:01:00Z", "delay": "PT60S" } },
                  "end":   { "scheduledTime": "2026-07-15T08:30:00Z", "estimated": { "time": "2026-07-15T08:32:00Z", "delay": "PT120S" } },
                  "realtimeState": "UPDATED", "realTime": true, "serviceDate": "2026-07-15",
                  "from": { "name": "Origin", "stop": { "gtfsId": "1:A" } },
                  "to":   { "name": "Dest",   "stop": { "gtfsId": "1:B" } },
                  "route": { "gtfsId": "1:R12", "shortName": "12" }, "trip": { "gtfsId": "1:T" }
                }
              ]
            }
          ]
        }
      ''';
      final event = parsePlanStreamRecord('chunk', data);
      expect(event, isA<PlanStreamResult>());
      final result = event as PlanStreamResult;

      final itinerary = result.itineraries.single;
      expect(itinerary.numberOfTransfers, 1);
      expect(itinerary.durationSeconds, 1800);

      final leg = itinerary.legs.single;
      expect(leg.mode, TransitMode.bus);
      expect(leg.startDelay, const Duration(seconds: 60));
      expect(leg.endDelay, const Duration(seconds: 120));
      expect(leg.startEstimated, '2026-07-15T08:01:00Z');
      expect(leg.isRealtime, true);
      expect(leg.realtimeState, RealtimeState.updated);
      expect(leg.serviceDate, '2026-07-15');
      expect(leg.fromGtfsId, '1:A');
      expect(leg.toGtfsId, '1:B');
      expect(leg.routeGtfsId, '1:R12');
      // Absent display fields stay null.
      expect(leg.routeColor, isNull);
      expect(leg.routeTextColor, isNull);
      expect(leg.fromPlatformCode, isNull);
      expect(leg.toZoneId, isNull);
    });

    // The `pageInfo` frame is the terminal event: it maps to PlanStreamDone carrying the continuation cursors.
    test('pageInfo maps to a terminal Done with continuation cursors', () {
      const data =
          '{ "startCursor": "c-prev", "endCursor": "c-next", "hasNextPage": true, "hasPreviousPage": false, "searchWindowUsed": "PT1H" }';
      final event = parsePlanStreamRecord('pageInfo', data);
      expect(event, isA<PlanStreamDone>());
      final page = (event as PlanStreamDone).pageInfo;
      expect(page.startCursor, 'c-prev');
      expect(page.endCursor, 'c-next');
      expect(page.hasNextPage, true);
      expect(page.hasPreviousPage, false);
      expect(page.searchWindowUsed, 'PT1H');
      expect(event.routingErrors, isEmpty);
    });

    // Routing outcomes ride on the terminal pageInfo, shaped like batch planConnection's routingErrors.
    test('pageInfo carries routing errors on the terminal Done', () {
      const data = '{ "hasNextPage": false, "hasPreviousPage": false, '
          '"routingErrors": ['
          '{ "code": "OUTSIDE_SERVICE_PERIOD", "inputField": "DATE_TIME", "description": "outside the feed" },'
          '{ "code": "LOCATION_NOT_FOUND", "inputField": "FROM", "description": "unknown stop" }'
          '] }';
      final event = parsePlanStreamRecord('pageInfo', data) as PlanStreamDone;
      expect(event.routingErrors.length, 2);
      expect(
          event.routingErrors[0].code, RoutingErrorCode.outsideServicePeriod);
      expect(event.routingErrors[0].inputField, InputField.dateTime);
      expect(event.routingErrors[0].description, 'outside the feed');
      expect(event.routingErrors[1].code, RoutingErrorCode.locationNotFound);
      expect(event.routingErrors[1].inputField, InputField.from);
    });

    // The old `done` telemetry frame is no longer surfaced — it just ends the stream.
    test('done telemetry is ignored', () {
      const data =
          '{ "iterations": 3, "windowSeconds": 3600, "resultCount": 5, "stoppedBy": "targetResults" }';
      expect(parsePlanStreamRecord('done', data), isNull);
    });

    // A stream `error` record is the GraphQL error envelope; a top-level BAD_REQUEST becomes a typed badRequest.
    test('error event maps to a typed badRequest failure', () {
      const data =
          '{ "data": null, "errors": [ { "message": "maxWindow is out of range", "extensions": { "code": "BAD_REQUEST", "field": "maxWindow" } } ] }';
      final event = parsePlanStreamRecord('error', data);
      expect(event, isA<PlanStreamFailure>());
      final error = (event as PlanStreamFailure).error;
      expect(error.code, SpiderErrorCode.badRequest);
      expect(error.field, 'maxWindow');
      expect(error.message, 'maxWindow is out of range');
    });

    test('heartbeats and unknown events are ignored', () {
      expect(parsePlanStreamRecord('message', ''), isNull);
      expect(parsePlanStreamRecord('weird', '{ "x": 1 }'), isNull);
    });

    // Pins the stream request wire shape (targetResults/maxWindow + via, nulls omitted) so a contract regen
    // can't silently rename or reorder the fields the SDK sends to /routing/plan-stream.
    test('stream variables serialize to the plan-stream wire shape', () {
      final variables = wire.PlanConnectionStreamVariables(
        dateTime:
            wire.PlanDateTimeInput(earliestDeparture: '2026-07-15T08:00:00Z'),
        origin: wire.PlanLabeledLocationInput(
            location: wire.PlanLocationInput(
                stopLocation:
                    wire.PlanStopLocationInput(stopLocationId: '1:A'))),
        destination: wire.PlanLabeledLocationInput(
            location: wire.PlanLocationInput(
                coordinate:
                    wire.PlanCoordinateInput(latitude: 49.2, longitude: 16.6))),
        via: [
          wire.PlanViaLocationInput(
              passThrough: wire.PlanPassThroughViaLocationInput(
                  stopLocationIds: ['1:V']))
        ],
        targetResults: 5,
        maxWindow: 'PT3H',
      );
      expect(variables.toJson(), {
        'dateTime': {'earliestDeparture': '2026-07-15T08:00:00Z'},
        'origin': {
          'location': {
            'stopLocation': {'stopLocationId': '1:A'}
          }
        },
        'destination': {
          'location': {
            'coordinate': {'latitude': 49.2, 'longitude': 16.6}
          }
        },
        'via': [
          {
            'passThrough': {
              'stopLocationIds': ['1:V']
            }
          }
        ],
        'targetResults': 5,
        'maxWindow': 'PT3H',
      });
    });

    test(
        'planStream emits Result then a terminal Done over SSE (dropping the '
        'done telemetry) and sends the id + apikey, no cursors', () async {
      const frames = 'event: chunk\n'
          'data: {"frontier":1800,"found":1,"finalized":1,"results":[{"numberOfTransfers":0,"duration":600,"legs":[{"mode":"BUS","start":{"scheduledTime":"2026-07-15T08:00:00Z"},"end":{"scheduledTime":"2026-07-15T08:10:00Z"},"from":{"name":"A"},"to":{"name":"B"}}]}]}\n'
          '\n'
          ': heartbeat\n'
          '\n'
          'event: pageInfo\n'
          'data: {"endCursor":"c-next","hasNextPage":true}\n'
          '\n'
          'event: done\n'
          'data: {"iterations":1,"windowSeconds":1800,"resultCount":1,"stoppedBy":"targetResults"}\n'
          '\n';
      final mock = MockHttpClient((_) => resp('{}'),
          streamHandler: (_) => SpiderHttpStreamedResponse(
              200,
              {'content-type': 'text/event-stream'},
              Stream.value(utf8.encode(frames))));
      final client = SpiderClient('https://env.api.example.com', 'secret-key',
          SpiderClientOptions(httpClient: mock));

      final events = await client.routing
          .planStream(stopsAB, targetResults: 4, maxWindowMinutes: 180)
          .toList();

      expect(events.length, 2);
      expect(events[0], isA<PlanStreamResult>());
      expect(
          (events[0] as PlanStreamResult).itineraries.single.legs.single.mode,
          TransitMode.bus);
      final done = events[1] as PlanStreamDone;
      expect(done.pageInfo.endCursor, 'c-next');
      expect(done.pageInfo.hasNextPage, true);

      final req = mock.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/routing/plan-stream');
      expect(req.headers['apikey'], 'secret-key');
      expect(req.headers['accept'], 'text/event-stream');
      final body = bodyOf(req);
      expect(body['id'], PersistedQueries.planstream.id);
      final vars = body['variables'] as Map<String, dynamic>;
      expect(vars.containsKey('after'), false);
      expect(vars.containsKey('before'), false);
      expect(vars['targetResults'], 4);
      expect(vars['maxWindow'], 'PT180M');
    });

    test('planStream rejects a max window under 2 h without a request',
        () async {
      for (final options in [
        stopsAB,
        PlanOptions(
            origin: const Location.stop('A'),
            destination: const Location.stop('B'),
            arriveBy: DateTime.utc(2026, 7, 15, 9)),
      ]) {
        final (client, mock) = makeStreamClient(200, '');
        final events = await client.routing
            .planStream(options, targetResults: 5, maxWindowMinutes: 119)
            .toList();
        final error = (events.single as PlanStreamFailure).error;
        expect(error.code, SpiderErrorCode.badRequest);
        expect(error.field, 'maxWindow');
        expect(error.message, 'maxWindow is out of range');
        expect(mock.requests, isEmpty);
      }
      final (client, mock) = makeStreamClient(200,
          'event: pageInfo\ndata: {"hasNextPage":false,"hasPreviousPage":false}\n\n');
      final events = await client.routing
          .planStream(stopsAB, targetResults: 5, maxWindowMinutes: 120)
          .toList();
      expect(events.single, isA<PlanStreamDone>());
      expect(varsOf(mock.requests.single)['maxWindow'], 'PT120M');
    });

    test('planStream checks via limits without a request', () async {
      final (client, mock) = makeStreamClient(200, '');
      final events = await client.routing
          .planStream(
              const PlanOptions(
                  origin: Location.stop('A'),
                  destination: Location.stop('B'),
                  via: [ViaLocation.passThrough([])]),
              targetResults: 5,
              maxWindowMinutes: 120)
          .toList();
      expect((events.single as PlanStreamFailure).error.field, 'via');
      expect(mock.requests, isEmpty);
    });

    test(
        'a 2xx JSON body instead of an event stream maps like batch '
        '(gateway missing-variable BAD_REQUEST)', () async {
      final (client, _) = makeStreamClient(
          200,
          '{"data":null,"errors":[{"message":"maxWindow is required",'
          '"extensions":{"code":"BAD_REQUEST","field":"maxWindow"}}]}',
          contentType: 'application/json');
      final events = await client.routing
          .planStream(stopsAB, targetResults: 5, maxWindowMinutes: 120)
          .toList();
      final error = (events.single as PlanStreamFailure).error;
      expect(error.code, SpiderErrorCode.badRequest);
      expect(error.field, 'maxWindow');
      expect(error.message, 'maxWindow is required');
    });

    test('a 2xx JSON body with no errors is a server failure', () async {
      final (client, _) = makeStreamClient(200, '{"data":null}',
          contentType: 'application/json; charset=utf-8');
      final events = await client.routing
          .planStream(stopsAB, targetResults: 5, maxWindowMinutes: 120)
          .toList();
      expect((events.single as PlanStreamFailure).error.code,
          SpiderErrorCode.server);
    });

    test('planStreamNext continues forward with after and repeats the request',
        () async {
      const frames = 'event: pageInfo\n'
          'data: {"startCursor":"c-prev","endCursor":"c-next2","hasNextPage":true,"hasPreviousPage":true}\n'
          '\n';
      final mock = MockHttpClient((_) => resp('{}'),
          streamHandler: (_) => SpiderHttpStreamedResponse(
              200,
              {'content-type': 'text/event-stream'},
              Stream.value(utf8.encode(frames))));
      final client = SpiderClient('https://env.api.example.com', 'secret-key',
          SpiderClientOptions(httpClient: mock));

      final events = await client.routing
          .planStreamNext(stopsAB,
              targetResults: 3, maxWindowMinutes: 240, after: 'c-next')
          .toList();

      expect(events.single, isA<PlanStreamDone>());
      expect((events.single as PlanStreamDone).pageInfo.hasPreviousPage, true);

      final vars =
          bodyOf(mock.requests.single)['variables'] as Map<String, dynamic>;
      expect(vars['after'], 'c-next');
      expect(vars.containsKey('before'), false);
      expect(vars['targetResults'], 3);
      expect(vars['maxWindow'], 'PT240M');
    });

    test('planStreamPrevious continues backward with before', () async {
      const frames = 'event: pageInfo\n'
          'data: {"startCursor":"c-prev2","endCursor":"c-next","hasNextPage":true,"hasPreviousPage":false}\n'
          '\n';
      final mock = MockHttpClient((_) => resp('{}'),
          streamHandler: (_) => SpiderHttpStreamedResponse(
              200,
              {'content-type': 'text/event-stream'},
              Stream.value(utf8.encode(frames))));
      final client = SpiderClient('https://env.api.example.com', 'secret-key',
          SpiderClientOptions(httpClient: mock));

      final events = await client.routing
          .planStreamPrevious(stopsAB,
              targetResults: 5, maxWindowMinutes: 120, before: 'c-prev')
          .toList();

      expect(events.single, isA<PlanStreamDone>());
      expect((events.single as PlanStreamDone).pageInfo.hasNextPage, true);

      final vars =
          bodyOf(mock.requests.single)['variables'] as Map<String, dynamic>;
      expect(vars['before'], 'c-prev');
      expect(vars.containsKey('after'), false);
    });

    test('planStream surfaces a non-2xx as a terminal failure', () async {
      final mock = MockHttpClient((_) => resp('{}'),
          streamHandler: (_) => SpiderHttpStreamedResponse(
              403,
              const {},
              Stream.value(
                  utf8.encode('{"code":"forbidden","message":"nope"}'))));
      final client = SpiderClient('https://env.api.example.com', 'secret-key',
          SpiderClientOptions(httpClient: mock));

      final events = await client.routing
          .planStream(stopsAB, targetResults: 5, maxWindowMinutes: 120)
          .toList();

      expect(events.single, isA<PlanStreamFailure>());
      expect((events.single as PlanStreamFailure).error.code,
          SpiderErrorCode.unauthorized);
    });

    test('planStream maps a retired persisted query to queryRetired', () async {
      final (client, _) = makeStreamClient(410,
          '{"error":"query_retired","message":"persisted query is retired"}',
          contentType: 'application/json');
      final events = await client.routing
          .planStream(stopsAB, targetResults: 5, maxWindowMinutes: 120)
          .toList();
      final error = (events.single as PlanStreamFailure).error;
      expect(error.code, SpiderErrorCode.queryRetired);
      expect(error.httpStatus, 410);
      expect(error.serverCode, 'query_retired');
      expect(error.message.toLowerCase(), isNot(contains('update')));
    });

    test('planStream keeps an unknown persisted-query id unauthorized',
        () async {
      final (client, _) = makeStreamClient(403,
          '{"error":"persisted_query_rejected","message":"unknown persisted-query id: abc"}',
          contentType: 'application/json');
      final events = await client.routing
          .planStream(stopsAB, targetResults: 5, maxWindowMinutes: 120)
          .toList();
      final error = (events.single as PlanStreamFailure).error;
      expect(error.code, SpiderErrorCode.unauthorized);
      expect(error.serverCode, 'persisted_query_rejected');
      expect(error.message, contains('unknown persisted-query id: abc'));
    });
  });

  group('plan limits', () {
    const limits = [
      (
        SpiderErrorCode.planningLimitReached,
        'planning_limit_reached',
        'trip planning limit reached'
      ),
      (
        SpiderErrorCode.agreementInactive,
        'agreement_inactive',
        'agreement is not active'
      ),
    ];

    String refusal(String code, String message) =>
        jsonEncode({'error': code, 'message': message});

    // Every buffered call, by surface. Each one here has to fail against the mock's response.
    final calls =
        <String, Future<SpiderResult<Object?>> Function(SpiderClient)>{
      'plan': (c) => c.routing.plan(stopsAB),
      'departures': (c) => c.routing.departures('S'),
      'trip': (c) => c.routing.trip('T1'),
      'stops.search': (c) => c.stops.search(const StopFilter(name: 'M')),
      'stops.byId': (c) => c.stops.byId('1:S1'),
      'realtime.vehicles': (c) => c.realtime.vehicles(['T1']),
      'realtime.vehicleForTrip': (c) => c.realtime.vehicleForTrip('T1'),
      'realtime.delays': (c) => c.realtime.delays(['T1'], '2026-07-15'),
      'realtime.alerts': (c) => c.realtime.alerts(),
    };

    Future<SpiderError> errorOf(
        String call, SpiderHttpResponse response) async {
      final (client, _) = makeClient((_) => response);
      final result = await calls[call]!(client);
      expect(result, isA<Failure<Object?>>(), reason: call);
      return result.errorOrNull!;
    }

    test('a 403 refusal maps to its code on every surface', () async {
      for (final (code, serverCode, message) in limits) {
        for (final call in calls.keys) {
          final error = await errorOf(
              call, resp(refusal(serverCode, message), status: 403));
          expect(error.code, code, reason: '$call $serverCode');
          expect(error.httpStatus, 403, reason: '$call $serverCode');
          expect(error.serverCode, serverCode, reason: '$call $serverCode');
          expect(error.message, message, reason: '$call $serverCode');
        }
      }
    });

    test('the body code wins over a rewritten status', () async {
      for (final (code, serverCode, message) in limits) {
        for (final status in [400, 401, 404, 410, 429, 500]) {
          for (final call in calls.keys) {
            final error = await errorOf(
                call, resp(refusal(serverCode, message), status: status));
            expect(error.code, code, reason: '$call $status $serverCode');
            expect(error.httpStatus, status,
                reason: '$call $status $serverCode');
            expect(error.serverCode, serverCode,
                reason: '$call $status $serverCode');
          }
        }
      }
    });

    test('a 403 without a plan-limit code stays unauthorized', () async {
      for (final body in [
        '',
        '{"error":"forbidden","message":"trip planning limit reached"}',
        '{"message":"agreement is not active"}',
      ]) {
        for (final call in calls.keys) {
          final error = await errorOf(call, resp(body, status: 403));
          expect(error.code, SpiderErrorCode.unauthorized,
              reason: '$call $body');
          expect(error.httpStatus, 403, reason: '$call $body');
        }
      }
    });

    test('the message is the body message', () async {
      final error = await errorOf(
          'departures',
          resp(refusal('agreement_inactive', 'agreement is not active (env)'),
              status: 403));
      expect(error.message, 'agreement is not active (env)');
    });

    test('a refusal without a message keeps the code and its own message',
        () async {
      for (final (code, serverCode, message) in limits) {
        final error = await errorOf(
            'plan', resp(jsonEncode({'error': serverCode}), status: 403));
        expect(error.code, code);
        expect(error.message, message);
      }
    });

    test('planStream maps a refusal before the stream starts', () async {
      for (final (code, serverCode, message) in limits) {
        final (client, _) = makeStreamClient(403, refusal(serverCode, message),
            contentType: 'application/json');
        final events = await client.routing
            .planStream(stopsAB, targetResults: 5, maxWindowMinutes: 120)
            .toList();
        final error = (events.single as PlanStreamFailure).error;
        expect(error.code, code);
        expect(error.httpStatus, 403);
        expect(error.serverCode, serverCode);
        expect(error.message, message);
      }
    });

    test('planStream keeps a plain 403 unauthorized', () async {
      final (client, _) =
          makeStreamClient(403, '', contentType: 'application/json');
      final events = await client.routing
          .planStream(stopsAB, targetResults: 5, maxWindowMinutes: 120)
          .toList();
      expect((events.single as PlanStreamFailure).error.code,
          SpiderErrorCode.unauthorized);
    });
  });
}
