import 'dart:typed_data';

import 'package:pdf/pdf.dart';
// pdf 3.13.1 exposes catalog.params but does not re-export its dictionary type.
// This pinned format primitive is used only for standard viewer preferences.
// ignore: implementation_imports
import 'package:pdf/src/pdf/format/dict.dart' show PdfDict;
import 'package:pdf/widgets.dart' as pw;

enum TradeDocumentOutputLayout { a4TwoPages, a3Landscape, a4Duplex }

/// Arranges already validated, fresh full-A4 canvases; never parses or upgrades
/// a saved document contract. The caller must validate known immutable snapshots
/// and its live output scope before and after awaiting this function.
///
/// Factories include their own inner margins and must return separate widgets.
/// A3 keeps each A4 canvas at 100% vector size. Duplex is a viewer/driver request,
/// not a guarantee that a printer will honor two-sided long-edge output.
Future<Uint8List> composeTradeDocumentOutput({
  required TradeDocumentOutputLayout layout,
  required Future<pw.Widget> Function() frontA4,
  required Future<pw.Widget> Function() termsA4,
  Uint8List? canonicalBytes,
}) async {
  if (layout == TradeDocumentOutputLayout.a4TwoPages && canonicalBytes != null) {
    if (canonicalBytes.isEmpty) {
      throw ArgumentError.value(canonicalBytes, 'canonicalBytes', 'Empty document');
    }
    // Includes legacy one-page or signed originals. No added terms, factories,
    // parsing, mutation, recompression or re-signing of those bytes.
    return canonicalBytes;
  }

  final front = await frontA4();
  final terms = await termsA4();
  if (identical(front, terms)) {
    throw StateError('Front and terms factories must return fresh canvases.');
  }
  final document = pw.Document();
  document.document.catalog.params['/ViewerPreferences'] = PdfDict({
    '/PrintScaling': const PdfName('/None'),
    if (layout == TradeDocumentOutputLayout.a4Duplex)
      '/Duplex': const PdfName('/DuplexFlipLongEdge'),
  });
  pw.Widget canvas(pw.Widget child) => pw.SizedBox(
    width: PdfPageFormat.a4.width,
    height: PdfPageFormat.a4.height,
    child: child,
  );
  if (layout == TradeDocumentOutputLayout.a3Landscape) {
    document.addPage(pw.Page(
      pageFormat: PdfPageFormat.a3.landscape,
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [canvas(front), canvas(terms)],
      ),
    ));
  } else {
    for (final child in [front, terms]) {
      document.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => canvas(child),
      ));
    }
  }
  return document.save();
}
