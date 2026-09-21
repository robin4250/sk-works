import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'manual_content.dart';

class ManualPdfService {
  const ManualPdfService._();

  static Future<Uint8List> buildRoleManual(
    ManualRole role, {
    PdfPageFormat format = PdfPageFormat.a4,
  }) {
    return _build(
      title: 'SKO ${ManualContent.roleLabel(role)}用説明書',
      sections: ManualContent.forRole(role),
      format: format,
    );
  }

  static Future<Uint8List> buildPamphlet({
    PdfPageFormat format = PdfPageFormat.a4,
  }) {
    return _build(
      title: 'SKO ベータ版パンフレット',
      sections: ManualContent.pamphlet,
      format: format,
    );
  }

  static Future<Uint8List> _build({
    required String title,
    required List<ManualSection> sections,
    required PdfPageFormat format,
  }) async {
    final regular = await PdfGoogleFonts.notoSansJPRegular();
    final bold = await PdfGoogleFonts.notoSansJPBold();
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );

    for (var i = 0; i < sections.length; i++) {
      final section = sections[i];
      document.addPage(
        pw.Page(
          pageFormat: format,
          margin: const pw.EdgeInsets.all(14 * PdfPageFormat.mm),
          build: (_) => _page(
            title: title,
            section: section,
            page: i + 1,
            total: sections.length,
          ),
        ),
      );
    }

    return document.save();
  }

  static pw.Widget _page({
    required String title,
    required ManualSection section,
    required int page,
    required int total,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: pw.BoxDecoration(
            color: PdfColors.blue700,
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 15,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                '$page / $total',
                style: const pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 14),
        pw.Text(
          section.title,
          style: pw.TextStyle(
            fontSize: 23,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blue900,
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: PdfColors.blue50,
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Text(section.summary),
        ),
        pw.SizedBox(height: 14),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 6,
              child: _steps(section),
            ),
            pw.SizedBox(width: 14),
            pw.Expanded(
              flex: 5,
              child: _screenMock(section),
            ),
          ],
        ),
        pw.Spacer(),
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: PdfColors.amber50,
            border: pw.Border.all(color: PdfColors.amber700),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                width: 22,
                height: 22,
                decoration: const pw.BoxDecoration(
                  color: PdfColors.amber700,
                  shape: pw.BoxShape.circle,
                ),
                alignment: pw.Alignment.center,
                child: pw.Text(
                  '!',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'サポート・補足が出るタイミング',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(section.support),
                  ],
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          'ベータ版：アプリの大幅更新時は、説明書・パンフレットもセットで更新します。',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ],
    );
  }

  static pw.Widget _steps(ManualSection section) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          '操作手順',
          style: pw.TextStyle(
            fontSize: 15,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 8),
        for (var i = 0; i < section.steps.length; i++) ...[
          pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 8),
            padding: const pw.EdgeInsets.all(9),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: pw.BorderRadius.circular(7),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: 24,
                  height: 24,
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.blue700,
                    shape: pw.BoxShape.circle,
                  ),
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    '${i + 1}',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(child: pw.Text(section.steps[i])),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static pw.Widget _screenMock(ManualSection section) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          '画面イメージ',
          style: pw.TextStyle(
            fontSize: 15,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Container(
          height: 310,
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            border: pw.Border.all(color: PdfColors.grey500, width: 1.5),
            borderRadius: pw.BorderRadius.circular(16),
          ),
          child: pw.Column(
            children: [
              pw.Container(
                height: 22,
                decoration: pw.BoxDecoration(
                  color: PdfColors.blue700,
                  borderRadius: pw.BorderRadius.circular(6),
                ),
              ),
              pw.SizedBox(height: 12),
              for (var i = 0; i < 3; i++) ...[
                pw.Container(
                  height: 28,
                  margin: const pw.EdgeInsets.only(bottom: 8),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white,
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                ),
              ],
              pw.Spacer(),
              pw.Container(
                padding: const pw.EdgeInsets.all(4),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                    color: PdfColors.red600,
                    width: 3,
                  ),
                  borderRadius: pw.BorderRadius.circular(12),
                ),
                child: pw.Container(
                  height: 48,
                  alignment: pw.Alignment.center,
                  decoration: pw.BoxDecoration(
                    color: PdfColors.blue700,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Text(
                    section.buttonLabel,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'ここを押す',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  color: PdfColors.red700,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String fileNameForRole(ManualRole role) =>
      'SKO_${ManualContent.roleLabel(role)}用説明書.pdf';

  static const pamphletFileName = 'SKO_ベータ版パンフレット.pdf';
}

class ManualPdfPreviewPage extends StatelessWidget {
  const ManualPdfPreviewPage.role({
    super.key,
    required ManualRole role,
  })  : _role = role,
        _pamphlet = false;

  const ManualPdfPreviewPage.pamphlet({super.key})
      : _role = null,
        _pamphlet = true;

  final ManualRole? _role;
  final bool _pamphlet;

  @override
  Widget build(BuildContext context) {
    final role = _role;
    final title = _pamphlet
        ? 'SKOパンフレット'
        : '${ManualContent.roleLabel(role!)}用説明書';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: PdfPreview(
        initialPageFormat: PdfPageFormat.a4,
        canChangePageFormat: false,
        canChangeOrientation: false,
        allowPrinting: true,
        allowSharing: true,
        pdfFileName: _pamphlet
            ? ManualPdfService.pamphletFileName
            : ManualPdfService.fileNameForRole(role!),
        build: (format) => _pamphlet
            ? ManualPdfService.buildPamphlet(format: format)
            : ManualPdfService.buildRoleManual(role!, format: format),
      ),
    );
  }
}
