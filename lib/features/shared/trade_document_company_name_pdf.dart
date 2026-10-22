import 'package:pdf/widgets.dart' as pw;

/// Positions an already-authorized saved seal over the end of the printed name.
/// This helper owns layout only: it never looks up or replaces seal metadata.
class TradeDocumentCompanyNamePdf {
  const TradeDocumentCompanyNamePdf._();

  static pw.Widget build({
    required String name,
    required pw.Font textFont,
    required double fontSize,
    required double labelWidth,
    required double sealSize,
    required pw.Widget seal,
  }) => pw.LayoutBuilder(builder: (context, constraints) {
    final width = constraints?.maxWidth;
    if (width == null || !width.isFinite || width <= labelWidth + sealSize) {
      throw StateError('帳票の社名欄の幅を確認できません。');
    }
    double measure(String text) =>
        textFont.getFont(context).stringMetrics(text).advanceWidth * fontSize;
    // Reserve half of the seal beyond the name, including in a compact column.
    final textWidth = width - labelWidth - sealSize / 2;
    final lines = <String>[];
    var line = '';
    for (final rune in name.runes) {
      final character = String.fromCharCode(rune);
      if (character == '\n') {
        lines.add(line);
        line = '';
      } else {
        if (line.isNotEmpty && measure('$line$character') > textWidth) {
          lines.add(line);
          line = '';
        }
        line += character;
      }
    }
    lines.add(line);
    final lineHeight = fontSize * 1.4;
    final padding = (sealSize - lineHeight) / 2;
    final sealLeft = (labelWidth + measure(lines.last) - sealSize / 2)
        .clamp(labelWidth, width - sealSize).toDouble();
    final style = pw.TextStyle(font: textFont, fontSize: fontSize);
    return pw.Stack(children: [
      pw.Padding(
        padding: pw.EdgeInsets.symmetric(vertical: padding),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(width: labelWidth, height: lineHeight,
            child: pw.Align(alignment: pw.Alignment.centerLeft,
              child: pw.Text('社名：', style: style))),
          pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [for (final value in lines)
              pw.SizedBox(width: textWidth, height: lineHeight,
                child: pw.Align(alignment: pw.Alignment.centerLeft,
                  child: pw.Text(value, style: style))),
            ])),
        ]),
      ),
      pw.Positioned(left: sealLeft, top: (lines.length - 1) * lineHeight,
        child: seal),
    ]);
  });
}
