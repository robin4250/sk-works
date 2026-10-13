import '../attendance/route_journey_visit_progress.dart';

enum HomeRouteActionState { unavailable, arrive, move, checkout }

/// Only a complete server visit contract can activate the next route action.
HomeRouteActionState homeRouteActionState(
  Map<String, dynamic> workspace,
  String sourceId,
) {
  final progress = RouteJourneyVisitProgress.fromWorkspace(workspace, sourceId);
  if (progress == null) return HomeRouteActionState.unavailable;
  if (progress.isFinalVisit) return HomeRouteActionState.checkout;
  if (progress.openVisit != null) return HomeRouteActionState.move;
  return progress.canArrive
      ? HomeRouteActionState.arrive
      : HomeRouteActionState.unavailable;
}
