import 'errors.dart';
import 'routing.dart';

/// One event from [SpiderRouting.planStream]. The router sweeps the search window forward and pushes
/// itineraries as they finalize: zero or more [PlanStreamResult]s, then a terminal [PlanStreamDone] carrying
/// the continuation paging info. A [PlanStreamFailure] is terminal and takes the place of the rest.
sealed class PlanStreamEvent {
  const PlanStreamEvent();
}

/// A batch of finalized itineraries as the search frontier advances. Each [Itinerary]'s legs carry the
/// scheduled times plus the realtime delay fields ([Leg.startEstimated] / [Leg.endEstimated] /
/// [Leg.startDelay] / [Leg.endDelay] / [Leg.isRealtime] / [Leg.realtimeState]) — the same delay handling the
/// one-shot [SpiderRouting.plan] applies.
final class PlanStreamResult extends PlanStreamEvent {
  final List<Itinerary> itineraries;
  const PlanStreamResult(this.itineraries);
}

/// Terminal event: the continuation paging info, mirroring [Route.pageInfo]. Continue forward with
/// [SpiderRouting.planStreamNext] passing [RoutePageInfo.endCursor] when [RoutePageInfo.hasNextPage], or
/// backward with [SpiderRouting.planStreamPrevious] passing [RoutePageInfo.startCursor] when
/// [RoutePageInfo.hasPreviousPage].
final class PlanStreamDone extends PlanStreamEvent {
  final RoutePageInfo pageInfo;

  /// Why the search found fewer or no itineraries (e.g. an unknown stop, or a date outside the feed), shaped
  /// like [Route.routingErrors]; empty when there is nothing to report.
  final List<RoutingError> routingErrors;
  const PlanStreamDone(this.pageInfo, {this.routingErrors = const []});
}

/// Terminal failure — a transport/HTTP problem, a decoding error, or a server `error` event (an invalid
/// request). [error] is the same [SpiderError] taxonomy the one-shot calls return.
final class PlanStreamFailure extends PlanStreamEvent {
  final SpiderError error;
  const PlanStreamFailure(this.error);
}
