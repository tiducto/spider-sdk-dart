/// The Dart SDK for the Spider transit API — trip planning, stop search, and live realtime data behind one
/// typed client.
library;

export 'src/client.dart'
    show SpiderClient, SpiderClientOptions, FeatureOptions, AutoRetryOptions;
export 'src/enums.dart';
export 'src/errors.dart'
    show SpiderError, SpiderErrorCode, SpiderContractMismatchError;
export 'src/location.dart';
export 'src/polyline.dart' show LatLon;
export 'src/realtime.dart';
export 'src/result.dart';
export 'src/routing.dart'
    show
        SpiderRouting,
        Route,
        RouteEdge,
        Itinerary,
        Leg,
        RoutePageInfo,
        RoutingError,
        Departure,
        TripStop,
        TripDetails,
        PlanOptions;
export 'src/routes.dart'
    show SpiderRoutes, RouteFilter, RouteMode, TransitRoute;
export 'src/stops.dart'
    show SpiderStops, Stop, StopFilter, GeoPoint, GeoBoundingBox;
export 'src/transport.dart'
    show
        SpiderHttpClient,
        SpiderHttpRequest,
        SpiderHttpResponse,
        DefaultSpiderHttpClient;
