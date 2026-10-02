import 'dart:typed_data';

import 'package:flutter/material.dart';
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
        title: Text(
          records.length == 1
              ? '社員データ A4横プレビュー'
              : '社員一覧 A4横プレビュー',
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: PdfPreview(
              build: (_) => _buildPdf(),
              canChangeOrientation: false,
              canChangePageFormat: false,
              allowPrinting: !_isSend,
              allowSharing: false,
              pdfFileName:
                  records.length == 1 ? '社員データ.pdf' : '社員一覧.pdf',
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
                          name: records.length == 1
                              ? '社員データ.pdf'
                              : '社員一覧.pdf',
                        ),
                icon: Icon(
                  _isSend ? Icons.send_outlined : Icons.print_outlined,
                ),
                label: Text(
                  _isSend
                      ? 'このA4プレビュー内容で送信へ進む'
                      : 'このA4プレビュー内容を印刷',
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
