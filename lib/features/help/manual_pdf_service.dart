import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../international/language_controller.dart';
import '../shared/pdf_bytes_cache.dart';
import 'manual_content.dart';
import 'manual_version.dart';

class ManualPdfService {
  const ManualPdfService._();

  static Future<Uint8List> buildRoleManual(
    ManualRole role, {
    PdfPageFormat format = PdfPageFormat.a4,
    pw.Font? regularFont,
    pw.Font? boldFont,
  }) {
    return _build(
      title: 'SKO ${ManualContent.roleLabel(role)}用説明書',
      sections: ManualContent.forRole(role),
      format: format,
      regularFont: regularFont,
      boldFont: boldFont,
    );
  }

  static Future<Uint8List> buildPamphlet({
    PdfPageFormat format = PdfPageFormat.a4,
    pw.Font? regularFont,
    pw.Font? boldFont,
  }) {
    return _build(
      title: 'SKO ベータ版パンフレット',
      sections: ManualContent.pamphlet,
      format: format,
      regularFont: regularFont,
      boldFont: boldFont,
    );
  }

  static Future<Uint8List> buildChapter(ManualSection section, {
    PdfPageFormat format = PdfPageFormat.a4,
    pw.Font? regularFont,
    pw.Font? boldFont,
  }) => _build(title: 'SKO ベータ版 / ${section.title}',
    sections: [section], format: format,
    regularFont: regularFont, boldFont: boldFont);

  static Future<Uint8List> _build({
    required String title,
    required List<ManualSection> sections,
    required PdfPageFormat format,
    pw.Font? regularFont,
    pw.Font? boldFont,
  }) async {
    final regular = regularFont ?? await PdfGoogleFonts.notoSansJPRegular();
    final bold = boldFont ?? await PdfGoogleFonts.notoSansJPBold();
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );

    // Each feature is independently paginated. The safeguard scales with
    // actual text rather than imposing a total brochure/manual page cap.
    int pageBudget(Iterable<String> text) =>
        20 + text.fold<int>(0, (length, value) => length + value.length) ~/ 100;
    pw.Widget footer(pw.Context context) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 10),
      child: pw.Row(children: [
        pw.Expanded(child: pw.Text(ManualVersion.label,
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700))),
        pw.Text('${context.pageNumber} / ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8)),
      ]),
    );
    document.addPage(pw.MultiPage(
      pageFormat: format,
      margin: const pw.EdgeInsets.all(14 * PdfPageFormat.mm),
      maxPages: pageBudget(sections.map((section) => section.title)),
      footer: footer,
      build: (_) => [
        pw.Anchor(name: 'contents', child: pw.Text(title,
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold))),
        pw.SizedBox(height: 12),
        pw.Text('機能別目次', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.Text('項目を押すと該当する機能の説明へ移動します。必要な説明は機能ごとに追加します。'),
        pw.SizedBox(height: 12),
        for (var i = 0; i < sections.length; i++)
          pw.Link(destination: 'feature-$i', child: pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 5),
            child: pw.Text('${i + 1}. ${sections[i].title}',
              style: const pw.TextStyle(color: PdfColors.blue700)),
          )),
      ],
    ));
    for (var i = 0; i < sections.length; i++) {
      final section = sections[i];
      document.addPage(pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(14 * PdfPageFormat.mm),
        maxPages: pageBudget([section.title, section.summary,
          section.support, section.buttonLabel, ...section.steps]),
        header: (_) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 10),
          child: pw.Text(title, style: const pw.TextStyle(
            fontSize: 10, color: PdfColors.blue700)),
        ),
        footer: footer,
        build: (_) => [
          pw.Anchor(name: 'feature-$i', child: pw.Text(section.title,
            style: pw.TextStyle(fontSize: 23, fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue900))),
          pw.SizedBox(height: 8),
          pw.Text(section.summary, overflow: pw.TextOverflow.span),
          pw.SizedBox(height: 12),
          pw.Text('操作手順', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
          for (var step = 0; step < section.steps.length; step++) ...[
            pw.Text('${step + 1}. ${section.steps[step]}', overflow: pw.TextOverflow.span),
            pw.SizedBox(height: 10),
          ],
          pw.SizedBox(height: 12),
          _screenMock(section),
          pw.SizedBox(height: 12),
          pw.Text('サポート・補足', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text(section.support, overflow: pw.TextOverflow.span),
          pw.SizedBox(height: 12),
          pw.Link(destination: 'contents', child: pw.Text('機能別目次へ戻る',
            style: const pw.TextStyle(color: PdfColors.blue700))),
        ],
      ));
    }
    return document.save();
  }

  static pw.Widget _screenMock(ManualSection section) => pw.Container(
    padding: const pw.EdgeInsets.all(12),
    decoration: pw.BoxDecoration(color: PdfColors.blue50,
      border: pw.Border.all(color: PdfColors.blue700),
      borderRadius: pw.BorderRadius.circular(8)),
    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('操作の目印（画面イメージ）',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.Text('ここを押す：${section.buttonLabel}',
          style: pw.TextStyle(color: PdfColors.blue900,
            fontWeight: pw.FontWeight.bold)),
      ]),
  );

  static String fileNameForRole(ManualRole role) =>
      'SKO_ベータ版_${ManualContent.roleLabel(role)}用説明書.pdf';

  static const pamphletFileName = 'SKO_ベータ版パンフレット.pdf';
}

class ManualPdfPreviewPage extends StatefulWidget {
  const ManualPdfPreviewPage.chapter({super.key, required ManualSection section})
      : _section = section, _role = null, _pamphlet = false;

  const ManualPdfPreviewPage.role({
    super.key,
    required ManualRole role,
  })  : _section = null, _role = role,
        _pamphlet = false;

  const ManualPdfPreviewPage.pamphlet({super.key})
      : _section = null, _role = null,
        _pamphlet = true;

  final ManualSection? _section;
  final ManualRole? _role;
  final bool _pamphlet;

  @override
  State<ManualPdfPreviewPage> createState() => _ManualPdfPreviewPageState();
}

class _ManualPdfPreviewPageState extends State<ManualPdfPreviewPage> {
  final _pdfBytes = PdfBytesCache();

  @override
  void didUpdateWidget(covariant ManualPdfPreviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget._role != widget._role || oldWidget._pamphlet != widget._pamphlet || oldWidget._section != widget._section) {
      _pdfBytes.invalidate();
    }
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    final section = widget._section;
    final role = widget._role;
    final pamphlet = widget._pamphlet;
    final title = section?.title ?? (pamphlet
        ? 'SKOパンフレット'
        : '${ManualContent.roleLabel(role!)}用説明書');

    return Scaffold(
      appBar: AppBar(title: Text(SkoLanguageController.tr(title))),
      body: PdfPreview(
        initialPageFormat: PdfPageFormat.a4,
        canChangePageFormat: false,
        canChangeOrientation: false,
        allowPrinting: true,
        allowSharing: true,
        pdfFileName: section != null
            ? 'SKO_ベータ版_${section.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.pdf'
            : pamphlet
            ? ManualPdfService.pamphletFileName
            : ManualPdfService.fileNameForRole(role!),
        build: (format) => _pdfBytes.get(
          () => section != null
              ? ManualPdfService.buildChapter(section, format: format)
              : pamphlet
              ? ManualPdfService.buildPamphlet(format: format)
              : ManualPdfService.buildRoleManual(role!, format: format),
        ),
      ),
    );
  }
}

