import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Generates a company-specific square seal from the registered company name.
/// No company name or seal bitmap is embedded in the application.
class CompanySealPdf {
  const CompanySealPdf._();

  static Future<ByteData>? _fontData;

  /// Cache immutable asset data, not a font's document-bound mutable state.
  /// Every PDF document receives its own font wrapper, including concurrent
  /// invoice/payroll rendering. A failed asset load can be retried.
  static Future<pw.Font> loadFont() async =>
      pw.Font.ttf(await (_fontData ??= _loadFontData()));

  static Future<ByteData> _loadFontData() async {
    try {
      return await rootBundle.load(
        'assets/fonts/company-seal/niseten.ttf',
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
  }) {
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
                      child: pw.Builder(
                        builder: (context) {
                          final primary = (font ?? pw.Font.helvetica())
                              .getFont(context);
                          // Select the font before measuring: fallback glyphs
                          // have different bearings and ink bounds.
                          final selected = primary.isRuneSupported(rune)
                              ? primary
                              : (fallbackFont?.getFont(context) ?? primary);
                          final metrics = selected.glyphMetrics(rune);
                          return pw.CustomPaint(
                            size: PdfPoint(size, size),
                            painter: (canvas, cell) {
                              if (metrics.width <= 0 || metrics.height <= 0) {
                                return;
                              }
                              // Fit actual glyph ink rather than the font's
                              // ascent/descent line box. Seal lettering fills
                              // each vertical cell without clipping strokes.
                              final inkWidth = cell.x * .92;
                              final inkHeight = cell.y * .92;
                              final fontSize = inkHeight / metrics.height;
                              final horizontalScale =
                                  inkWidth / (metrics.width * fontSize);
                              canvas
                                ..saveContext()
                                ..setFillColor(red)
                                ..setStrokeColor(red)
                                ..setLineWidth(
                                  (cell.x < cell.y ? cell.x : cell.y) * .035,
                                )
                                ..drawString(
                                  selected,
                                  fontSize,
                                  String.fromCharCode(rune),
                                  (cell.x - inkWidth) / 2 -
                                      metrics.left * fontSize * horizontalScale,
                                  (cell.y - inkHeight) / 2 -
                                      metrics.top * fontSize,
                                  scale: horizontalScale,
                                  mode: PdfTextRenderingMode.fillAndStroke,
                                )
                                ..restoreContext();
                            },
                          );
                        },
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
