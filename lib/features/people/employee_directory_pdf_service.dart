import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../common/japanese_phone.dart';
import 'people_page.dart';

class EmployeeDirectoryPdfService {
  const EmployeeDirectoryPdfService._();

  static Future<Uint8List> build({
    required String companyName,
    required List<PersonRecord> records,
    DateTime? generatedAt,
  }) async {
    final regular = await PdfGoogleFonts.notoSansJPRegular();
    final bold = await PdfGoogleFonts.notoSansJPBold();
    final now = generatedAt ?? DateTime.now();

    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(
          10 * PdfPageFormat.mm,
          10 * PdfPageFormat.mm,
          10 * PdfPageFormat.mm,
          10 * PdfPageFormat.mm,
        ),
        build: (_) => [
          pw.Stack(
            children: [
              pw.Align(
                alignment: pw.Alignment.center,
                child: pw.Text(
                  companyName.isEmpty ? '社員一覧' : companyName,
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  _date(now),
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            '社員一覧',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: const [
              '名前',
              '区分',
              '血液型',
              '職種',
              '電話番号',
              '住所',
              '緊急連絡先氏名',
              '続柄',
              '電話番号',
              '住所',
            ],
            data: [
              for (final record in records)
                [
                  record.name,
                  record.kind.label,
                  record.bloodType,
                  record.role,
                  japaneseDomesticPhone(record.phone),
                  record.address,
                  record.emergencyName,
                  record.emergencyRelation,
                  japaneseDomesticPhone(record.emergencyPhone),
                  record.emergencyAddress,
                ],
            ],
            headerStyle: pw.TextStyle(
              fontSize: 7,
              fontWeight: pw.FontWeight.bold,
            ),
            cellStyle: const pw.TextStyle(fontSize: 6.5),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColors.grey300,
            ),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.all(3),
            border: pw.TableBorder.all(
              color: PdfColors.grey500,
              width: 0.5,
            ),
          ),
        ],
      ),
    );

    return document.save();
  }

  static Future<void> printDirectory({
    required String companyName,
    required List<PersonRecord> records,
  }) {
    return Printing.layoutPdf(
      name: '社員一覧.pdf',
      format: PdfPageFormat.a4.landscape,
      onLayout: (_) => build(
        companyName: companyName,
        records: records,
      ),
    );
  }

  static String _date(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return value.year.toString() +
        '/' +
        two(value.month) +
        '/' +
        two(value.day);
  }
}

class EmployeeDirectoryPrintPreviewPage extends StatelessWidget {
  const EmployeeDirectoryPrintPreviewPage({
    super.key,
    required this.companyName,
    required this.records,
  });

  final String companyName;
  final List<PersonRecord> records;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('社員一覧 印刷プレビュー')),
      body: PdfPreview(
        build: (_) => EmployeeDirectoryPdfService.build(
          companyName: companyName,
          records: records,
        ),
        canChangePageFormat: false,
        canChangeOrientation: false,
        allowPrinting: true,
        allowSharing: true,
        pdfFileName: '社員一覧.pdf',
      ),
    );
  }
}
