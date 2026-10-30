import 'dart:ui';

/// Exact PDF paint bounds, normalized to a top-left page coordinate system.
class DailyReportPhotoHitTarget {
  const DailyReportPhotoHitTarget({required this.pageIndex, required this.photoIndex, required this.bounds});
  final int pageIndex, photoIndex;
  final Rect bounds;
}
