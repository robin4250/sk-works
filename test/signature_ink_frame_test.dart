import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/daily_reports/signature_capture_page.dart';
import 'package:sk_works/features/daily_reports/daily_report_pdf_service.dart';

void main() {
  test('ink bounds retain captured pixel geometry and stroke padding', () {
    final bounds = signatureInkBounds([
      [const Offset(.25, .25), const Offset(.75, .75)],
    ], const Size(800, 200));
    expect(bounds.left, closeTo(197.6, .001));
    expect(bounds.top, closeTo(47.6, .001));
    expect(bounds.width, closeTo(404.8, .001));
    expect(bounds.height, closeTo(104.8, .001));
  });
  test('empty and point-only signatures have finite nonzero bounds', () {
    expect(signatureInkBounds([], const Size(400, 120)),
        const Rect.fromLTWH(0, 0, 400, 120));
    final dot = signatureInkBounds([
      [const Offset(.5, .5)],
    ], const Size(400, 120));
    expect(dot.width, closeTo(4.8, .001));
    expect(dot.height, closeTo(4.8, .001));
  });
  test('report SVG trims blank margins without changing saved strokes', () {
    final signature = [[{'x': .25, 'y': .25}, {'x': .75, 'y': .75}]];
    final original = DailyReportPdfService.signatureSvg(signature)!;
    final fitted = DailyReportPdfService.signatureSvg(signature, fitInk: true)!;
    expect(original, contains('viewBox="0 0 400 120"'));
    expect(fitted, isNot(contains('viewBox="0 0 400 120"')));
    expect(fitted, contains('points="100.0,30.0 300.0,90.0"'));
    expect(signature.first.first['x'], .25);
  });
}
