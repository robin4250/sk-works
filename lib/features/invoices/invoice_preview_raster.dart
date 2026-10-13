import 'dart:async';
import 'dart:typed_data';
import '../../international/language_controller.dart';

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
        throw StateError(SkoLanguageController.tr('PDFのページ画像が空です。再試行してください。'));
      }
      pages.add(image);
    }
  } on TimeoutException {
    throw StateError(SkoLanguageController.tr('PDFの画面表示に時間がかかっています。再試行してください。'));
  }
  if (pages.isEmpty) {
    throw StateError(SkoLanguageController.tr('PDFのページを表示できませんでした。再試行してください。'));
  }
  return pages;
}

/// Printing supplies raw RGBA pixels. A failed native drawing context may return
/// a correctly sized, wholly transparent page that still encodes as valid PNG.
Future<Uint8List> encodeInvoicePreviewRaster({
  required int width,
  required int height,
  required Uint8List pixels,
  required Future<Uint8List> Function() encode,
}) async {
  if (width <= 0 || height <= 0 || pixels.length != width * height * 4) {
    throw StateError(SkoLanguageController.tr('PDFのページを描画できませんでした。再試行してください。'));
  }
  var visible = false;
  for (var alpha = 3; alpha < pixels.length; alpha += 4) {
    if (pixels[alpha] != 0) {
      visible = true;
      break;
    }
  }
  if (!visible) {
    throw StateError(SkoLanguageController.tr('PDFのページを描画できませんでした。再試行してください。'));
  }
  return encode();
}
