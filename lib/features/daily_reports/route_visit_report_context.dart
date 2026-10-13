/// Exact saved arrival/move pair. A date or site alone cannot identify a visit.
class RouteVisitReportContext {
  const RouteVisitReportContext({
    required this.sourceClockInId,
    required this.routeAssignmentId,
    required this.routeStopId,
    required this.startCaptureId,
    required this.endCaptureId,
  });

  final String sourceClockInId;
  final String routeAssignmentId;
  final String routeStopId;
  final String startCaptureId;
  final String endCaptureId;

  Map<String, Object?> toRpcParams() {
    final values = [
      sourceClockInId,
      routeAssignmentId,
      routeStopId,
      startCaptureId,
      endCaptureId,
    ];
    if (values.any((value) => value.trim().isEmpty) ||
        startCaptureId == endCaptureId) {
      throw StateError('現場訪問の記録を再確認してください');
    }
    return {
      'p_source_clock_in_id': sourceClockInId,
      'p_route_assignment_id': routeAssignmentId,
      'p_route_stop_id': routeStopId,
      'p_start_capture_id': startCaptureId,
      'p_end_capture_id': endCaptureId,
    };
  }

  bool matches(Map<dynamic, dynamic> value) =>
      value['source_clock_in_id'] == sourceClockInId &&
      value['route_assignment_id'] == routeAssignmentId &&
      value['route_stop_id'] == routeStopId &&
      value['start_capture_id'] == startCaptureId &&
      value['end_capture_id'] == endCaptureId;
}
