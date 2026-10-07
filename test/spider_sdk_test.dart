import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:spider_sdk/spider_sdk.dart';
import 'package:spider_sdk/src/contract/contract_version.dart'
    show contractVersion;
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

// Contract 1.3 response builders: every member is required (nullable ones explicitly null), so a fixture
// spreads its overrides over a complete base.
typedef Json = Map<String, dynamic>;

Json stopJson(String gtfsId, [Json o = const {}]) => {
      'gtfsId': gtfsId,
      'wheelchairBoarding': 'NO_INFORMATION',
      'platformCode': '1',
      'zoneId': 'P',
      ...o,
    };

Json routeJson(String gtfsId, [Json o = const {}]) => {
      'gtfsId': gtfsId,
      'shortName': '12',
      'longName': 'Line 12',
      'color': 'FF0000',
      'textColor': 'FFFFFF',
      ...o,
    };

Json legJson([Json o = const {}]) => {
      'mode': 'BUS',
      'start': {'scheduledTime': '2026-08-21T10:00:00Z', 'estimated': null},
      'end': {'scheduledTime': '2026-08-21T10:15:00Z', 'estimated': null},
      'typicalArrivalDelay': 0,
      'realtimeState': 'SCHEDULED',
      'realTime': false,
      'serviceDate': '2026-08-21',
      'from': {'name': 'A', 'stop': stopJson('1:S1')},
      'to': {'name': 'B', 'stop': stopJson('1:S2')},
      'route': routeJson('1:R12'),
      'headsign': 'Downtown',
      'distance': 1500.0,
      'duration': 900,
      'trip': {'gtfsId': '1:T1', 'bikesAllowed': 'NO_INFORMATION'},
      'interlineWithPreviousLeg': false,
      'legGeometry': {'points': '_p~iF~ps|U'},
      ...o,
    };

Json itineraryJson(List<Json> legs, [Json o = const {}]) => {
      'start': '2026-08-21T10:00:00Z',
      'end': '2026-08-21T10:30:00Z',
      'duration': 1800,
      'waitingTime': 0,
      'numberOfTransfers': legs.length > 1 ? legs.length - 1 : 0,
      'legs': legs,
      ...o,
    };

Json pageInfoJson([Json o = const {}]) => {
      'startCursor': 'c0',
      'endCursor': 'c1',
      'hasNextPage': false,
      'hasPreviousPage': false,
      'searchWindowUsed': 'PT60M',
      ...o,
    };

String planJson(
        {List<Json> itineraries = const [],
        Json pageInfo = const {},
        List<Json> routingErrors = const []}) =>
    jsonEncode({
      'itineraries': itineraries,
      'pageInfo': pageInfoJson(pageInfo),
      'routingErrors': routingErrors,
      'searchDateTime': '2026-08-21T10:00:00Z',
    });

String chunkJson(List<Json> itineraries) => jsonEncode({
      'frontier': 1800,
      'found': itineraries.length,
      'finalized': itineraries.length,
      'results': itineraries,
    });

String streamPageInfoJson(
        [Json o = const {}, List<Json> routingErrors = const []]) =>
    jsonEncode({...pageInfoJson(o), 'routingErrors': routingErrors});

Json stoptimeJson(String tripId, [Json o = const {}]) => {
      'serviceDay': 1784066400,
      'scheduledDeparture': 36000,
      'realtimeDeparture': 36000,
      'realtime': false,
      'realtimeState': 'SCHEDULED',
      'typicalDelay': 0,
      'headsign': 'Airport',
      'stop': {'gtfsId': '1:ST-P1', 'platformCode': '1'},
      'trip': {
        'gtfsId': tripId,
        'bikesAllowed': 'NO_INFORMATION',
        'wheelchairAccessible': 'NO_INFORMATION',
        'route': routeJson('1:R12', {'mode': 'BUS'}),
      },
      ...o,
    };

String departuresJson(List<Json> stoptimes, [Json o = const {}]) => jsonEncode({
      'stop': {
        'gtfsId': '1:ST',
        'name': 'Central',
        'wheelchairBoarding': null,
        'stoptimesWithoutPatterns': stoptimes,
        ...o,
      }
    });

Json tripStoptimeJson(String stopId,
        [Json o = const {}, Json stop = const {}]) =>
    {
      'serviceDay': 1787263200,
      'scheduledArrival': 36000,
      'scheduledDeparture': 36000,
      'realtimeArrival': 36000,
      'realtimeDeparture': 36000,
      'realtime': false,
      'realtimeState': 'SCHEDULED',
      'typicalDelay': 0,
      'stop': {
        'gtfsId': stopId,
        'name': 'A',
        'lat': 49.19,
        'lon': 16.61,
        'wheelchairBoarding': 'NO_INFORMATION',
        'platformCode': '1',
        'zoneId': 'P',
        ...stop,
      },
      ...o,
    };

String tripJson(List<Json> stoptimes, [Json o = const {}]) => jsonEncode({
      'trip': {
        'gtfsId': '1:T1',
        'directionId': '0',
        'tripHeadsign': 'Airport',
        'bikesAllowed': 'NO_INFORMATION',
        'wheelchairAccessible': 'NO_INFORMATION',
        'route': routeJson('1:R12', {'mode': 'BUS'}),
        'stoptimesForDate': stoptimes,
        'tripGeometry': null,
        ...o,
      }
    });

final emptyPlanBody = planJson();

final planBody = planJson(itineraries: [
  itineraryJson([
    legJson({
      'from': {
        'name': 'A',
        'stop': stopJson('1:S1', {'wheelchairBoarding': 'POSSIBLE'})
      },
      'to': {
        'name': 'B',
        'stop': stopJson('1:S2', {
          'wheelchairBoarding': 'NOT_POSSIBLE',
          'platformCode': 'B2',
          'zoneId': '0'
        })
      },
      'trip': {'gtfsId': '1:T1', 'bikesAllowed': 'ALLOWED'},
      'legGeometry': {'points': '_p~iF~ps|U_ulLnnqC_mqNvxq`@'},
    })
  ], {
    'waitingTime': 120,
    'numberOfTransfers': 1
  })
], pageInfo: {
  'hasNextPage': true,
  'startCursor': 'c1',
  'endCursor': 'c1'
});

final pageInfoFrame = 'event: pageInfo\ndata: ${streamPageInfoJson()}\n\n';

void main() {
  group('routing', () {
    test('plan posts the REST body with headers and maps the route', () async {
      final (client, mock) = makeClient((_) => resp(planBody));
      final result = await client.routing.plan(const PlanOptions(
        origin: Location.coordinate(49.19, 16.61),
        destination: Location.coordinate(49.22, 16.52),
      ));
      expect(result, isA<Success<Route>>());
      final route = (result as Success<Route>).value;
      expect(route.edges.length, 1);
      expect(route.edges[0].cursor, 'NoCursor');
      expect(route.edges[0].itinerary.accessibilityScore, isNull);
      expect(route.searchDateTime, '2026-08-21T10:00:00Z');
      final leg = route.edges[0].itinerary.legs[0];
      expect(leg.accessibilityScore, isNull);
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
      expect(req.uri.path, '/routing/v1/plan');
      expect(req.method, 'POST');
      expect(req.headers['apikey'], 'secret-key');
      expect(req.headers['x-spider-contract-version'], contractVersion);
      expect(req.headers['x-spider-sdk'], 'dart/$sdkVersion');
      expect(req.headers['content-type'], 'application/json');
      final body = bodyOf(req);
      expect(body.containsKey('id'), false);
      expect(body.containsKey('variables'), false);
      expect(body.containsKey('first'), false);
      expect(body.containsKey('last'), false);
      expect(body['searchWindow'], 'PT60M');
      expect((body['dateTime'] as Map)['earliestDeparture'], isNotNull);
      expect((body['dateTime'] as Map)['latestArrival'], isNull);
    });

    test('plan sends the contract PlanTripRequest body', () async {
      final (client, mock) = makeClient((_) => resp(planBody));
      await client.routing.plan(PlanOptions(
        origin: const Location.coordinate(49.19, 16.61),
        destination: const Location.stop('1:B'),
        departAt: DateTime.utc(2026, 10, 7, 6),
        via: const [
          ViaLocation.passThrough(['1:V']),
          ViaLocation.visit(Location.stop('1:W'), minimumWaitSeconds: 300),
        ],
        allowedTransitModes: const [TransitMode.bus],
        maxTransfers: 1,
        searchWindowMinutes: 90,
        wheelchairAccessible: true,
        reliability: Reliability.safe,
      ));
      expect(bodyOf(mock.requests.single), {
        'dateTime': {'earliestDeparture': '2026-10-07T06:00:00.000Z'},
        'origin': {
          'location': {
            'coordinate': {'latitude': 49.19, 'longitude': 16.61}
          }
        },
        'destination': {
          'location': {
            'stopLocation': {'stopLocationId': '1:B'}
          }
        },
        'searchWindow': 'PT90M',
        'via': [
          {
            'passThrough': {
              'stopLocationIds': ['1:V']
            }
          },
          {
            'visit': {
              'stopLocationIds': ['1:W'],
              'minimumWaitTime': 'PT300S'
            }
          },
        ],
        'modes': {
          'transit': {
            'transit': [
              {'mode': 'BUS'}
            ]
          }
        },
        'preferences': {
          'transit': {
            'transfer': {'maximumTransfers': 2}
          },
          'accessibility': {
            'wheelchair': {'enabled': true}
          },
        },
        'reliability': 'SAFE',
      });
    });

    test('plan with no filters omits modes/preferences (null-omission)',
        () async {
      final (client, mock) = makeClient((_) => resp(planBody));
      await client.routing.plan(const PlanOptions(
          origin: Location.stop('S1'), destination: Location.stop('S2')));
      final vars = bodyOf(mock.requests[0]);
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
      final vars = bodyOf(mock.requests[0]);
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

    test('plan sends reliability only when set', () async {
      for (final (reliability, expected) in [
        (Reliability.standard, 'STANDARD'),
        (Reliability.safe, 'SAFE'),
        (Reliability.verySafe, 'VERY_SAFE'),
      ]) {
        final (client, mock) = makeClient((_) => resp(planBody));
        await client.routing.plan(PlanOptions(
            origin: const Location.stop('S1'),
            destination: const Location.stop('S2'),
            reliability: reliability));
        expect(bodyOf(mock.requests.single)['reliability'], expected);
      }
      final (client, mock) = makeClient((_) => resp(planBody));
      await client.routing.plan(stopsAB);
      expect(bodyOf(mock.requests.single).containsKey('reliability'), false);
    });

    test('plan maps the typical arrival delay and the interline flag',
        () async {
      final body = planJson(itineraries: [
        itineraryJson([
          legJson({'typicalArrivalDelay': 90}),
          legJson(
              {'typicalArrivalDelay': null, 'interlineWithPreviousLeg': true}),
          legJson({
            'mode': 'WALK',
            'typicalArrivalDelay': null,
            'serviceDate': null,
            'route': null,
            'headsign': null,
            'trip': null,
          }),
        ])
      ]);
      final (client, _) = makeClient((_) => resp(body));
      final result = await client.routing.plan(const PlanOptions(
          origin: Location.stop('A'),
          destination: Location.stop('D'),
          reliability: Reliability.standard));
      final legs = (result as Success<Route>).value.edges.single.itinerary.legs;
      expect(legs[0].typicalArrivalDelay, const Duration(seconds: 90));
      expect(legs[0].interlineWithPreviousLeg, false);
      expect(legs[1].typicalArrivalDelay, isNull);
      expect(legs[1].interlineWithPreviousLeg, true);
      expect(legs[2].typicalArrivalDelay, isNull);
      expect(legs[2].interlineWithPreviousLeg, false);
    });

    test('plan with arriveBy sets latestArrival', () async {
      final (client, mock) = makeClient((_) => resp(planBody));
      await client.routing.plan(PlanOptions(
        origin: const Location.stop('S1'),
        destination: const Location.stop('S2'),
        arriveBy:
            DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true),
      ));
      final dt = bodyOf(mock.requests[0])['dateTime'] as Map;
      expect(dt['latestArrival'], isNotNull);
      expect(dt['earliestDeparture'], isNull);
    });

    test('planNext sends the same body plus after', () async {
      final page2 = planJson(pageInfo: {
        'hasPreviousPage': true,
        'startCursor': 'c2',
        'endCursor': 'c2'
      });
      final (client, mock) = makeClient(
          (req) => resp(bodyOf(req)['after'] == 'c1' ? page2 : planBody));
      final first = await client.routing.plan(PlanOptions(
          origin: const Location.stop('A'),
          destination: const Location.stop('B'),
          departAt: DateTime.utc(2026, 10, 7, 6)));
      final next =
          await client.routing.planNext((first as Success<Route>).value);
      expect((next as Success<Route>).value.pageInfo.startCursor, 'c2');
      expect(bodyOf(mock.requests[1]),
          {...bodyOf(mock.requests[0]), 'after': 'c1'});
    });

    test('planPrevious sends the same body plus before', () async {
      final both =
          planJson(pageInfo: {'hasNextPage': true, 'hasPreviousPage': true});
      final (client, mock) = makeClient((_) => resp(both));
      final first = await client.routing.plan(PlanOptions(
          origin: const Location.stop('A'),
          destination: const Location.stop('B'),
          departAt: DateTime.utc(2026, 10, 7, 6)));
      await client.routing.planPrevious((first as Success<Route>).value);
      expect(bodyOf(mock.requests[1]),
          {...bodyOf(mock.requests[0]), 'before': 'c0'});
    });

    test('planNext and planPrevious repeat the reliability', () async {
      final both =
          planJson(pageInfo: {'hasNextPage': true, 'hasPreviousPage': true});
      final (client, mock) = makeClient((_) => resp(both));
      final first = await client.routing.plan(const PlanOptions(
          origin: Location.stop('A'),
          destination: Location.stop('B'),
          reliability: Reliability.safe));
      final route = (first as Success<Route>).value;
      await client.routing.planNext(route);
      await client.routing.planPrevious(route);
      expect(mock.requests.map((r) => bodyOf(r)['reliability']).toList(),
          ['SAFE', 'SAFE', 'SAFE']);
      expect(bodyOf(mock.requests[1])['after'], 'c1');
      expect(bodyOf(mock.requests[2])['before'], 'c0');
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

    test('a routing 400 is a badRequest naming the body field', () async {
      final (client, _) = makeClient((_) => resp(
          '{"code":"bad_request","message":"preferences.street.bicycle is not allowed",'
          '"field":"preferences.street.bicycle"}',
          status: 400));
      final result = await client.routing.plan(stopsAB);
      final error = (result as Failure<Route>).error;
      expect(error.code, SpiderErrorCode.badRequest);
      expect(error.httpStatus, 400);
      expect(error.serverCode, 'bad_request');
      expect(error.field, 'preferences.street.bicycle');
      expect(error.message,
          'POST /routing/v1/plan -> 400: preferences.street.bicycle is not allowed');
    });

    test('the body field wins over the field the message names', () async {
      final (client, _) = makeClient((_) => resp(
          '{"code":"bad_request","message":"after is invalid","field":"before"}',
          status: 400));
      final error =
          ((await client.routing.plan(stopsAB)) as Failure<Route>).error;
      expect(error.field, 'before');
    });

    test('a 200 body that is not the plan response is a failure', () async {
      final (client, _) = makeClient((_) => resp('{"data":null}'));
      final result = await client.routing.plan(stopsAB);
      expect(result, isA<Failure<Route>>());
    });

    test('plan sends the search window as given, without clamping', () async {
      final (client, mock) = makeClient((_) => resp(planBody));
      await client.routing.plan(const PlanOptions(
          origin: Location.stop('A'),
          destination: Location.stop('B'),
          searchWindowMinutes: 0));
      expect(bodyOf(mock.requests.single)['searchWindow'], 'PT0M');
    });

    test('plan maps LOCATION_NOT_FOUND on from, to and via', () async {
      final body = planJson(routingErrors: [
        for (final (field, description) in [
          ('FROM', 'unknown origin'),
          ('TO', 'unknown destination'),
          ('VIA', 'unknown via stop'),
        ])
          {
            'code': 'LOCATION_NOT_FOUND',
            'inputField': field,
            'description': description
          }
      ]);
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

      test('reject a visit wait below 0 or above 1 h without a request',
          () async {
        for (final wait in [-1, 3601]) {
          final (result, mock) = await planVia([
            ViaLocation.visit(const Location.stop('V'),
                minimumWaitSeconds: wait)
          ]);
          final error = (result as Failure<Route>).error;
          expect(error.code, SpiderErrorCode.badRequest, reason: '$wait');
          expect(error.field, 'via.visit.minimumWaitTime', reason: '$wait');
          expect(error.message, 'via.visit.minimumWaitTime is out of range');
          expect(mock.requests, isEmpty);
        }
      });

      test('reject a coordinate visit as via is invalid without a request',
          () async {
        final (result, mock) = await planVia(
            [const ViaLocation.visit(Location.coordinate(49.2, 16.6))]);
        final error = (result as Failure<Route>).error;
        expect(error.code, SpiderErrorCode.badRequest);
        expect(error.field, 'via');
        expect(error.message, 'via is invalid');
        expect(mock.requests, isEmpty);
      });

      test('send 10 stop ids, a visit stop and a 1 h wait', () async {
        final (result, mock) = await planVia([
          ViaLocation.passThrough(List.generate(10, (i) => 'S$i')),
          ViaLocation.visit(const Location.stop('V'), minimumWaitSeconds: 3600),
          ViaLocation.visit(const Location.stop('W')),
        ]);
        expect(result, isA<Success<Route>>());
        final via = bodyOf(mock.requests.single)['via'] as List;
        expect(
            ((via[0] as Map)['passThrough'] as Map)['stopLocationIds'] as List,
            hasLength(10));
        expect((via[1] as Map)['visit'], {
          'stopLocationIds': ['V'],
          'minimumWaitTime': 'PT3600S'
        });
        expect((via[2] as Map)['visit'], {
          'stopLocationIds': ['W']
        });
      });

      test('leave the number of via locations to the server', () async {
        final (result, mock) = await planVia(
            List.generate(5, (i) => ViaLocation.passThrough(['S$i'])));
        expect(result, isA<Success<Route>>());
        expect(bodyOf(mock.requests.single)['via'] as List, hasLength(5));
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
        ('limit is not allowed', 'limit'),
        ('body is invalid', 'body'),
        (
          'preferences.street.walk.speed is out of range',
          'preferences.street.walk.speed'
        ),
        ('via.visit.coordinate is not allowed', 'via.visit.coordinate'),
        ('.limit is invalid', null),
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
      final body = departuresJson([
        stoptimeJson('1:T1', {
          'realtimeDeparture': 36060,
          'realtime': true,
          'realtimeState': 'UPDATED',
        }),
        stoptimeJson('1:T2', {
          'scheduledDeparture': 88800,
          'realtimeDeparture': 88800,
          'headsign': 'main square',
          'trip': {
            'gtfsId': '1:T2',
            'bikesAllowed': 'NO_INFORMATION',
            'wheelchairAccessible': 'NO_INFORMATION',
            'route': routeJson('1:R5', {'shortName': '5', 'mode': 'TRAM'}),
          },
        }),
      ], {
        'name': 'Main Square',
        'wheelchairBoarding': 'POSSIBLE'
      });
      final (client, mock) = makeClient((_) => resp(body));
      final result =
          await client.routing.departures('S', numberOfDepartures: 10);
      final departures = (result as Success<List<Departure>>).value;
      expect(bodyOf(mock.requests.single)['numberOfDepartures'], 10);
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
      final body = departuresJson([
        stoptimeJson('1:T1', {
          'stop': {'gtfsId': '1:ST-P2', 'platformCode': '2'},
          'trip': {
            'gtfsId': '1:T1',
            'bikesAllowed': 'NO_INFORMATION',
            'wheelchairAccessible': 'NOT_POSSIBLE',
            'route': routeJson('1:R12', {'mode': 'BUS'}),
          },
        }),
        stoptimeJson('1:T2', {
          'scheduledDeparture': 36600,
          'stop': {'gtfsId': '1:ST-P1', 'platformCode': null},
          'trip': {
            'gtfsId': '1:T2',
            'bikesAllowed': 'NO_INFORMATION',
            'wheelchairAccessible': 'NO_INFORMATION',
            'route': routeJson('1:R5', {
              'shortName': null,
              'longName': null,
              'color': null,
              'textColor': null,
              'mode': 'BUS'
            }),
          },
        }),
      ]);
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
      expect(bare.stopGtfsId, '1:ST-P1');
      expect(bare.platformCode, isNull);
      expect(bare.wheelchairAccessible, isNull);
    });

    test('departures maps the typical delay, null when unknown', () async {
      final body = departuresJson([
        stoptimeJson('1:T1', {'typicalDelay': 45}),
        stoptimeJson('1:T2', {'typicalDelay': null}),
      ]);
      final (client, _) = makeClient((_) => resp(body));
      final departures =
          ((await client.routing.departures('S')) as Success<List<Departure>>)
              .value;
      expect(departures.map((d) => d.typicalDelay).toList(),
          [const Duration(seconds: 45), null]);

      final (stationClient, _) =
          makeClient((_) => resp(departuresJson([stoptimeJson('1:T1')])));
      final fromStation = ((await stationClient.routing.departures('1:ST'))
              as Success<List<Departure>>)
          .value;
      expect(fromStation.single.typicalDelay, Duration.zero);
    });

    test(
        'departures posts the default count and a 24 h time range to '
        '/routing/v1/departures', () async {
      final (client, mock) = makeClient((_) => resp(departuresJson(const [])));
      await client.routing.departures('S');
      final req = mock.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/routing/v1/departures');
      expect(req.headers['content-type'], 'application/json');
      expect(bodyOf(req),
          {'id': 'S', 'numberOfDepartures': 30, 'timeRange': 86400});
    });

    test('departures sends the start time in Unix seconds', () async {
      final (client, mock) = makeClient((_) => resp(departuresJson(const [])));
      await client.routing.departures('S',
          startTime:
              DateTime.fromMillisecondsSinceEpoch(1791612000999, isUtc: true));
      expect(bodyOf(mock.requests.single)['startTime'], 1791612000);
    });

    test('departures for an unknown id (stop null) is notFound', () async {
      final (client, _) = makeClient((_) => resp('{"stop":null}'));
      final result = await client.routing.departures('1:NOPE');
      final error = (result as Failure<List<Departure>>).error;
      expect(error.code, SpiderErrorCode.notFound);
      expect(error.message, contains('1:NOPE'));
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
      final (client, mock) = makeClient((_) => resp(departuresJson(const [])));
      await client.routing.departures('S', timeRangeSeconds: 1);
      expect(bodyOf(mock.requests.single)['timeRange'], 1);
    });

    test('trip without a service date leaves it to the server (today)',
        () async {
      final (client, mock) = makeClient((_) => resp(tripJson(const [])));
      final result = await client.routing.trip('T1');
      expect(result, isA<Success<TripDetails>>());
      final req = mock.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/routing/v1/trip');
      expect(bodyOf(req), {'id': 'T1'});
    });

    test('trip for an unknown id (trip null) is notFound', () async {
      final (client, _) = makeClient((_) => resp('{"trip":null}'));
      final result = await client.routing.trip('1:NOPE');
      final error = (result as Failure<TripDetails>).error;
      expect(error.code, SpiderErrorCode.notFound);
      expect(error.message, contains('1:NOPE'));
    });

    test('trip maps stops, geometry and enums', () async {
      final body = tripJson([
        tripStoptimeJson('1:S1', {
          'scheduledDeparture': 36030,
          'realtimeArrival': 36050,
          'realtimeDeparture': 36080,
          'realtime': true,
        }, {
          'wheelchairBoarding': 'POSSIBLE'
        })
      ], {
        'bikesAllowed': 'NOT_ALLOWED',
        'tripGeometry': {'points': '_p~iF~ps|U', 'length': 2},
      });
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
      expect(bodyOf(mock.requests.single),
          {'id': 'T1', 'serviceDate': '2026-08-21'});
    });

    test('trip maps the route, accessibility and stop display fields',
        () async {
      final body = tripJson([
        tripStoptimeJson(
            '1:S1', const {}, {'platformCode': '3', 'zoneId': 'P'}),
        tripStoptimeJson('1:S2', {'scheduledArrival': 36600},
            {'name': 'B', 'platformCode': null, 'zoneId': null}),
      ], {
        'wheelchairAccessible': 'POSSIBLE',
        'route': routeJson('1:R12', {
          'color': '00A0E2',
          'textColor': '000000',
          'mode': 'BUS',
        }),
      });
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

      final (bareClient, _) = makeClient((_) => resp(tripJson(const [], {
            'route': routeJson('1:R12', {
              'shortName': null,
              'longName': null,
              'color': null,
              'textColor': null,
              'mode': 'BUS',
            })
          })));
      final bare =
          ((await bareClient.routing.trip('T1')) as Success<TripDetails>).value;
      expect(bare.routeColor, isNull);
      expect(bare.routeTextColor, isNull);
      expect(bare.wheelchairAccessible, isNull);
    });

    test('trip maps the typical delay per stop, null when unknown', () async {
      final body = tripJson([
        tripStoptimeJson('1:S1', {'typicalDelay': 30}),
        tripStoptimeJson(
            '1:S2', {'scheduledArrival': 36600, 'typicalDelay': null}),
      ]);
      final (client, _) = makeClient((_) => resp(body));
      final trip =
          ((await client.routing.trip('T1')) as Success<TripDetails>).value;
      expect(trip.stops.map((s) => s.typicalDelay).toList(),
          [const Duration(seconds: 30), null]);
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
      expect(mock.requests[0].method, 'POST');
      expect(mock.requests[0].uri.path, '/stops/v1/search');
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
          '{"vehicles":[{"tripId":"1:T1","latitude":49.1,"longitude":16.6,"occupancyStatus":"FEW_SEATS_AVAILABLE","timestamp":1700000000}],"missing":["1:T9"],"feedTimestamp":1700000000,"staleSeconds":3}';
      final (client, mock) = makeClient((_) => resp(body));
      final result = await client.realtime.vehicles(['1:T1', '1:T9']);
      final positions = (result as Success<VehiclePositions>).value;
      expect(positions.vehicles[0].timestampEpochMs, 1700000000 * 1000);
      expect(
          positions.vehicles[0].occupancy, OccupancyStatus.fewSeatsAvailable);
      expect(positions.missing, ['1:T9']);
      expect(positions.freshness.staleSeconds, 3);
      expect(positions.freshness.feedTimestampEpochMs, 1700000000 * 1000);
      expect(mock.requests[0].uri.queryParameters['tripIds'], '1:T1,1:T9');
    });

    test('each call targets its /v1 path', () async {
      final calls = <(String, String), Future<Object?> Function(SpiderClient)>{
        ('GET', '/realtime/v1/vehicles'): (c) => c.realtime.vehicles(['1:T1']),
        ('GET', '/realtime/v1/vehicles/by-trip/1%3AT1'): (c) =>
            c.realtime.vehicleForTrip('1:T1'),
        ('GET', '/realtime/v1/delays'): (c) =>
            c.realtime.delays('2026-07-15', ['1:T1']),
        ('GET', '/realtime/v1/alerts'): (c) => c.realtime.alerts(),
      };
      for (final MapEntry(key: (method, path), value: call) in calls.entries) {
        final (client, mock) = makeClient((_) => resp('{}'));
        await call(client);
        final req = mock.requests.single;
        expect((req.method, req.uri.path), (method, path));
      }
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
      final result = await client.realtime.vehicleForTrip('1:T1');
      final error = (result as Failure<LiveVehicleUpdate>).error;
      expect(error.code, SpiderErrorCode.badRequest);
      expect(error.field, 'tripId');
    });

    test('vehicleForTrip 404 is a soft null', () async {
      final (client, _) = makeClient((_) => resp('{}', status: 404));
      final result = await client.realtime.vehicleForTrip('1:T1');
      expect((result as Success<LiveVehicleUpdate>).value.vehicle, isNull);
    });

    test('delays GETs one service date with the ids as sent', () async {
      const body =
          '{"serviceDate":"2026-07-15","delays":[{"tripId":"1:T1","routeId":"1:R1","delaySeconds":120,"scheduleRelationship":"SCHEDULED","stopTimeUpdates":[{"stopId":"1:S1","stopSequence":3,"arrivalDelay":120,"departureDelay":90}]}],"missing":["1:T2"],"feedTimestamp":1700000000,"staleSeconds":2}';
      final (client, mock) = makeClient((_) => resp(body));
      final result =
          await client.realtime.delays('2026-07-15', ['1:T2', '1:T1']);
      final delays = (result as Success<TripDelays>).value;

      final req = mock.requests.single;
      expect(req.method, 'GET');
      expect(req.uri.path, '/realtime/v1/delays');
      expect(req.uri.queryParameters,
          {'serviceDate': '2026-07-15', 'tripIds': '1:T1,1:T2'});

      expect(delays.serviceDate, '2026-07-15');
      final d = delays.delayFor('1:T1');
      expect(d?.routeId, '1:R1');
      expect(d?.delaySeconds, 120);
      expect(d?.stopTimeUpdates.first.stopId, '1:S1');
      expect(d?.stopTimeUpdates.first.arrivalDelay, 120);
      expect(delays.delayFor('T1'), isNull);
      expect(delays.missing, ['1:T2']);
      expect(delays.freshness.feedTimestampEpochMs, 1700000000 * 1000);
      expect(delays.freshness.staleSeconds, 2);
    });

    test('delays de-duplicates and sorts ids into one URL', () async {
      final urls = <String>[];
      for (final ids in [
        ['1:B', '1:A', '1:B'],
        ['1:A', '1:B'],
      ]) {
        final (client, mock) = makeClient((_) => resp(
            '{"serviceDate":"2026-07-15","delays":[],"missing":["1:A","1:B"]}'));
        final result = await client.realtime.delays('2026-07-15', ids);
        expect(result, isA<Success<TripDelays>>());
        urls.add(mock.requests.single.uri.toString());
      }
      expect(urls[0], urls[1]);
    });

    test('delays rejects fixed limits without a request', () async {
      final cases = <(String, List<String>, String, String)>[
        ('2026-07-15', const [], 'tripIds', 'tripIds is required'),
        ('2026-07-15', const ['1:T1', ' '], 'tripIds', 'tripIds is invalid'),
        ('2026-07-15', const ['1:T1', ''], 'tripIds', 'tripIds is invalid'),
        (
          '2026-07-15',
          List.generate(51, (i) => '1:T$i'),
          'tripIds',
          'tripIds is out of range'
        ),
        ('20260715', const ['1:T1'], 'serviceDate', 'serviceDate is invalid'),
      ];
      for (final (date, ids, field, message) in cases) {
        final (client, mock) = makeClient((_) => resp('{}'));
        final result = await client.realtime.delays(date, ids);
        final error = (result as Failure<TripDelays>).error;
        expect(error.code, SpiderErrorCode.badRequest, reason: message);
        expect(error.field, field, reason: message);
        expect(error.message, message);
        expect(mock.requests, isEmpty, reason: message);
      }
    });

    test('delays counts distinct ids against the limit of 50', () async {
      final (client, mock) = makeClient(
          (_) => resp('{"serviceDate":"2026-07-15","delays":[],"missing":[]}'));
      final ids = [
        ...List.generate(50, (i) => '1:T$i'),
        ...List.generate(10, (i) => '1:T$i'),
      ];
      final result = await client.realtime.delays('2026-07-15', ids);
      expect(result, isA<Success<TripDelays>>());
      expect(mock.requests.single.uri.queryParameters['tripIds']!.split(','),
          hasLength(50));
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
          RoutingErrorCode.unknown);
      expect(
          RoutingErrorCode.fromWire('SOMETHING_NEW'), RoutingErrorCode.unknown);
      expect(InputField.fromWire('VIA'), InputField.via);
      expect(InputField.fromWire('FROM_PLACE'), InputField.unknown);
    });

    test('an unknown wire value decodes to unknown through the plan mapping',
        () {
      final data = streamPageInfoJson(const {}, [
        {'code': 'SOMETHING_NEW', 'inputField': 'SOMEWHERE', 'description': 'x'}
      ]);
      final done = parsePlanStreamRecord('pageInfo', data) as PlanStreamDone;
      expect(done.routingErrors.single.code, RoutingErrorCode.unknown);
      expect(done.routingErrors.single.inputField, InputField.unknown);
      final chunk = chunkJson([
        itineraryJson([
          legJson({'mode': 'HOVERCRAFT', 'realtimeState': 'SOMETHING_NEW'})
        ])
      ]);
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
      final data = chunkJson([
        itineraryJson([
          legJson({
            'from': {
              'name': 'A',
              'stop': stopJson('1:A', {'wheelchairBoarding': 'RAMP_ONLY'})
            },
            'to': {
              'name': 'B',
              'stop': stopJson('1:B', {'wheelchairBoarding': 'NO_INFORMATION'})
            },
            'trip': {'gtfsId': '1:T', 'bikesAllowed': 'FOLDING_ONLY'},
          }),
          legJson({
            'trip': {'gtfsId': '1:T2', 'bikesAllowed': 'NO_INFORMATION'},
          }),
        ])
      ]);
      final legs = (parsePlanStreamRecord('chunk', data) as PlanStreamResult)
          .itineraries
          .single
          .legs;
      expect(legs[0].fromWheelchair, WheelchairBoarding.unknown);
      expect(legs[0].toWheelchair, isNull);
      expect(legs[0].bikesAllowed, BikesAllowed.unknown);
      expect(legs[1].bikesAllowed, isNull);

      final (client, _) = makeClient((_) =>
          resp(tripJson(const [], {'wheelchairAccessible': 'SOMETHING_NEW'})));
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
      final data = chunkJson([
        itineraryJson([
          legJson({
            'start': {
              'scheduledTime': '2026-07-15T08:00:00Z',
              'estimated': {'time': '2026-07-15T08:01:00Z', 'delay': 'PT60S'}
            },
            'end': {
              'scheduledTime': '2026-07-15T08:30:00Z',
              'estimated': {'time': '2026-07-15T08:32:00Z', 'delay': 'PT120S'}
            },
            'typicalArrivalDelay': 150,
            'realtimeState': 'UPDATED',
            'realTime': true,
            'serviceDate': '2026-07-15',
            'from': {
              'name': 'Origin',
              'stop': stopJson('1:A', {'platformCode': null})
            },
            'to': {
              'name': 'Dest',
              'stop': stopJson('1:B', {'zoneId': null})
            },
            'route': routeJson('1:R12', {'color': null, 'textColor': null}),
            'interlineWithPreviousLeg': true,
          })
        ], {
          'numberOfTransfers': 1
        })
      ]);
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
      expect(leg.typicalArrivalDelay, const Duration(seconds: 150));
      expect(leg.interlineWithPreviousLeg, true);
      expect(leg.startEstimated, '2026-07-15T08:01:00Z');
      expect(leg.isRealtime, true);
      expect(leg.realtimeState, RealtimeState.updated);
      expect(leg.serviceDate, '2026-07-15');
      expect(leg.fromGtfsId, '1:A');
      expect(leg.toGtfsId, '1:B');
      expect(leg.routeGtfsId, '1:R12');
      // Null display fields stay null.
      expect(leg.routeColor, isNull);
      expect(leg.routeTextColor, isNull);
      expect(leg.fromPlatformCode, isNull);
      expect(leg.toZoneId, isNull);
    });

    // The `pageInfo` frame is the terminal event: it maps to PlanStreamDone carrying the continuation cursors.
    test('pageInfo maps to a terminal Done with continuation cursors', () {
      const data =
          '{ "startCursor": "c-prev", "endCursor": "c-next", "hasNextPage": true, "hasPreviousPage": false, "searchWindowUsed": "PT1H", "routingErrors": [] }';
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

    // Routing outcomes ride on the terminal pageInfo, shaped like the batch plan's routingErrors.
    test('pageInfo carries routing errors on the terminal Done', () {
      final data = streamPageInfoJson(const {}, [
        {
          'code': 'OUTSIDE_SERVICE_PERIOD',
          'inputField': 'DATE_TIME',
          'description': 'outside the feed'
        },
        {
          'code': 'LOCATION_NOT_FOUND',
          'inputField': 'FROM',
          'description': 'unknown stop'
        },
      ]);
      final event = parsePlanStreamRecord('pageInfo', data) as PlanStreamDone;
      expect(event.routingErrors.length, 2);
      expect(
          event.routingErrors[0].code, RoutingErrorCode.outsideServicePeriod);
      expect(event.routingErrors[0].inputField, InputField.dateTime);
      expect(event.routingErrors[0].description, 'outside the feed');
      expect(event.routingErrors[1].code, RoutingErrorCode.locationNotFound);
      expect(event.routingErrors[1].inputField, InputField.from);
    });

    test('done telemetry is ignored', () {
      const data =
          '{ "iterations": 3, "windowSeconds": 3600, "resultCount": 5, "stoppedBy": "targetResults" }';
      expect(parsePlanStreamRecord('done', data), isNull);
    });

    test('heartbeats and unknown events, error included, are ignored', () {
      expect(parsePlanStreamRecord('message', ''), isNull);
      expect(parsePlanStreamRecord('weird', '{ "x": 1 }'), isNull);
      expect(
          parsePlanStreamRecord(
              'error', '{"code":"bad_request","message":"x is invalid"}'),
          isNull);
    });

    test('a chunk or pageInfo off the contract is a decoding failure', () {
      for (final (event, data) in [
        ('chunk', '{"results":[]}'),
        ('pageInfo', '{"hasNextPage":true,"hasPreviousPage":false}'),
        ('pageInfo', 'not json'),
      ]) {
        final failure = parsePlanStreamRecord(event, data) as PlanStreamFailure;
        expect(failure.error.code, SpiderErrorCode.decoding, reason: data);
      }
    });

    // Pins the stream request wire shape so a contract regen can't silently rename or reorder its fields.
    test('the stream request serializes to the plan-stream wire shape', () {
      final variables = wire.PlanStreamRequest(
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
        reliability: wire.Reliability.safe,
      );
      expect(jsonDecode(jsonEncode(variables)), {
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
        'reliability': 'SAFE',
      });
    });

    test(
        'planStream emits Result then a terminal Done over SSE (dropping the '
        'done telemetry) and posts the REST body, no cursors', () async {
      final frames = 'event: chunk\n'
          'data: ${chunkJson([
            itineraryJson([
              legJson({'typicalArrivalDelay': null})
            ])
          ])}\n'
          '\n'
          ': heartbeat\n'
          '\n'
          'event: pageInfo\n'
          'data: ${streamPageInfoJson({
            'endCursor': 'c-next',
            'hasNextPage': true
          })}\n'
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
      final leg =
          (events[0] as PlanStreamResult).itineraries.single.legs.single;
      expect(leg.mode, TransitMode.bus);
      expect(leg.typicalArrivalDelay, isNull);
      expect(leg.interlineWithPreviousLeg, false);
      final done = events[1] as PlanStreamDone;
      expect(done.pageInfo.endCursor, 'c-next');
      expect(done.pageInfo.hasNextPage, true);

      final req = mock.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/routing/v1/plan-stream');
      expect(req.headers['apikey'], 'secret-key');
      expect(req.headers['accept'], 'text/event-stream');
      expect(req.headers['content-type'], 'application/json');
      expect(req.headers['x-spider-contract-version'], contractVersion);
      final vars = bodyOf(req);
      expect(vars.containsKey('id'), false);
      expect(vars.containsKey('variables'), false);
      expect(vars.containsKey('after'), false);
      expect(vars.containsKey('before'), false);
      expect(vars.containsKey('reliability'), false);
      expect(vars.containsKey('searchWindow'), false);
      expect(vars['targetResults'], 4);
      expect(vars['maxWindow'], 'PT180M');
    });

    test('planStream sends reliability when set', () async {
      final (client, mock) = makeStreamClient(200, pageInfoFrame);
      await client.routing
          .planStream(
              const PlanOptions(
                  origin: Location.stop('A'),
                  destination: Location.stop('B'),
                  reliability: Reliability.verySafe),
              targetResults: 5,
              maxWindowMinutes: 120)
          .toList();
      expect(bodyOf(mock.requests.single)['reliability'], 'VERY_SAFE');
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
      final (client, mock) = makeStreamClient(200, pageInfoFrame);
      final events = await client.routing
          .planStream(stopsAB, targetResults: 5, maxWindowMinutes: 120)
          .toList();
      expect(events.single, isA<PlanStreamDone>());
      expect(bodyOf(mock.requests.single)['maxWindow'], 'PT120M');
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

    test('planStream rejects a coordinate visit as via is invalid', () async {
      final (client, mock) = makeStreamClient(200, pageInfoFrame);
      final events = await client.routing
          .planStream(
              const PlanOptions(
                  origin: Location.stop('A'),
                  destination: Location.stop('B'),
                  via: [ViaLocation.visit(Location.coordinate(49.2, 16.6))]),
              targetResults: 5,
              maxWindowMinutes: 120)
          .toList();
      final error = (events.single as PlanStreamFailure).error;
      expect(error.code, SpiderErrorCode.badRequest);
      expect(error.field, 'via');
      expect(error.message, 'via is invalid');
      expect(mock.requests, isEmpty);
    });

    test('a 400 before the stream is a badRequest naming the body field',
        () async {
      final (client, _) = makeStreamClient(
          400,
          '{"code":"bad_request","message":"targetResults is required",'
          '"field":"targetResults"}',
          contentType: 'application/json');
      final events = await client.routing
          .planStream(stopsAB, targetResults: 5, maxWindowMinutes: 120)
          .toList();
      final error = (events.single as PlanStreamFailure).error;
      expect(error.code, SpiderErrorCode.badRequest);
      expect(error.httpStatus, 400);
      expect(error.field, 'targetResults');
    });

    test('a stream that ends without pageInfo is a network failure', () async {
      for (final body in [
        'event: chunk\n'
            'data: {"frontier":60,"found":0,"finalized":0,"results":[]}\n\n',
        '',
      ]) {
        final (client, _) = makeStreamClient(200, body);
        final events = await client.routing
            .planStream(stopsAB, targetResults: 5, maxWindowMinutes: 120)
            .toList();
        final failure = events.last as PlanStreamFailure;
        expect(failure.error.code, SpiderErrorCode.network, reason: body);
        expect(failure.error.message, contains('without pageInfo'));
        expect(events.whereType<PlanStreamDone>(), isEmpty, reason: body);
      }
    });

    test(
        'nothing follows the terminal event, and the stream is read to its '
        'done', () async {
      var drained = false;
      Stream<List<int>> frames() async* {
        yield utf8.encode(pageInfoFrame);
        await Future<void>.delayed(Duration.zero);
        yield utf8.encode('event: chunk\n'
            'data: {"frontier":60,"found":1,"finalized":1,"results":[]}\n\n'
            '$pageInfoFrame'
            'event: done\n'
            'data: {"iterations":1,"windowSeconds":60,"resultCount":0,"stoppedBy":"targetResults"}\n\n');
        drained = true;
      }

      final mock = MockHttpClient((_) => resp('{}'),
          streamHandler: (_) => SpiderHttpStreamedResponse(
              200, {'content-type': 'text/event-stream'}, frames()));
      final client = SpiderClient('https://env.api.example.com', 'secret-key',
          SpiderClientOptions(httpClient: mock));
      final events = await client.routing
          .planStream(stopsAB, targetResults: 5, maxWindowMinutes: 120)
          .toList();
      expect(events.single, isA<PlanStreamDone>());
      expect(drained, true);
    });

    test('a connection drop after pageInfo keeps the Done', () async {
      Stream<List<int>> frames() async* {
        yield utf8.encode(pageInfoFrame);
        throw http.ClientException('connection closed');
      }

      final mock = MockHttpClient((_) => resp('{}'),
          streamHandler: (_) => SpiderHttpStreamedResponse(
              200, {'content-type': 'text/event-stream'}, frames()));
      final client = SpiderClient('https://env.api.example.com', 'secret-key',
          SpiderClientOptions(httpClient: mock));
      final events = await client.routing
          .planStream(stopsAB, targetResults: 5, maxWindowMinutes: 120)
          .toList();
      expect(events.single, isA<PlanStreamDone>());
    });

    test('a connection drop before pageInfo is a network failure', () async {
      Stream<List<int>> frames() async* {
        yield utf8.encode('event: chunk\n'
            'data: {"frontier":60,"found":0,"finalized":0,"results":[]}\n\n');
        throw http.ClientException('connection closed');
      }

      final mock = MockHttpClient((_) => resp('{}'),
          streamHandler: (_) => SpiderHttpStreamedResponse(
              200, {'content-type': 'text/event-stream'}, frames()));
      final client = SpiderClient('https://env.api.example.com', 'secret-key',
          SpiderClientOptions(httpClient: mock));
      final events = await client.routing
          .planStream(stopsAB, targetResults: 5, maxWindowMinutes: 120)
          .toList();
      expect(events.first, isA<PlanStreamResult>());
      expect((events.last as PlanStreamFailure).error.code,
          SpiderErrorCode.network);
    });

    test('planStreamNext continues forward with after and repeats the request',
        () async {
      final frames = 'event: pageInfo\n'
          'data: ${streamPageInfoJson({
            'startCursor': 'c-prev',
            'endCursor': 'c-next2',
            'hasNextPage': true,
            'hasPreviousPage': true
          })}\n'
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

      final vars = bodyOf(mock.requests.single);
      expect(vars['after'], 'c-next');
      expect(vars.containsKey('before'), false);
      expect(vars['targetResults'], 3);
      expect(vars['maxWindow'], 'PT240M');
    });

    test('planStreamPrevious continues backward with before', () async {
      final frames = 'event: pageInfo\n'
          'data: ${streamPageInfoJson({
            'startCursor': 'c-prev2',
            'endCursor': 'c-next',
            'hasNextPage': true
          })}\n'
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

      final vars = bodyOf(mock.requests.single);
      expect(vars['before'], 'c-prev');
      expect(vars.containsKey('after'), false);
    });

    test('planStreamNext and planStreamPrevious send the reliability',
        () async {
      const options = PlanOptions(
          origin: Location.stop('A'),
          destination: Location.stop('B'),
          reliability: Reliability.standard);
      final (client, mock) = makeStreamClient(200, pageInfoFrame);
      await client.routing
          .planStreamNext(options,
              targetResults: 5, maxWindowMinutes: 120, after: 'c-next')
          .toList();
      await client.routing
          .planStreamPrevious(options,
              targetResults: 5, maxWindowMinutes: 120, before: 'c-prev')
          .toList();
      expect(mock.requests.map((r) => bodyOf(r)['reliability']).toList(),
          ['STANDARD', 'STANDARD']);
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
      'realtime.vehicles': (c) => c.realtime.vehicles(['1:T1']),
      'realtime.vehicleForTrip': (c) => c.realtime.vehicleForTrip('1:T1'),
      'realtime.delays': (c) => c.realtime.delays('2026-07-15', ['1:T1']),
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

    test('the contract code names the refusal too, before the gateway error',
        () async {
      for (final (code, serverCode, message) in limits) {
        for (final call in calls.keys) {
          final error = await errorOf(
              call,
              resp(
                  jsonEncode({
                    'code': serverCode,
                    'error': 'forbidden',
                    'message': message
                  }),
                  status: 403));
          expect(error.code, code, reason: '$call $serverCode');
          expect(error.serverCode, serverCode, reason: '$call $serverCode');
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
        for (final body in [
          {'error': serverCode},
          {'error': serverCode, 'message': ''},
          {'error': serverCode, 'message': '  '},
        ]) {
          final error =
              await errorOf('plan', resp(jsonEncode(body), status: 403));
          expect(error.code, code, reason: '$body');
          expect(error.message, message, reason: '$body');
        }
      }
    });

    test('a refusal message is trimmed', () async {
      final error = await errorOf(
          'plan',
          resp(refusal('agreement_inactive', ' agreement is not active \n'),
              status: 403));
      expect(error.message, 'agreement is not active');
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
