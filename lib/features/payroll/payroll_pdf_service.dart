import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'payroll_statement_repository.dart';

class PayrollPdfService {
  const PayrollPdfService._();

  static Future<Uint8List> buildPdf(
    PayrollStatementRecord statement, {
    PdfPageFormat format = PdfPageFormat.a4,
  }) async {
    final regular = await PdfGoogleFonts.notoSansJPRegular();
    final bold = await PdfGoogleFonts.notoSansJPBold();
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );

    final detail = statement.detail;
    final earnings = _pick(detail, const [
      '基本給',
      '残業手当',
              '交通費',
      '出勤に基づく支給額',
    ]);
    final deductions = _pick(detail, const [
      '健康保険料',
            '所得税',
      '住民税',
        '道具代',
      '社会保険',
      'その他控除',
    ]);

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(
          8 * PdfPageFormat.mm,
          7 * PdfPageFormat.mm,
          8 * PdfPageFormat.mm,
          7 * PdfPageFormat.mm,
        ),
        build: (_) => _sheet(
          statement,
          detail: detail,
          earnings: earnings,
          deductions: deductions,
        ),
      ),
    );

    return document.save();
  }

  static Future<bool> printStatement(PayrollStatementRecord statement) {
    return Printing.layoutPdf(
      name: '${statement.monthLabel}_${statement.workerName}_給与明細.pdf',
      format: PdfPageFormat.a4.landscape,
      onLayout: (_) => buildPdf(statement),
    );
  }

  static String buildTextSnapshot(PayrollStatementRecord statement) =>
      '給与明細書\n${statement.companyName}\n${statement.workerName}\n'
      '${statement.monthLabel}\n${statement.reviewConfirmed ? '確認済み' : '未確定'}\n'
      '総支給額 ${_yen(statement.grossPay)}\n'
      '総控除額 ${_yen(statement.deductions)}\n'
      '差引支給額 ${_yen(statement.netPay)}';

  static pw.Widget _sheet(
    PayrollStatementRecord statement, {
    required Map<String, dynamic> detail,
    required Map<String, Object?> earnings,
    required Map<String, Object?> deductions,
  }) {
    final headerFill = PdfColor.fromHex('#DCE8F6');
    final grid = PdfColor.fromHex('#6D89A8');
    final configuredEarnings =
        _configuredMoneyEntries(detail, key: 'custom_earnings');
    final configuredDeductions =
        _configuredMoneyEntries(detail, key: 'custom_deductions');
    final adjustmentEarnings = _customMoneyEntries(detail, direction: 1);
    final adjustmentDeductions = _customMoneyEntries(detail, direction: -1);

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
      MapEntry<String, Object?>('その他控除', deductions['その他控除']),
      ...configuredDeductions.entries,
      ...adjustmentDeductions.entries.map(
        (entry) => MapEntry(entry.key, _asNumber(entry.value)?.abs() ?? 0),
      ),
    ]);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.SizedBox(height: 3),
        pw.Stack(
          children: [
            pw.Align(
              alignment: pw.Alignment.topCenter,
              child: pw.Text(
                '給与明細書',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Align(
              alignment: pw.Alignment.topRight,
              child: pw.SizedBox(
                width: 165,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      '${statement.periodEnd.year}年${statement.periodEnd.month}月分',
                      style: pw.TextStyle(
                        fontSize: 12.5,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      '支払日　${_paymentDate(statement, detail)}',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      statement.companyName,
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          children: [
            pw.SizedBox(
              width: 420,
              child: pw.Table(
                border: pw.TableBorder.all(color: grid, width: .55),
                columnWidths: const {
                  0: pw.FlexColumnWidth(2.4),
                  1: pw.FlexColumnWidth(1.1),
                  2: pw.FlexColumnWidth(2.5),
                },
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: headerFill),
                    children: [
                      _cell('所属', center: true, bold: true, height: 18),
                      _cell('社員番号', center: true, bold: true, height: 18),
                      _cell('氏名', center: true, bold: true, height: 18),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      _cell(statement.companyName, height: 22),
                      _cell(
                        _first(detail, const ['社員番号', '社員No', '社員No.']),
                        center: true,
                        height: 22,
                      ),
                      _cell(
                        '${statement.workerName}　様',
                        height: 22,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        _attendanceSection(
          detail: detail,
          headerFill: headerFill,
          grid: grid,
        ),
        pw.SizedBox(height: 10),
        _balancedMoneySection(
          title: '支給',
          entries: earningEntries,
          headerFill: headerFill,
          grid: grid,
        ),
        pw.SizedBox(height: 8),
        _balancedMoneySection(
          title: '控除',
          entries: deductionEntries,
          headerFill: headerFill,
          grid: grid,
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          children: [
            const pw.SizedBox(width: 28),
            pw.Expanded(
              child: pw.Table(
                border: pw.TableBorder.all(color: grid, width: .55),
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: headerFill),
                    children: [
                      _cell('', height: 18),
                      _cell('', height: 18),
                      _cell('総支給額', center: true, bold: true, height: 18),
                      _cell('総控除額', center: true, bold: true, height: 18),
                      _cell('差引支給額', center: true, bold: true, height: 18),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      _cell('', height: 23),
                      _cell('', height: 23),
                      _cell(
                        _number(statement.grossPay),
                        right: true,
                        height: 23,
                        fontSize: 8,
                      ),
                      _cell(
                        _number(statement.deductions),
                        right: true,
                        height: 23,
                        fontSize: 8,
                      ),
                      _cell(
                        _number(statement.netPay),
                        right: true,
                        bold: true,
                        height: 23,
                        fontSize: 8,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Table(
          border: pw.TableBorder.all(color: grid, width: .55),
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: headerFill),
              children: [
                _cell('日給単価', center: true, bold: true, height: 18),
                _cell('', height: 18),
                _cell('', height: 18),
                _cell('', height: 18),
                _cell('', height: 18),
                _cell('月次減税額', center: true, bold: true, height: 18, fontSize: 6.5),
                _cell('減税前未済額', center: true, bold: true, height: 18, fontSize: 6.5),
                _cell('減税前所得税', center: true, bold: true, height: 18, fontSize: 6.5),
                _cell('定額減税額', center: true, bold: true, height: 18, fontSize: 6.5),
                _cell('定額減税未済', center: true, bold: true, height: 18, fontSize: 6.5),
              ],
            ),
            pw.TableRow(
              children: [
                _cell(
                  _plainNumber(detail, const ['日給単価']),
                  right: true,
                  height: 22,
                ),
                for (var i = 0; i < 4; i++) _cell('', height: 22),
                _cell(_first(detail, const ['月次減税額']), right: true, height: 22),
                _cell(_first(detail, const ['減税前未済額']), right: true, height: 22),
                _cell(_first(detail, const ['減税前所得税']), right: true, height: 22),
                _cell(_first(detail, const ['定額減税額']), right: true, height: 22),
                _cell(_first(detail, const ['定額減税未済']), right: true, height: 22),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 175),
              child: pw.Text(
                'お疲れさまです。',
                style: const pw.TextStyle(fontSize: 7.5),
              ),
            ),
            pw.Text(
              statement.reviewConfirmed ? '確認済み' : '未確定',
              style: pw.TextStyle(
                fontSize: 6.5,
                color: statement.reviewConfirmed
                    ? PdfColors.green700
                    : PdfColors.red700,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _attendanceSection({
    required Map<String, dynamic> detail,
    required PdfColor headerFill,
    required PdfColor grid,
  }) {
    const topLabels = <String>[
      '出勤日数',
      '休出日数',
      '有給日数',
      '',
      '',
      '',
      '',
      '',
      '',
      '',
    ];
    const secondLabels = <String>[
      '残業時間',
      '法定休出時間',
      '早出時間',
      '夜間時間',
      '',
      '',
      '',
      '',
      '',
      '',
    ];

    final topValues = <String>[
      _dayCount(detail, const ['出勤日数']),
      _dayCount(detail, const ['休出日数', '休日出勤', '休日出勤日数']),
      _dayCount(detail, const ['有給日数']),
      '',
      '',
      '',
      '',
      '',
      '',
      '',
    ];

    final secondValues = <String>[
      _hours(detail, const ['残業時間']),
      _hours(detail, const ['法定休出時間', '法定休日出勤時間', '法定外出時間']),
      _hours(detail, const ['早出時間']),
      _hours(detail, const ['夜間時間']),
      '',
      '',
      '',
      '',
      '',
      '',
    ];

    return _sectionShell(
      title: '勤怠',
      headerFill: headerFill,
      grid: grid,
      rows: [
        _row(topLabels, headerFill: headerFill, bold: true, height: 18),
        _row(topValues, right: true, height: 21),
        _row(secondLabels, headerFill: headerFill, bold: true, height: 18),
        _row(secondValues, right: true, height: 21),
      ],
    );
  }

  static pw.Widget _balancedMoneySection({
    required String title,
    required Map<String, Object?> entries,
    required PdfColor headerFill,
    required PdfColor grid,
  }) {
    const columns = 5;
    final visible = entries.entries
        .where((entry) => (_asNumber(entry.value) ?? 0).abs() >= 1)
        .toList();
    final groups = <List<MapEntry<String, Object?>>>[];
    if (visible.isEmpty) {
      groups.add(const []);
    } else {
      for (var index = 0; index < visible.length; index += columns) {
        final end = index + columns < visible.length
            ? index + columns
            : visible.length;
        groups.add(visible.sublist(index, end));
      }
    }

    final rows = <pw.TableRow>[];
    for (final group in groups) {
      rows
        ..add(
          _row(
            [
              ...group.map((entry) => entry.key),
              ...List<String>.filled(columns - group.length, ''),
            ],
            headerFill: headerFill,
            bold: true,
            height: 18,
          ),
        )
        ..add(
          _row(
            [
              ...group.map(
                (entry) => _formatAmount(entry.value, absolute: true),
              ),
              ...List<String>.filled(columns - group.length, ''),
            ],
            right: true,
            height: 22,
          ),
        );
    }

    return _sectionShell(
      title: title,
      headerFill: headerFill,
      grid: grid,
      rows: rows,
    );
  }

  static pw.Widget _singleHeaderSection({
    required String title,
    required List<String> labels,
    required List<String> values,
    required PdfColor headerFill,
    required PdfColor grid,
    required int blankRows,
  }) {
    return _sectionShell(
      title: title,
      headerFill: headerFill,
      grid: grid,
      rows: [
        _row(labels, headerFill: headerFill, bold: true, height: 18),
        _row(values, right: true, height: 22),
        for (var i = 0; i < blankRows; i++)
          _row(
            List<String>.filled(labels.length, ''),
            height: 20,
          ),
      ],
    );
  }

  static pw.Widget _sectionShell({
    required String title,
    required PdfColor headerFill,
    required PdfColor grid,
    required List<pw.TableRow> rows,
  }) {
    return pw.Row(
      children: [
        pw.Container(
          width: 28,
          decoration: pw.BoxDecoration(
            color: headerFill,
            border: pw.Border.all(color: grid, width: .55),
          ),
          alignment: pw.Alignment.center,
          child: pw.Text(
            title.split('').join('\n'),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.Expanded(
          child: pw.Table(
            border: pw.TableBorder.all(color: grid, width: .55),
            children: rows,
          ),
        ),
      ],
    );
  }

  static pw.TableRow _row(
    List<String> values, {
    PdfColor? headerFill,
    bool bold = false,
    bool right = false,
    double height = 20,
  }) {
    return pw.TableRow(
      decoration: headerFill == null
          ? null
          : pw.BoxDecoration(color: headerFill),
      children: [
        for (final value in values)
          _cell(
            value,
            center: !right,
            right: right,
            bold: bold,
            height: height,
          ),
      ],
    );
  }

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

  static String _amount(
    Map<String, Object?> source,
    String key, {
    String? fallbackKey,
    bool absolute = false,
  }) {
    final value =
        source[key] ?? (fallbackKey == null ? null : source[fallbackKey]);
    return _formatAmount(value, absolute: absolute);
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
    'custom_earnings',
    'custom_earnings_total',
    'custom_deductions',
    '支払日',
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
    'その他控除',
  };

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
      if (name.isEmpty || amount < 1) continue;
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
      if (label.isEmpty || amount == null || amount.abs() < 1) continue;
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
          _fixedMoneyKeys.contains(entry.key)) {
        continue;
      }
      final value = _asNumber(entry.value);
      if (value == null || value == 0) continue;
      if ((direction > 0 && value > 0) ||
          (direction < 0 && value < 0)) {
        result[entry.key] = value;
      }
    }
    return result;
  }

  static num? _asNumber(Object? value) {
    if (value is num) return value;
    if (value == null) return null;
    final text = value.toString().replaceAll(',', '').trim();
    return num.tryParse(text);
  }

  static bool _hasAmount(Object? value) {
    final number = _asNumber(value);
    if (number != null) return number != 0;
    return value?.toString().trim().isNotEmpty ?? false;
  }

  static String _formatAmount(Object? value, {bool absolute = false}) {
    final number = _asNumber(value);
    if (number != null) {
      final amount = number.toInt();
      return _number(absolute ? amount.abs() : amount);
    }
    return value?.toString() ?? '';
  }

  static String _dayCount(
    Map<String, dynamic> source,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = source[key];
      if (value == null) continue;
      if (value is num) return value.toDouble().toStringAsFixed(1);
      final parsed = double.tryParse(value.toString());
      if (parsed != null) return parsed.toStringAsFixed(1);
      return value.toString();
    }
    return '';
  }

  static String _hours(
    Map<String, dynamic> source,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = source[key];
      if (value == null) continue;
      if (value is num) {
        final totalMinutes = (value.toDouble() * 60).round();
        final hours = totalMinutes ~/ 60;
        final minutes = totalMinutes % 60;
        return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
      }
      final text = value.toString().trim();
      if (text.contains(':')) return text;
      final parsed = double.tryParse(text);
      if (parsed != null) {
        final totalMinutes = (parsed * 60).round();
        final hours = totalMinutes ~/ 60;
        final minutes = totalMinutes % 60;
        return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
      }
      return text;
    }
    return '';
  }

  static String _plainNumber(
    Map<String, dynamic> source,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = source[key];
      if (value == null) continue;
      if (value is num) return value.toInt().toString();
      final text = value.toString().trim();
      final parsed = num.tryParse(text.replaceAll(',', ''));
      if (parsed != null) return parsed.toInt().toString();
      return text;
    }
    return '';
  }

  static String _first(
    Map<String, dynamic> source,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = source[key];
      if (value == null) continue;
      if (value is num) return _number(value.toInt());
      final text = value.toString();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  static pw.Widget _cell(
    String text, {
    bool bold = false,
    bool right = false,
    bool center = false,
    double fontSize = 7.4,
    double height = 20,
  }) {
    return pw.Container(
      height: height,
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      alignment: right
          ? pw.Alignment.centerRight
          : center
              ? pw.Alignment.center
              : pw.Alignment.centerLeft,
      child: pw.Text(
        text,
        maxLines: 1,
        textAlign: right
            ? pw.TextAlign.right
            : center
                ? pw.TextAlign.center
                : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
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
      final lastDay = DateTime(
        nextMonth.year,
        nextMonth.month + 1,
        0,
      ).day;
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
