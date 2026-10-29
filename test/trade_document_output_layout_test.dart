import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/features/shared/trade_document_output_layout.dart';

pw.Widget proofCanvas(String side) => pw.SizedBox(
  width: PdfPageFormat.a4.width,
  height: PdfPageFormat.a4.height,
  child: pw.Stack(children: [
    pw.Positioned.fill(child: pw.Container(
      margin: const pw.EdgeInsets.all(1),
      decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
    )),
    for (final top in [true, false])
      for (final left in [true, false])
        pw.Positioned(
          top: top ? 8 : null, bottom: top ? null : 8,
          left: left ? 8 : null, right: left ? null : 8,
          child: pw.Text('$side-${top ? 'TOP' : 'BOTTOM'}-${left ? 'LEFT' : 'RIGHT'}',
            style: const pw.TextStyle(fontSize: 8)),
        ),
    pw.Positioned(left: 34, right: 34, top: 50, child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('$side COMPLETE FIXED A4 CANVAS',
          style: const pw.TextStyle(fontSize: 16)),
        pw.SizedBox(height: 20),
        for (var i = 1; i <= 24; i++)
          pw.Padding(padding: const pw.EdgeInsets.only(bottom: 12),
            child: pw.Text('$side ITEM ${i.toString().padLeft(2, '0')} retained vector text',
              style: const pw.TextStyle(fontSize: 10))),
      ],
    )),
  ]),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('three outputs consume fresh canvases once and preserve canonical input', () async {
    final output = Directory('build/trade-document-output-layout')
      ..createSync(recursive: true);
    final canonical = Uint8List.fromList([1, 2, 3, 4]);
    final original = List<int>.from(canonical);
    for (final layout in TradeDocumentOutputLayout.values) {
      var frontCalls = 0;
      var termsCalls = 0;
      final bytes = await composeTradeDocumentOutput(
        layout: layout,
        // A4 canonical shortcut is checked separately; alternate layouts must
        // ignore canonical bytes and never reinterpret a signed original.
        canonicalBytes: layout == TradeDocumentOutputLayout.a4TwoPages ? null : canonical,
        frontA4: () async { frontCalls++; return proofCanvas('FRONT'); },
        termsA4: () async { termsCalls++; return proofCanvas('TERMS'); },
      );
      expect(frontCalls, 1);
      expect(termsCalls, 1);
      expect(canonical, original);
      expect(bytes.take(5).toList(), [37, 80, 68, 70, 45]);
      File('${output.path}/${layout.name}.pdf').writeAsBytesSync(bytes);
    }
  });

  test('saved legacy original is returned byte-identical without factories or terms', () async {
    final legacy = pw.Document()..addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (_) => pw.Text('LEGACY SAVED ORIGINAL - NO TERMS'),
    ));
    final canonical = await legacy.save();
    final before = List<int>.from(canonical);
    final result = await composeTradeDocumentOutput(
      layout: TradeDocumentOutputLayout.a4TwoPages, canonicalBytes: canonical,
      frontA4: () async => throw StateError('Must not regenerate original'),
      termsA4: () async => throw StateError('Must not attach terms to legacy'),
    );
    expect(identical(result, canonical), isTrue);
    expect(result, before);
    File('build/trade-document-output-layout/legacy-original.pdf').writeAsBytesSync(result);
  });

  test('rejected unknown contract or failed terms propagates with no output fallback', () async {
    var termsCalls = 0;
    await expectLater(composeTradeDocumentOutput(
      layout: TradeDocumentOutputLayout.a3Landscape,
      frontA4: () async => throw StateError('Unknown validated snapshot contract'),
      termsA4: () async { termsCalls++; return proofCanvas('TERMS'); },
    ), throwsStateError);
    expect(termsCalls, 0);
    await expectLater(composeTradeDocumentOutput(
      layout: TradeDocumentOutputLayout.a4Duplex,
      frontA4: () async => proofCanvas('FRONT'),
      termsA4: () async => throw StateError('Unverified terms reference'),
    ), throwsStateError);
  });

  test('reused mutable canvas and empty canonical fail closed', () async {
    final shared = proofCanvas('SHARED');
    await expectLater(composeTradeDocumentOutput(
      layout: TradeDocumentOutputLayout.a3Landscape,
      frontA4: () async => shared, termsA4: () async => shared,
    ), throwsStateError);
    await expectLater(composeTradeDocumentOutput(
      layout: TradeDocumentOutputLayout.a4TwoPages, canonicalBytes: Uint8List(0),
      frontA4: () async => throw StateError('No fallback'),
      termsA4: () async => throw StateError('No fallback'),
    ), throwsArgumentError);
  });
}
