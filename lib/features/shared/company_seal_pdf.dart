import 'dart:typed_data';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Generates a company-specific square seal from the registered company name.
/// No company name or seal bitmap is embedded in the application.
class CompanySealPdf {
  const CompanySealPdf._();

  static Future<ByteData>? _fontData;
  static Future<ByteData>? _reishoFontData;
  static Future<Set<int>>? _reishoCoverage;
  static Set<int>? _loadedReishoCoverage;
  static const legacyStyle = 'legacy';
  static const reishoStyle = 'aoyagi_reisho';
  static const _reishoAssets = 'assets/fonts/company-seal/aoyagi-reisho';

  static Future<pw.Font> loadStyleFont(String style) async {
    if (style == legacyStyle) return loadFont();
    if (style != reishoStyle) throw StateError('Unknown company seal style.');
    try {
      await unsupportedReishoCharacters('');
      return pw.Font.ttf(await (_reishoFontData ??=
          rootBundle.load('$_reishoAssets/AoyagiReisho.ttf')));
    } catch (_) {
      _reishoFontData = null;
      rethrow;
    }
  }

  static Future<String> unsupportedReishoCharacters(String name) async {
    try {
      final coverage = await (_reishoCoverage ??= rootBundle
          .loadString('$_reishoAssets/coverage.json')
          .then((value) => (jsonDecode(value) as List).cast<int>().toSet()));
      _loadedReishoCoverage = coverage;
      return String.fromCharCodes(name.runes
          .where((rune) => !coverage.contains(rune)).toSet());
    } catch (_) {
      _reishoCoverage = null;
      rethrow;
    }
  }

  /// Preserve every rune; choose near-square cells instead of squeezing glyphs.
  static List<String> balancedColumns(String name) {
    final chars = name.trim().runes.toList();
    if (chars.isEmpty) return const [];
    var bestColumns = 1;
    var bestScore = double.infinity;
    for (var columns = 1; columns <= math.min(chars.length, 8); columns++) {
      final rows = (chars.length / columns).ceil();
      final score = math.max(columns, rows).toDouble() +
          (columns * rows - chars.length) * 0.001;
      if (score < bestScore) {
        bestScore = score;
        bestColumns = columns;
      }
    }
    final rows = (chars.length / bestColumns).ceil();
    return [for (var offset = 0; offset < chars.length; offset += rows)
      String.fromCharCodes(chars.sublist(offset,
          math.min(offset + rows, chars.length)))];
  }

  static double reishoGlyphSize(String name, double size) {
    final columns = balancedColumns(name);
    if (columns.isEmpty) return 0;
    final rows = columns.map((column) => column.runes.length)
        .reduce(math.max);
    return size * 0.85 * 0.82 / math.max(columns.length, rows);
  }

  static pw.Widget _buildReisho(String name, double size, pw.Font font) {
    final coverage = _loadedReishoCoverage;
    if (coverage == null || name.runes.any((rune) => !coverage.contains(rune))) {
      throw StateError('The registered company name is unsupported by Reisho.');
    }
    final columns = balancedColumns(name);
    if (columns.isEmpty) return pw.SizedBox(width: size, height: size);
    final rows = columns.map((column) => column.runes.length).reduce(math.max);
    final cellSize = size * 0.85 / math.max(columns.length, rows);
    return pw.Container(
      width: size,
      height: size,
      padding: pw.EdgeInsets.all(size * 0.04),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.red, width: size * 0.04),
      ),
      child: pw.Center(child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [for (final column in columns.reversed) pw.Column(
          children: [for (final rune in column.runes) pw.SizedBox(
            width: cellSize,
            height: cellSize,
            child: pw.Center(child: pw.Text(String.fromCharCode(rune),
              style: pw.TextStyle(font: font, fontSize: cellSize * 0.82,
                  color: PdfColors.red))),
          )],
        )],
      )),
    );
  }

  /// Cache immutable asset data, not a font's document-bound mutable state.
  /// Every PDF document receives its own font wrapper, including concurrent
  /// invoice/payroll rendering. A failed asset load can be retried.
  static Future<pw.Font> loadFont() async =>
      pw.Font.ttf(await (_fontData ??= _loadFontData()));

  static Future<ByteData> _loadFontData() async {
    try {
      return await rootBundle.load(
        'assets/fonts/company-seal/NotoSansJP-Bold.ttf',
      );
    } catch (_) {
      _fontData = null;
      rethrow;
    }
  }

  static List<String> verticalColumns(String companyName) {
    final name = companyName.trim();
    if (name.isEmpty) return const [];
    // Japanese square seals traditionally read from the right-hand column.
    final chars = name.runes.map(String.fromCharCode).toList();
    if (name.startsWith('株式会社') && chars.length > 4) {
      final core = chars.sublist(4);
      final pivot = (core.length / 2).ceil();
      return ['株式会社', core.take(pivot).join(), core.skip(pivot).join()];
    }
    if (name.endsWith('株式会社') && chars.length > 4) {
      final core = chars.sublist(0, chars.length - 4);
      final pivot = (core.length / 2).ceil();
      return [core.take(pivot).join(), core.skip(pivot).join(), '株式会社'];
    }
    final chunk = (chars.length / 3).ceil();
    return [
      chars.take(chunk).join(),
      chars.skip(chunk).take(chunk).join(),
      chars.skip(chunk * 2).join(),
    ].where((part) => part.isNotEmpty).toList();
  }

  static pw.Widget build(
    String companyName, {
    double size = 42,
    pw.Font? font,
    pw.Font? fallbackFont,
    String style = legacyStyle,
  }) {
    if (style == reishoStyle) {
      if (font == null) throw StateError('Reisho font must be loaded explicitly.');
      return _buildReisho(companyName, size, font);
    }
    if (style != legacyStyle) throw StateError('Unknown company seal style.');
    final columns = verticalColumns(companyName);
    if (columns.isEmpty) return pw.SizedBox(width: size, height: size);
    final red = PdfColor.fromHex('#FF0000');
    return pw.Container(
      width: size,
      height: size,
      padding: pw.EdgeInsets.all(size * .025),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: red, width: size * (2.0 / 42)),
        borderRadius: pw.BorderRadius.all(
          pw.Radius.circular(size * (3.0 / 42)),
        ),
      ),
      child: pw.Row(
        children: [
          for (final column in columns.reversed)
            pw.Expanded(
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                children: [
                  for (final rune in column.runes)
                    pw.Expanded(
                      child: pw.FittedBox(
                        fit: pw.BoxFit.fill,
                        child: pw.Text(
                          String.fromCharCode(rune),
                          style: pw.TextStyle(
                            color: red,
                            fontSize: size * .24,
                            font: font,
                            // Keep rare registered characters visible using the
                            // document's full Japanese font when absent here.
                            fontFallback: fallbackFont == null
                                ? const []
                                : [fallbackFont],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
