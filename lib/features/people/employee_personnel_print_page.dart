import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../international/language_controller.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'people_page.dart';
import 'phone_display.dart';

enum EmployeePersonnelPreviewAction { print, send }

class EmployeePersonnelPrintPage extends StatelessWidget {
  const EmployeePersonnelPrintPage({
    super.key,
    required this.companyName,
    required this.records,
    this.action = EmployeePersonnelPreviewAction.print,
    this.onConfirmSend,
  });

  final String companyName;
  final List<PersonRecord> records;
  final EmployeePersonnelPreviewAction action;
  final Future<void> Function(BuildContext context)? onConfirmSend;

  bool get _isSend => action == EmployeePersonnelPreviewAction.send;

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
            headers: [
              SkoLanguageController.tr('名前'),
              SkoLanguageController.tr('区分'),
              SkoLanguageController.tr('血液型'),
              SkoLanguageController.tr('職種'),
              SkoLanguageController.tr('電話番号'),
              SkoLanguageController.tr('住所'),
              SkoLanguageController.tr('緊急連絡先氏名'),
              SkoLanguageController.tr('続柄'),
              SkoLanguageController.tr('緊急電話番号'),
              SkoLanguageController.tr('緊急住所'),
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
        title: Text(
          records.length == 1
              ? (SkoLanguageController.isEnglish ? 'Employee Data A4 Landscape Preview' : '社員データ A4横プレビュー')
              : (SkoLanguageController.isEnglish ? 'Employee List A4 Landscape Preview' : '社員一覧 A4横プレビュー'),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              child: InteractiveViewer(
                minScale: 0.65,
                maxScale: 5,
                boundaryMargin: const EdgeInsets.all(220),
                constrained: false,
                child: _EmployeePersonnelPreviewSheet(
                  companyName: companyName,
                  records: records,
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton.icon(
                onPressed: _isSend
                    ? () async {
                        final action = onConfirmSend;
                        if (action != null) {
                          await action(context);
                        }
                      }
                    : () => Printing.layoutPdf(
                          onLayout: (_) => _buildPdf(),
                        ),
                icon: Icon(
                  _isSend ? Icons.send_outlined : Icons.print_outlined,
                ),
                label: Text(
                  _isSend
                      ? (SkoLanguageController.isEnglish ? 'Continue to Send with This Preview' : 'このA4プレビュー内容で送信へ進む')
                      : (SkoLanguageController.isEnglish ? 'Print This A4 Preview' : 'このA4プレビュー内容を印刷'),
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _EmployeePersonnelPreviewSheet extends StatelessWidget {
  const _EmployeePersonnelPreviewSheet({
    required this.companyName,
    required this.records,
  });

  final String companyName;
  final List<PersonRecord> records;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateText =
        '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';
    final headers = <String>[
      SkoLanguageController.tr('名前'),
      SkoLanguageController.tr('区分'),
      SkoLanguageController.tr('血液型'),
      SkoLanguageController.tr('職種'),
      SkoLanguageController.tr('電話番号'),
      SkoLanguageController.tr('住所'),
      SkoLanguageController.tr('緊急連絡先氏名'),
      SkoLanguageController.tr('続柄'),
      SkoLanguageController.tr('緊急電話番号'),
      SkoLanguageController.tr('緊急住所'),
    ];

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Material(
        color: Colors.white,
        elevation: 2,
        child: SizedBox(
          width: 1188,
          height: 840,
          child: Padding(
            padding: const EdgeInsets.all(42),
            child: DefaultTextStyle(
              style: const TextStyle(color: Colors.black, fontSize: 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Text(
                        companyName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          dateText,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  Table(
                    border: TableBorder.all(color: Colors.black54, width: 0.8),
                    columnWidths: const {
                      0: FlexColumnWidth(1.25),
                      1: FlexColumnWidth(0.85),
                      2: FlexColumnWidth(0.72),
                      3: FlexColumnWidth(1.05),
                      4: FlexColumnWidth(1.2),
                      5: FlexColumnWidth(1.8),
                      6: FlexColumnWidth(1.35),
                      7: FlexColumnWidth(0.8),
                      8: FlexColumnWidth(1.25),
                      9: FlexColumnWidth(1.8),
                    },
                    children: [
                      TableRow(
                        decoration: const BoxDecoration(color: Color(0xFFE9E9E9)),
                        children: [
                          for (final header in headers)
                            _previewCell(header, bold: true),
                        ],
                      ),
                      for (final record in records)
                        TableRow(
                          children: [
                            _previewCell(record.name),
                            _previewCell(record.kind.label),
                            _previewCell(record.bloodType),
                            _previewCell(record.role),
                            _previewCell(domesticPhoneDisplay(record.phone)),
                            _previewCell(record.address),
                            _previewCell(record.emergencyName),
                            _previewCell(record.emergencyRelation),
                            _previewCell(
                              domesticPhoneDisplay(record.emergencyPhone),
                            ),
                            _previewCell(record.emergencyAddress),
                          ],
                        ),
                    ],
                  ),
                  const Spacer(),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      SkoLanguageController.isEnglish ? 'Pinch to zoom in or out' : 'ピンチ操作で拡大・縮小できます',
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _previewCell(String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 9),
        child: Text(
          value,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.black,
            fontSize: 11,
            fontWeight: bold ? FontWeight.w900 : FontWeight.w500,
          ),
        ),
      );
}
