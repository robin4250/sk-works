import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/features/shared/company_seal_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'seal fits glyph ink instead of reserving font line-height whitespace',
    () async {
      final document = pw.Document();
      final font = await CompanySealPdf.loadFont();
      document.addPage(
        pw.Page(
          pageFormat: const PdfPageFormat(100, 100),
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Stack(
            children: [
              pw.Positioned(
                left: 20,
                top: 20,
                child: CompanySealPdf.build('建', font: font),
              ),
            ],
          ),
        ),
      );
      final directory = Directory.systemTemp.createTempSync('seal-ink-');
      try {
        final file = File('${directory.path}/seal.pdf');
        await file.writeAsBytes(await document.save());
        final output = Platform.environment['SKO_PDF_OUTPUT_DIR'];
        if (output != null) {
          await Directory(output).create(recursive: true);
          await file.copy('$output/company_seal_ink.pdf');
        }
        final result = Process.runSync('python3', [
          '-c',
          r'''
import fitz, sys
pdf = fitz.open(sys.argv[1])
page = pdf[0]
# Crop inside the rounded frame so its red border cannot satisfy the test.
image = page.get_pixmap(matrix=fitz.Matrix(12, 12),
                       clip=fitz.Rect(23.5, 23.5, 58.5, 58.5), alpha=False)
points = []
data = image.samples
for y in range(image.height):
    for x in range(image.width):
        offset = (y * image.width + x) * image.n
        r, g, b = data[offset:offset + 3]
        if r > 160 and g < 100 and b < 100:
            points.append((x, y))
assert points, 'The company glyph must produce visible red ink'
width = max(x for x, y in points) - min(x for x, y in points) + 1
height = max(y for x, y in points) - min(y for x, y in points) + 1
assert width > image.width * .80, (width, image.width)
assert height > image.height * .80, (height, image.height)
assert '建' in page.get_text(), 'Registered glyph must remain PDF text'
''',
          file.path,
        ]);
        expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      } finally {
        directory.deleteSync(recursive: true);
      }
    },
    skip: Platform.environment['SKO_PDF_FONT_PATH'] == null
        ? 'Set SKO_PDF_FONT_PATH in the real-PDF integration lane (PyMuPDF).'
        : false,
  );
}
