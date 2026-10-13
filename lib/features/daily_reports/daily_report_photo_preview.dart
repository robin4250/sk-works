import 'package:flutter/material.dart';

import '../../international/language_controller.dart';
import 'daily_report_pdf_evidence.dart';
import 'daily_report_photo_pages.dart';

/// The app thumbnail opens the actual saved evidence, including every photo.
class DailyReportPhotoPreview extends StatelessWidget {
  const DailyReportPhotoPreview({super.key, required this.photos});

  final List<DailyReportPdfEvidence> photos;

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) return const SizedBox.shrink();
    final cover = photos.where((photo) => photo.photoBytes != null).firstOrNull;
    return InkWell(
      key: const ValueKey('daily-report-photo-thumbnail'),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _DailyReportPhotoGallery(
            photos: photos,
            initialIndex: cover == null ? 0 : photos.indexOf(cover),
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (cover?.photoBytes != null)
            Image.memory(
              cover!.photoBytes!,
              width: 56,
              height: 42,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.broken_image_outlined),
            )
          else
            const Icon(Icons.broken_image_outlined),
          const SizedBox(width: 6),
          Text('${photos.length} ${SkoLanguageController.tr('写真')}'),
        ],
      ),
    );
  }
}

class _DailyReportPhotoGallery extends StatefulWidget {
  const _DailyReportPhotoGallery({
    required this.photos,
    required this.initialIndex,
  });
  final List<DailyReportPdfEvidence> photos;
  final int initialIndex;

  @override
  State<_DailyReportPhotoGallery> createState() =>
      _DailyReportPhotoGalleryState();
}

class _DailyReportPhotoGalleryState extends State<_DailyReportPhotoGallery> {
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(SkoLanguageController.tr('写真'))),
    body: PageView(
      controller: _pages,
      children: [
        for (final (index, photo) in widget.photos.indexed)
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '${index + 1}/${widget.photos.length} ${photo.record.workerName}',
                ),
              ),
              Expanded(
                child: photo.photoBytes != null
                    ? InteractiveViewer(
                        minScale: 1,
                        maxScale: 5,
                        child: Center(
                          child: Image.memory(
                            photo.photoBytes!,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Center(
                              child: Text(
                                SkoLanguageController.tr('保存済み写真を読み込めませんでした'),
                              ),
                            ),
                          ),
                        ),
                      )
                    : Center(
                        child: Text(
                          SkoLanguageController.tr(
                            photo.record.storagePath.isEmpty
                                ? photo.record.missingPhotoLabel
                                : '保存済み写真を読み込めませんでした',
                          ),
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '${dailyReportPhotoLocation(photo).isEmpty ? SkoLanguageController.tr('撮影住所未取得') : dailyReportPhotoLocation(photo)}\n${dailyReportPhotoTime(photo)}',
                ),
              ),
            ],
          ),
      ],
    ),
  );
}
