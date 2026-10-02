import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'people_page.dart';
import 'phone_display.dart';

class EmployeePersonnelPrintPage extends StatelessWidget {
  const EmployeePersonnelPrintPage({
    super.key,
    required this.companyName,
    required this.records,
  });

  final String companyName;
  final List<PersonRecord> records;

  Future<Uint8List> _buildPdf() async {
    final regular = await PdfGoogleFonts.notoSansJPRegular();
    final bold = await PdfGoogleFonts.notoSansJPBold();
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );
    final now = DateTime.now();
    final dateText =
        '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(10 * PdfPageFormat.mm),
        header: (_) => pw.Stack(
          children: [
            pw.Align(
              alignment: pw.Alignment.center,
              child: pw.Text(
                companyName,
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(dateText),
            ),
          ],
        ),
        build: (_) => [
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColors.grey300,
            ),
            cellStyle: const pw.TextStyle(fontSize: 7.5),
            cellAlignment: pw.Alignment.centerLeft,
            headers: const [
              '名前',
              '区分',
              '血液型',
              '職種',
              '電話番号',
              '住所',
              '緊急連絡先氏名',
              '続柄',
              '緊急電話番号',
              '緊急住所',
            ],
            data: [
              for (final record in records)
                [
                  record.name,
                  record.kind.label,
                  record.bloodType,
                  record.role,
                  domesticPhoneDisplay(record.phone),
                  record.address,
                  record.emergencyName,
                  record.emergencyRelation,
                  domesticPhoneDisplay(record.emergencyPhone),
                  record.emergencyAddress,
                ],
            ],
          ),
        ],
      ),
    );

    return document.save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('社員一覧 A4横プレビュー'),
      ),
      body: PdfPreview(
        build: (_) => _buildPdf(),
        canChangeOrientation: false,
        canChangePageFormat: false,
        allowPrinting: true,
        allowSharing: true,
        pdfFileName: '社員一覧.pdf',
      ),
    );
  }
}
