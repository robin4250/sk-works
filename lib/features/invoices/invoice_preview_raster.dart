import 'dart:async';
import 'dart:typed_data';

/// Only actual raster pages are displayed. Native stalls and empty results are
/// recoverable display failures; the original PDF remains available for output.
Future<List<Uint8List>> collectInvoicePreviewPages(
  Stream<Uint8List> images, {
  Duration idleTimeout = const Duration(seconds: 45),
}) async {
  final pages = <Uint8List>[];
  try {
    await for (final image in images.timeout(idleTimeout)) {
      if (image.isEmpty) {
        throw StateError('PDFのページ画像が空です。再試行してください。');
      }
      pages.add(image);
    }
  } on TimeoutException {
    throw StateError('PDFの画面表示に時間がかかっています。再試行してください。');
  }
  if (pages.isEmpty) {
    throw StateError('PDFのページを表示できませんでした。再試行してください。');
  }
  return pages;
}
