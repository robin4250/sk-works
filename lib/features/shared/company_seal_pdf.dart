import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Generates a company-specific square seal from the registered company name.
/// No company name or seal bitmap is embedded in the application.
class CompanySealPdf {
  const CompanySealPdf._();

  static List<String> verticalColumns(String companyName) {
    final name = companyName.trim();
    if (name.isEmpty) return const [];
    // Japanese square seals traditionally read from the right-hand column.
    final chars = name.runes.map(String.fromCharCode).toList();
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

  static pw.Widget build(String companyName, {double size = 42}) {
    final columns = verticalColumns(companyName);
    if (columns.isEmpty) return pw.SizedBox(width: size, height: size);
    final red = PdfColor.fromHex('#FF0000');
    return pw.Container(
      width: size,
      height: size,
      padding: const pw.EdgeInsets.all(2),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: red, width: 1.55),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
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
                        fit: pw.BoxFit.contain,
                        child: pw.Text(
                          String.fromCharCode(rune),
                          style: pw.TextStyle(
                            color: red,
                            fontSize: size * .24,
                            fontWeight: pw.FontWeight.bold,
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
