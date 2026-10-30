import 'package:flutter/material.dart';
import '../shared/resource_registration_card.dart';
import 'daily_report_pdf_evidence.dart';

/// Already-authorized in-memory photographs; this widget performs no lookup.
/// The shared gallery supplies fullscreen close/name, pinch, swipe and retirement.
class DailyReportPhotoPreview extends StatelessWidget {
  const DailyReportPhotoPreview({super.key, required this.photos, required this.gallery});
  final List<DailyReportPdfEvidence> photos;
  final ResourceAttachmentGallery gallery;

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty || !gallery.isCurrent()) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 336.0;
      return Wrap(children: [
        for (final (index, photo) in photos.indexed)
          SizedBox(width: width / 6, child: Align(alignment: Alignment.center,
            child: ResourceAttachmentThumbnail(
              key: ValueKey('daily-report-photo-thumbnail-$index'),
              attachment: gallery.entries[index], gallery: gallery,
              recordTitle: photo.record.workerName, requireGalleryScope: true))),
      ]);
    });
  }
}

List<ResourceAttachment> dailyReportPhotoAttachments(List<DailyReportPdfEvidence> photos,
  {required Future<void> Function() validateAccess}) => [
  for (final (index, photo) in photos.indexed) ResourceAttachment(
    label: photo.record.workerName,
    recordTitle: '${photo.record.workerName} / ${photo.record.eventLabel}',
    previewKey: '${photo.record.storageBucket}:${photo.record.id}:$index',
    path: photo.record.storagePath.isEmpty ? 'missing:${photo.record.id}:$index' : photo.record.storagePath,
    validateAccess: validateAccess,
    loadBytes: () async {
      await validateAccess();
      final bytes = photo.photoBytes;
      if (bytes == null) throw StateError(photo.record.missingPhotoLabel);
      return bytes;
    }),
];
