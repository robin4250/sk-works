import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'payroll_statement_repository.dart';
import '../shared/company_seal_pdf.dart';

class PayrollPdfService {
  const PayrollPdfService._();

  static Future<Uint8List> buildPdf(
    PayrollStatementRecord statement, {
    PdfPageFormat format = PdfPageFormat.a4,
    pw.Font? regularFont,
    pw.Font? boldFont,
  }) async {
    final regular = regularFont ?? await PdfGoogleFonts.notoSansJPRegular();
    final bold = boldFont ?? await PdfGoogleFonts.notoSansJPBold();
    final sealFont = await CompanySealPdf.loadFont();
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );

    final detail = statement.detail;
    final earnings = _pick(detail, const ['基本給', '残業手当', '交通費', '出勤に基づく支給額']);
    final deductions = _pick(detail, const [
      '健康保険料',
      '所得税',
      '住民税',
      '道具代',
      '社会保険',
    ]);

    final configuredEarnings = _configuredMoneyEntries(
      detail,
      key: 'custom_earnings',
    );
    final configuredDeductions = _configuredMoneyEntries(
      detail,
      key: 'custom_deductions',
    );
    final adjustmentEarnings = _customMoneyEntries(detail, direction: 1);
    final adjustmentDeductions = _customMoneyEntries(detail, direction: -1);
    // Legacy aggregate placeholders are intentionally not rendered. Every visible
    // earning/deduction must have an explicit item name.

    final earningEntries = _mergeMoneyEntries([
      MapEntry<String, Object?>(
        '基本給',
        earnings['基本給'] ?? earnings['出勤に基づく支給額'],
      ),
      MapEntry<String, Object?>('残業手当', earnings['残業手当']),
      MapEntry<String, Object?>('交通費', earnings['交通費']),
      ...configuredEarnings.entries,
      ...adjustmentEarnings.entries,
    ]);

    final deductionEntries = _mergeMoneyEntries([
      MapEntry<String, Object?>(
        '健康保険料',
        deductions['健康保険料'] ?? deductions['社会保険'],
      ),
      MapEntry<String, Object?>('所得税', deductions['所得税']),
      MapEntry<String, Object?>('住民税', deductions['住民税']),
      MapEntry<String, Object?>('道具代', deductions['道具代']),
      ...configuredDeductions.entries,
      ...adjustmentDeductions.entries.map(
        (entry) => MapEntry(entry.key, _asNumber(entry.value)?.abs() ?? 0),
      ),
    ]);

    final largestCount = earningEntries.length > deductionEntries.length
        ? earningEntries.length
        : deductionEntries.length;
    final pageCount = largestCount == 0 ? 1 : (largestCount + 14) ~/ 15;
    for (var pageIndex = 0; pageIndex < pageCount; pageIndex++) {
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(18, 18, 18, 18),
          build: (_) => _sheet(
            statement,
            sealFont: sealFont,
            fallbackFont: regular,
            detail: detail,
            earningEntries: Map.fromEntries(
              earningEntries.entries.skip(pageIndex * 15).take(15),
            ),
            deductionEntries: Map.fromEntries(
              deductionEntries.entries.skip(pageIndex * 15).take(15),
            ),
            pageIndex: pageIndex,
            pageCount: pageCount,
          ),
        ),
      );
    }

    return document.save();
  }

  static Future<bool> printStatement(PayrollStatementRecord statement) {
    return Printing.layoutPdf(
      name: '${statement.monthLabel}_${statement.workerName}_給与明細.pdf',
      format: PdfPageFormat.a4,
      onLayout: (_) => buildPdf(statement),
    );
  }

  static String buildTextSnapshot(PayrollStatementRecord statement) =>
      '給与明細書\n${statement.companyName}\n${statement.workerName}\n'
      '${statement.monthLabel}\n給与形態 ${_payTypeLabel(statement.detail)}\n${statement.reviewConfirmed ? '確認済み' : '未確定'}\n'
      '総支給額 ${statement.grossPay == 0 ? '' : _yen(statement.grossPay)}\n'
      '総控除額 ${statement.deductions == 0 ? '' : _yen(statement.deductions)}\n'
      '差引支給額 ${statement.netPay == 0 ? '' : _yen(statement.netPay)}';

  static pw.Widget _sheet(
    PayrollStatementRecord statement, {
    required pw.Font sealFont,
    required pw.Font fallbackFont,
    required Map<String, dynamic> detail,
    required Map<String, Object?> earningEntries,
    required Map<String, Object?> deductionEntries,
    required int pageIndex,
    required int pageCount,
  }) {
    final blue = PdfColor.fromHex('#178DE3');
    final paleBlue = PdfColor.fromHex('#EFF8FD');
    final red = PdfColor.fromHex('#EC4F79');
    final paleRed = PdfColor.fromHex('#FFF3F6');
    final green = PdfColor.fromHex('#318B61');
    final paleGreen = PdfColor.fromHex('#F0FAF4');

    const width = 519.275590551;
    final panelWidth = (width - 10) / 2;
    pw.Widget text(
      String value, {
      double size = 8,
      PdfColor? color,
      bool bold = false,
    }) => pw.Text(
      value,
      style: pw.TextStyle(
        fontSize: size,
        color: color,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    );
    pw.Widget at(double x, double y, double w, double h, pw.Widget child) =>
        pw.Positioned(
          left: x,
          top: y,
          child: pw.SizedBox(width: w, height: h, child: child),
        );
    pw.BoxDecoration box(
      PdfColor stroke, {
      PdfColor? fill,
      double radius = 5,
    }) => pw.BoxDecoration(
      color: fill,
      border: pw.Border.all(color: stroke, width: .5),
      borderRadius: pw.BorderRadius.circular(radius),
    );
    final light = PdfColor.fromHex('#83CBEA');
    final companyText = text(statement.companyName, size: 10, bold: true);
    final bank = detail['bank_account'] is Map
        ? Map<String, dynamic>.from(detail['bank_account'] as Map)
        : detail;
    final bankFields = [
      [
        '銀行名',
        _first(bank, const ['bank_name', '銀行名']),
      ],
      [
        '支店名',
        _first(bank, const ['bank_branch', 'branch_name', '支店名']),
      ],
      [
        '口座種別',
        _first(bank, const ['bank_account_type', 'account_type', '口座種別']),
      ],
      [
        '口座番号',
        _first(bank, const ['bank_account_number', 'account_number', '口座番号']),
      ],
      [
        '口座名義',
        _first(bank, const ['bank_account_holder', 'account_holder', '口座名義']),
      ],
    ];
    final remarks = _first(detail, const ['備考', 'remarks', 'notes']);
    final payType = _payTypeLabel(detail);
    return pw.Container(
      width: 559.275590551,
      height: 805.88976378,
      decoration: box(PdfColor.fromHex('#A8B8C8')),
      child: pw.Stack(
        children: [
          if (pageCount > 1)
            at(
              450,
              790,
              89,
              10,
              text('${pageIndex + 1} / $pageCount', size: 6),
            ),
          at(
            20,
            29,
            180,
            34,
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Flexible(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 7),
                    child: companyText,
                  ),
                ),
                pw.Transform.translate(
                  offset: const PdfPoint(-4, 0),
                  child: CompanySealPdf.build(
                    statement.companyName,
                    size: 32,
                    font: sealFont,
                    fallbackFont: fallbackFont,
                  ),
                ),
              ],
            ),
          ),
          at(
            20,
            50,
            170,
            12,
            pw.LayoutBuilder(
              builder: (context, constraints) {
                final nameWidth =
                    fallbackFont
                        .getFont(context)
                        .stringMetrics(statement.companyName)
                        .width *
                    10;
                final availableWidth = (nameWidth - 4)
                    .clamp(1.0, 144.0)
                    .toDouble();
                final registeredTagline = _first(detail, const [
                  'company_tagline',
                  '会社スローガン',
                ]);
                final tagline = registeredTagline.isEmpty
                    ? '人と現場をつなぐ　未来をつくる'
                    : registeredTagline;
                final taglineWidth =
                    fallbackFont.getFont(context).stringMetrics(tagline).width *
                    5.5;
                final belowSeal = taglineWidth > availableWidth;
                return pw.Transform.translate(
                  offset: PdfPoint(0, belowSeal ? 14 : 0),
                  child: pw.Align(
                    alignment: pw.Alignment.topLeft,
                    child: pw.SizedBox(
                      width: belowSeal ? 144 : availableWidth,
                      height: 12,
                      child: pw.FittedBox(
                        fit: pw.BoxFit.scaleDown,
                        alignment: pw.Alignment.topLeft,
                        child: text(
                          tagline,
                          size: 5.5,
                          color: PdfColor.fromHex('#073A76'),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          at(
            200,
            41,
            159,
            30,
            pw.Center(
              child: text(
                '給 与 明 細 書',
                size: 19,
                color: PdfColor.fromHex('#073A76'),
              ),
            ),
          ),
          at(200, 66, 159, .7, pw.Container(color: blue)),
          at(
            200,
            70,
            159,
            13,
            pw.Center(
              child: text(
                'S A L A R Y   S T A T E M E N T',
                size: 5.6,
                color: blue,
              ),
            ),
          ),
          at(
            390,
            29,
            149.275590551,
            25,
            pw.Align(
              alignment: pw.Alignment.topRight,
              child: text(
                '${statement.periodEnd.year}年${statement.periodEnd.month}月分',
                size: 12.5,
                color: PdfColor.fromHex('#073A76'),
              ),
            ),
          ),
          at(
            390,
            50,
            149.275590551,
            14,
            pw.Align(
              alignment: pw.Alignment.topRight,
              child: text(
                '支給日　${_paymentDate(statement, detail)}',
                size: 6.4,
                color: PdfColor.fromHex('#073A76'),
              ),
            ),
          ),
          at(
            350,
            80,
            189.275590551,
            16,
            pw.Align(
              alignment: pw.Alignment.topRight,
              child: text(
                _first(detail, const ['statement_message', '帳票メッセージ']).isEmpty
                    ? '毎日の現場が、明日の街をつくる。'
                    : _first(detail, const ['statement_message', '帳票メッセージ']),
                size: 7.5,
                color: PdfColor.fromHex('#073A76'),
              ),
            ),
          ),
          at(
            20,
            79,
            230,
            28,
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 12),
              decoration: box(blue, fill: blue),
              child: pw.Stack(
                children: [
                  pw.Positioned(
                    left: 0,
                    top: 2.8,
                    child: pw.Text(
                      payType.split('').join(' '),
                      style: const pw.TextStyle(
                        fontSize: 16,
                        color: PdfColors.white,
                      ),
                    ),
                  ),
                  pw.Positioned(
                    left: 88,
                    right: 0,
                    top: 8,
                    child: pw.FittedBox(
                      fit: pw.BoxFit.scaleDown,
                      alignment: pw.Alignment.centerLeft,
                      child: text(
                        payType == '月給'
                            ? '（月固定給 ＋ 各種手当）'
                            : payType == '時給'
                            ? '（勤務時間 × 登録単価 ＋ 各種手当）'
                            : payType == '日給'
                            ? '（勤務日数 × 登録単価 ＋ 各種手当）'
                            : '',
                        size: 8.5,
                        color: PdfColors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          at(
            20,
            114,
            width,
            42,
            pw.Row(
              children: [
                for (final field in [
                  [
                    '社員番号',
                    _first(detail, const ['社員番号', '社員No', '社員No.']),
                  ],
                  ['氏名', '${statement.workerName}　様'],
                  [
                    '所属',
                    _first(detail, const ['所属', '部署']),
                  ],
                  [
                    '職種',
                    _first(detail, const ['職種']),
                  ],
                  ['給与形態', payType],
                  [
                    '入社日',
                    _first(detail, const ['入社日']),
                  ],
                ])
                  pw.SizedBox(
                    width: const <String, double>{
                      '社員番号': 62,
                      '氏名': 108,
                      '所属': 85,
                      '職種': 94,
                      '給与形態': 78,
                      '入社日': 92.275590551,
                    }[field[0]],
                    child: pw.Container(
                      height: 42,
                      padding: const pw.EdgeInsets.all(8),
                      decoration: box(light, fill: paleBlue, radius: 3),
                      child: _identityText(field[0], field[1]),
                    ),
                  ),
              ],
            ),
          ),
          at(
            20,
            163,
            width,
            79,
            pw.Container(
              decoration: box(light),
              child: pw.Column(
                children: [
                  _sectionHeader('1', '勤務実績', blue, paleBlue),
                  pw.Expanded(child: _attendanceCards(detail, blue, paleBlue)),
                ],
              ),
            ),
          ),
          at(
            20,
            252,
            panelWidth,
            305,
            _moneyPanel(
              '2　●　支給（＋）',
              earningEntries,
              detail,
              blue,
              paleBlue,
              total: statement.grossPay,
              totalLabel: '支給合計（A）',
              earnings: true,
            ),
          ),
          at(
            30 + panelWidth,
            252,
            panelWidth,
            305,
            _moneyPanel(
              '3　　控除（－）',
              deductionEntries,
              detail,
              red,
              paleRed,
              total: statement.deductions,
              totalLabel: '控除合計（B）',
            ),
          ),
          at(
            20,
            566,
            width,
            79,
            pw.Container(
              decoration: box(light, fill: paleGreen),
              child: pw.Column(
                children: [
                  _sectionHeader('4', '差引支給額', blue, paleBlue),
                  pw.Expanded(
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.fromLTRB(10, 6, 10, 7),
                      child: pw.Row(
                        children: [
                          pw.Expanded(
                            child: _summaryAmount(
                              '支給合計（A）',
                              statement.grossPay,
                              blue,
                              paleBlue,
                            ),
                          ),
                          pw.SizedBox(
                            width: 24,
                            child: pw.Center(child: text('－', size: 12)),
                          ),
                          pw.Expanded(
                            child: _summaryAmount(
                              '控除合計（B）',
                              statement.deductions,
                              red,
                              paleRed,
                            ),
                          ),
                          pw.SizedBox(
                            width: 24,
                            child: pw.Center(child: text('＝', size: 12)),
                          ),
                          pw.Expanded(
                            child: _summaryAmount(
                              '差引支給額（振込額）',
                              statement.netPay,
                              green,
                              paleGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          at(
            20,
            731.88976378,
            300,
            57,
            pw.Container(
              decoration: box(light),
              padding: const pw.EdgeInsets.all(10),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  text('備考', size: 8.5),
                  pw.SizedBox(width: 25),
                  pw.Expanded(child: text(remarks, size: 6)),
                ],
              ),
            ),
          ),
          at(
            330,
            731.88976378,
            width - 310,
            57,
            pw.Container(
              decoration: box(light),
              padding: const pw.EdgeInsets.all(10),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  text('振込先', size: 8.5),
                  pw.SizedBox(width: 20),
                  pw.Expanded(
                    child: bankFields.every((field) => field[1].isEmpty)
                        ? text('未登録', size: 9, color: PdfColors.red)
                        : pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              for (final field in bankFields)
                                text('${field[0]}　${field[1]}', size: 5),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _sectionHeader(
    String number,
    String label,
    PdfColor accent,
    PdfColor pale,
  ) => pw.Container(
    height: 27,
    decoration: pw.BoxDecoration(
      color: pale,
      borderRadius: pw.BorderRadius.circular(5),
    ),
    child: pw.Row(
      children: [
        pw.Container(
          width: 28,
          height: 27,
          alignment: pw.Alignment.center,
          decoration: pw.BoxDecoration(
            color: accent,
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(
            number,
            style: const pw.TextStyle(fontSize: 14, color: PdfColors.white),
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Text(label, style: pw.TextStyle(fontSize: 10.5, color: accent)),
      ],
    ),
  );

  static pw.Widget _identityText(String label, String value) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(label, style: const pw.TextStyle(fontSize: 6)),
      pw.SizedBox(height: 2),
      pw.Text(
        value,
        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
      ),
    ],
  );

  static String _payTypeLabel(Map<String, dynamic> detail) {
    final nested = detail['payroll_settings'] is Map
        ? Map<String, dynamic>.from(detail['payroll_settings'] as Map)
        : const <String, dynamic>{};
    final raw = _first(detail, const [
      'pay_type',
      '給与形態',
      '給与方式',
      'salary_type',
      'payment_type',
    ]);
    final normalized =
        (raw.isEmpty ? _first(nested, const ['pay_type', '給与形態', '給与方式']) : raw)
            .trim()
            .toLowerCase();
    if (normalized == 'monthly' || normalized.contains('月給')) return '月給';
    if (normalized == 'hourly' || normalized.contains('時給')) return '時給';
    if (normalized == 'daily' || normalized.contains('日給')) return '日給';
    return '未登録';
  }

  static pw.Widget _attendanceCards(
    Map<String, dynamic> detail,
    PdfColor blue,
    PdfColor pale,
  ) {
    final items = <MapEntry<String, String>>[
      MapEntry('出勤日数', _dayCount(detail, const ['出勤日数'])),
      MapEntry('欠勤日数', _dayCount(detail, const ['欠勤日数'])),
      MapEntry('有給取得', _dayCount(detail, const ['有給日数'])),
      MapEntry('休日出勤', _dayCount(detail, const ['休出日数', '休日出勤', '休日出勤日数'])),
      MapEntry('残業時間', _hours(detail, const ['残業時間'])),
      MapEntry('早出時間', _hours(detail, const ['早出時間'])),
      MapEntry('深夜時間', _hours(detail, const ['深夜時間', '夜間時間'])),
      MapEntry('休日残業時間', _hours(detail, const ['休日残業時間', '法定休出時間'])),
      MapEntry('休日深夜時間', _hours(detail, const ['休日深夜時間'])),
      MapEntry('休日深夜残業', _hours(detail, const ['休日深夜残業時間'])),
    ];
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        children: [
          for (var index = 0; index < 9; index++)
            pw.Expanded(
              child: pw.Container(
                decoration: pw.BoxDecoration(
                  border: index == 0
                      ? null
                      : pw.Border(
                          left: pw.BorderSide(
                            color: PdfColor.fromHex('#DCEFF8'),
                            width: .5,
                          ),
                        ),
                ),
                padding: const pw.EdgeInsets.only(top: 7),
                child: pw.Column(
                  children: [
                    pw.Text(
                      items[index].key,
                      style: pw.TextStyle(
                        fontSize: 5.7,
                        color: PdfColor.fromHex('#073A76'),
                      ),
                    ),
                    pw.SizedBox(height: 11),
                    pw.Text(
                      _isZeroDisplay(items[index].value)
                          ? ''
                          : items[index].value,
                      style: pw.TextStyle(
                        fontSize: 8.2,
                        color: _isZeroDisplay(items[index].value)
                            ? PdfColor.fromHex('#BCCADD')
                            : PdfColor.fromHex('#073A76'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  static pw.Widget _moneyPanel(
    String title,
    Map<String, Object?> entries,
    Map<String, dynamic> detail,
    PdfColor accent,
    PdfColor pale, {
    required int total,
    required String totalLabel,
    bool earnings = false,
  }) {
    final visible = entries.entries.toList();
    final rowCount = visible.length < 15 ? 15 : visible.length;
    final rowHeight = 220.0 / rowCount;
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: accent, width: .6),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Column(
        children: [
          pw.Container(
            height: 30,
            alignment: pw.Alignment.centerLeft,
            padding: const pw.EdgeInsets.fromLTRB(12, 2, 12, 0),
            decoration: pw.BoxDecoration(
              color: accent,
              borderRadius: const pw.BorderRadius.only(
                topLeft: pw.Radius.circular(5),
                topRight: pw.Radius.circular(5),
              ),
            ),
            child: pw.Text(
              title,
              style: const pw.TextStyle(fontSize: 11.5, color: PdfColors.white),
            ),
          ),
          pw.Container(
            height: 21,
            color: pale,
            child: pw.Row(
              children: [
                pw.Expanded(
                  flex: earnings ? 25 : 31,
                  child: pw.Center(
                    child: pw.Text(
                      '項目',
                      style: const pw.TextStyle(fontSize: 5.4),
                    ),
                  ),
                ),
                pw.Expanded(
                  flex: earnings ? 39 : 43,
                  child: pw.Center(
                    child: pw.Text(
                      earnings ? '計算内容・単価' : '計算内容・備考',
                      style: const pw.TextStyle(fontSize: 5.4),
                    ),
                  ),
                ),
                if (earnings)
                  pw.Expanded(
                    flex: 17,
                    child: pw.Center(
                      child: pw.Text(
                        '日数・時間',
                        style: const pw.TextStyle(fontSize: 5.4),
                      ),
                    ),
                  ),
                pw.Expanded(
                  flex: earnings ? 19 : 26,
                  child: pw.Center(
                    child: pw.Text(
                      '金額（円）',
                      style: const pw.TextStyle(fontSize: 5.4),
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < rowCount; i++)
            pw.Container(
              height: rowHeight,
              padding: const pw.EdgeInsets.fromLTRB(4, 3.5, 4, 0),
              decoration: pw.BoxDecoration(
                border: pw.Border(top: pw.BorderSide(color: pale, width: .3)),
              ),
              child: i >= visible.length
                  ? null
                  : pw.Row(
                      children: [
                        pw.Expanded(
                          flex: earnings ? 25 : 31,
                          child: pw.Text(
                            visible[i].key,
                            style: const pw.TextStyle(fontSize: 5.4),
                          ),
                        ),
                        pw.Expanded(
                          flex: earnings ? 39 : 43,
                          child: pw.Text(
                            _moneyExplanation(visible[i].key, detail),
                            textAlign: pw.TextAlign.center,
                            style: const pw.TextStyle(fontSize: 5),
                          ),
                        ),
                        if (earnings)
                          pw.Expanded(
                            flex: 17,
                            child: pw.Text(
                              _quantity(visible[i].key, detail),
                              textAlign: pw.TextAlign.center,
                              style: const pw.TextStyle(fontSize: 5),
                            ),
                          ),
                        pw.Expanded(
                          flex: earnings ? 19 : 26,
                          child: pw.Text(
                            _number(
                              (_asNumber(visible[i].value) ?? 0).abs().toInt(),
                            ),
                            textAlign: pw.TextAlign.right,
                            style: const pw.TextStyle(fontSize: 6),
                          ),
                        ),
                      ],
                    ),
            ),
          pw.Container(
            height: 34,
            padding: const pw.EdgeInsets.fromLTRB(10, 3.7, 10, 0),
            decoration: pw.BoxDecoration(
              color: pale,
              border: pw.Border.all(color: accent, width: .5),
              borderRadius: pw.BorderRadius.circular(5),
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    totalLabel,
                    style: pw.TextStyle(fontSize: 9.5, color: accent),
                  ),
                ),
                pw.Text(
                  total == 0 ? '' : _number(total),
                  style: pw.TextStyle(fontSize: 14.5, color: accent),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _quantity(String label, Map<String, dynamic> detail) {
    final key = label.contains('休日残業')
        ? '休日残業時間'
        : label.contains('残業')
        ? '残業時間'
        : label.contains('早出')
        ? '早出時間'
        : label.contains('休日出勤')
        ? '休出日数'
        : '';
    if (key.isEmpty || detail[key] == null) return '－';
    if ((_asNumber(detail[key]) ?? 0) == 0) return '';
    return '${detail[key]}${key.endsWith('日数') ? '日' : '時間'}';
  }

  static String _moneyExplanation(String label, Map<String, dynamic> detail) {
    final direct = detail['$label計算内容'] ?? detail['$label備考'];
    if (direct != null && direct.toString().trim().isNotEmpty) {
      return direct.toString().trim();
    }
    if (label == '基本給') {
      return _payTypeLabel(detail) == '月給' ? '月固定給' : '勤務実績 × 基本単価';
    }
    if (label.contains('残業')) return '登録単価 × 残業時間';
    if (label.contains('早出')) return '登録単価 × 早出時間';
    if (label.contains('休日')) return '登録単価 × 休日実績';
    return '';
  }

  static pw.Widget _summaryAmount(
    String label,
    int amount,
    PdfColor color,
    PdfColor pale,
  ) => pw.Container(
    height: 39,
    decoration: pw.BoxDecoration(
      color: pale,
      border: pw.Border.all(color: color, width: .5),
      borderRadius: pw.BorderRadius.circular(5),
    ),
    child: pw.Stack(
      children: [
        pw.Positioned(
          left: 0,
          right: 0,
          top: 8.692,
          child: pw.Text(
            label,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 6.3, color: color),
          ),
        ),
        pw.Positioned(
          left: 0,
          right: 0,
          top: 20.08,
          child: pw.Text(
            amount == 0 ? '' : '${_number(amount)} 円',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 12, color: color),
          ),
        ),
      ],
    ),
  );

  static Map<String, Object?> _pick(
    Map<String, dynamic> detail,
    List<String> keys,
  ) {
    final result = <String, Object?>{};
    for (final key in keys) {
      if (detail.containsKey(key)) {
        result[key] = detail[key];
      }
    }
    return result;
  }

  static const _nonMoneyDetailKeys = <String>{
    '出勤日数',
    '休出日数',
    '休日出勤',
    '休日出勤日数',
    '有給日数',
    '残業時間',
    '法定休出時間',
    '法定休日出勤時間',
    '法定外出時間',
    '早出時間',
    '夜間時間',
    '日給単価',
    '月次減税額',
    '減税前未済額',
    '減税前所得税',
    '定額減税額',
    '定額減税未済',
    '社員番号',
    '社員No',
    '社員No.',
    'pay_type',
    '給与形態',
    '給与方式',
    'salary_type',
    'payment_type',
    'payroll_settings',
    'monthly_salary_yen',
    'calculation_daily_base_yen',
    'base_rate_yen',
    'hourly_rate_yen',
    'custom_earnings',
    'custom_earnings_total',
    'custom_deductions',
    '支払日',
    '欠勤日数',
    '深夜時間',
    '休日残業時間',
    '休日深夜時間',
    '休日深夜残業時間',
    'bank_account',
    'bank_name',
    'bank_branch',
    'branch_name',
    'bank_account_type',
    'account_type',
    'bank_account_number',
    'account_number',
    'bank_account_holder',
    'account_holder',
    '口座番号',
    '備考',
    'remarks',
    'notes',
  };

  static const _fixedMoneyKeys = <String>{
    '基本給',
    '残業手当',
    '交通費',
    '出勤に基づく支給額',
    '健康保険料',
    '所得税',
    '住民税',
    '道具代',
    '社会保険',
  };

  static const _aggregatePlaceholderLabels = <String>{
    'その他支給',
    'その他の支給',
    'その他控除',
    'その他の控除',
  };

  static bool _isAggregatePlaceholder(String label) =>
      _aggregatePlaceholderLabels.contains(label.trim());

  static Map<String, Object?> _configuredMoneyEntries(
    Map<String, dynamic> detail, {
    required String key,
  }) {
    final raw = detail[key];
    if (raw is! List) return const {};
    final result = <String, Object?>{};
    for (final value in raw) {
      if (value is! Map) continue;
      final name = value['name']?.toString().trim() ?? '';
      final amount = (value['amount_yen'] as num?)?.toInt() ?? 0;
      if (name.isEmpty) continue;
      if (_isAggregatePlaceholder(name)) continue;
      result[name] = (result[name] as num? ?? 0) + amount;
    }
    return result;
  }

  static Map<String, Object?> _mergeMoneyEntries(
    Iterable<MapEntry<String, Object?>> entries,
  ) {
    final result = <String, Object?>{};
    for (final entry in entries) {
      final label = entry.key.trim();
      final amount = _asNumber(entry.value);
      if (label.isEmpty || amount == null || amount.abs() < 1) {
        continue;
      }
      result[label] = (result[label] as num? ?? 0) + amount.abs();
    }
    return result;
  }

  static Map<String, Object?> _customMoneyEntries(
    Map<String, dynamic> detail, {
    required int direction,
  }) {
    final result = <String, Object?>{};
    for (final entry in detail.entries) {
      if (_nonMoneyDetailKeys.contains(entry.key) ||
          _fixedMoneyKeys.contains(entry.key) ||
          _isAggregatePlaceholder(entry.key)) {
        continue;
      }
      final value = _asNumber(entry.value);
      if (value == null || value == 0) continue;
      if ((direction > 0 && value > 0) || (direction < 0 && value < 0)) {
        result[entry.key] = value;
      }
    }
    return result;
  }

  static String _first(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static bool _isZeroDisplay(String value) {
    final normalized = value.trim().replaceAll('時間', '').replaceAll('日', '');
    if (normalized.isEmpty || normalized == '00:00') return true;
    final number = double.tryParse(normalized);
    return number != null && number == 0;
  }

  static num? _asNumber(Object? value) {
    if (value is num) return value;
    if (value == null) return null;
    final text = value.toString().replaceAll(',', '').trim();
    return num.tryParse(text);
  }

  static String _dayCount(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value == null) continue;
      final parsed = _asNumber(value.toString().replaceAll('日', ''));
      if (parsed == null) return value.toString();
      return '${parsed == parsed.round() ? parsed.toInt() : parsed.toStringAsFixed(1)}日';
    }
    return '0日';
  }

  static String _hours(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value == null) continue;
      final raw = value.toString().replaceAll('時間', '');
      final parts = raw.split(':');
      final hours = parts.length == 2
          ? (double.tryParse(parts[0]) ?? 0) +
                (double.tryParse(parts[1]) ?? 0) / 60
          : double.tryParse(raw);
      if (hours != null) return '${hours.toStringAsFixed(1)}時間';
      return value.toString();
    }
    return '0.0時間';
  }

  static String _paymentDate(
    PayrollStatementRecord statement,
    Map<String, dynamic> detail,
  ) {
    final day = (_asNumber(detail['支払日']) ?? 0).toInt();
    if (day >= 1 && day <= 31) {
      final nextMonth = DateTime(
        statement.periodEnd.year,
        statement.periodEnd.month + 1,
        1,
      );
      final lastDay = DateTime(nextMonth.year, nextMonth.month + 1, 0).day;
      final actualDay = day > lastDay ? lastDay : day;
      return _date(DateTime(nextMonth.year, nextMonth.month, actualDay));
    }
    return statement.issuedAt == null ? '' : _date(statement.issuedAt!);
  }

  static String _date(DateTime value) =>
      '${value.year}年${value.month}月${value.day}日';

  static String _number(int value) {
    final negative = value < 0;
    final digits = value.abs().toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        out.write(',');
      }
      out.write(digits[i]);
    }
    return '${negative ? '-' : ''}$out';
  }

  static String _yen(int value) => '¥${_number(value)}';
}
