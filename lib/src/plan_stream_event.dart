import 'errors.dart';
import 'routing.dart';

/// One event from [SpiderRouting.planStream]. The router sweeps the search window forward and pushes
/// itineraries as they finalize: zero or more [PlanStreamChunk]s, then a [PlanStreamPage] with the
/// continuation cursors, then a terminal [PlanStreamDone]. A [PlanStreamFailure] is terminal and takes the
/// place of the rest.
sealed class PlanStreamEvent {
  const PlanStreamEvent();
}

/// A batch of finalized itineraries as the search frontier advances. Each [Itinerary]'s legs carry the
/// scheduled times plus the realtime delay fields ([Leg.startEstimated] / [Leg.endEstimated] /
/// [Leg.startDelay] / [Leg.endDelay] / [Leg.isRealtime] / [Leg.realtimeState]) — the same delay handling the
/// one-shot [SpiderRouting.plan] applies. [frontierSeconds] is how far (seconds from the search start) the
/// window has swept; [found] is the running count discovered and [finalized] the count committed so far.
final class PlanStreamChunk extends PlanStreamEvent {
  final int frontierSeconds;
  final int found;
  final int finalized;
  final List<Itinerary> itineraries;
  const PlanStreamChunk({
    required this.frontierSeconds,
    required this.found,
    required this.finalized,
    required this.itineraries,
  });
}

/// Continuation cursors for the stream, mirroring [Route.pageInfo]. Re-call [SpiderRouting.planStream] with
/// the same inputs plus `after` = [RoutePageInfo.endCursor] to stream the next window (or `before` =
/// [RoutePageInfo.startCursor] for the previous one).
final class PlanStreamPage extends PlanStreamEvent {
  final RoutePageInfo pageInfo;
  const PlanStreamPage(this.pageInfo);
}

/// Terminal summary once the sweep stops: how many [iterations] ran, the window reached in [windowSeconds],
/// the total [resultCount], and why it [stoppedBy] (e.g. `targetResults` or `maxWindow`).
final class PlanStreamDone extends PlanStreamEvent {
  final int iterations;
  final int windowSeconds;
  final int resultCount;
  final String stoppedBy;
  const PlanStreamDone({
    required this.iterations,
    required this.windowSeconds,
    required this.resultCount,
    required this.stoppedBy,
  });
}

/// Terminal failure — a transport/HTTP problem, a decoding error, or a server `error` event (e.g. an invalid
/// request). [error] is the same [SpiderError] taxonomy the one-shot calls return.
final class PlanStreamFailure extends PlanStreamEvent {
  final SpiderError error;
  const PlanStreamFailure(this.error);
}
