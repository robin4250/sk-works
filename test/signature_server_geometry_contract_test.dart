import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/daily_reports/signature_capture_page.dart';

void main() {
  final fixture = jsonDecode(File('test/fixtures/signature_input_geometry_cases.json').readAsStringSync()) as Map;
  for (final row in (fixture['cases'] as List).cast<Map>()) {
    if (!row.containsKey('expected_client_ink')) continue;
    test('shared client/server ink geometry: ${row['name']}', () {
      final value = row['value'];
      expect(signatureHasDrawableInk(SignatureResult.fromJson(value),
        canvasSize: SignatureResult.sizeFromJson(value)), row['expected_client_ink']);
    });
  }
  test('actual client codec keeps capture dimensions identical at every point', () {
    const result = SignatureResult(signerName: 'Synthetic', canvasSize: Size(600, 220),
      strokes: [[Offset(.1, .2), Offset(.2, .8)], [Offset(.4, .2), Offset(.5, .8)]]);
    final value = {'strokes': result.toJson()};
    expect(SignatureResult.sizeFromJson(value), const Size(600, 220));
    expect(signatureHasDrawableInk(SignatureResult.fromJson(value),
      canvasSize: SignatureResult.sizeFromJson(value)), isTrue);
    for (final stroke in (value['strokes'] as List)) {
      for (final point in (stroke as List).cast<Map>()) {
        expect(point.keys.toSet(), {'x', 'y', 'canvas_width', 'canvas_height'});
        expect(point['canvas_width'], 600); expect(point['canvas_height'], 220);
      }
    }
  });
}
