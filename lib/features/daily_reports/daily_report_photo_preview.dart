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
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 336.0;
      final tileWidth = width / 6;
      return Wrap(children: [
        for (final (index, photo) in photos.indexed)
          SizedBox(width: tileWidth, child: InkWell(
            key: photo == (cover ?? photos.first)
              ? const ValueKey('daily-report-photo-thumbnail')
              : ValueKey('daily-report-photo-thumbnail-$index'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => _DailyReportPhotoGallery(photos: photos, initialIndex: index))),
            child: Padding(padding: const EdgeInsets.all(2), child: Column(
              mainAxisSize: MainAxisSize.min, children: [
                SizedBox(height: 42, width: double.infinity,
                  child: photo.photoBytes != null
                    ? Image.memory(photo.photoBytes!, fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined))
                    : const Icon(Icons.broken_image_outlined)),
                Text(photo.record.workerName, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10)),
              ])),
          )),
      ]);
    });
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
    appBar: AppBar(leading: IconButton(key: const ValueKey('daily-report-photo-close'),
      tooltip: SkoLanguageController.tr('閉じる'), icon: const Icon(Icons.close),
      onPressed: () => Navigator.of(context).pop()),
      title: Text(SkoLanguageController.tr('写真'))),
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
