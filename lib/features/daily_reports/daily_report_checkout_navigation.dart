/// Only a signed report opened by checkout returns to its next step.
/// A report opened independently remains available for viewing and printing.
bool shouldFinishCheckoutReport({
  required bool signed,
  required bool isVisitReport,
  required String? reportRouteId,
  required String? checkoutRouteId,
  required String? checkoutSourceId,
  required DateTime reportDate,
  required DateTime? checkoutDate,
}) {
  if (!signed) return false;
  if (isVisitReport) return true;
  return reportRouteId != null &&
      reportRouteId == checkoutRouteId &&
      (checkoutSourceId ?? '').isNotEmpty &&
      checkoutDate != null &&
      reportDate.year == checkoutDate.year &&
      reportDate.month == checkoutDate.month &&
      reportDate.day == checkoutDate.day;
}
