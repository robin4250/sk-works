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
    ]);

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(
          14 * PdfPageFormat.mm,
          13 * PdfPageFormat.mm,
          14 * PdfPageFormat.mm,
          13 * PdfPageFormat.mm,
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
      format: PdfPageFormat.a4,
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
    final configuredEarnings =
        _configuredMoneyEntries(detail, key: 'custom_earnings');
    final configuredDeductions =
        _configuredMoneyEntries(detail, key: 'custom_deductions');
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

    final blue = PdfColor.fromHex('#2F80ED');
    final paleBlue = PdfColor.fromHex('#EAF4FF');
    final red = PdfColor.fromHex('#D95C73');
    final paleRed = PdfColor.fromHex('#FFF0F3');
    final green = PdfColor.fromHex('#2E8B57');
    final paleGreen = PdfColor.fromHex('#EAF8EF');

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Text(
                statement.companyName,
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: blue),
              ),
            ),
            pw.Text(
              '給与明細書',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: blue),
            ),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('${statement.periodEnd.year}年${statement.periodEnd.month}月分',
                      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  pw.Text('支払日　${_paymentDate(statement, detail)}',
                      style: const pw.TextStyle(fontSize: 7)),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: pw.BoxDecoration(
            color: paleBlue,
            border: pw.Border.all(color: blue, width: .8),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Row(children: [
            pw.Expanded(child: _identityText('社員番号', _first(detail, const ['社員番号', '社員No', '社員No.']))),
            pw.Expanded(flex: 2, child: _identityText('氏名', '${statement.workerName}　様')),
            pw.Expanded(child: _identityText('所属', _first(detail, const ['所属', '部署']))),
            pw.Expanded(child: _identityText('職種', _first(detail, const ['職種']))),
            pw.Expanded(child: _identityText('給与形態', _payTypeLabel(detail))),
            pw.Expanded(child: _identityText('入社日', _first(detail, const ['入社日']))),
          ]),
        ),
        pw.SizedBox(height: 14),
        pw.Text('勤務実績', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: blue)),
        pw.SizedBox(height: 5),
        _attendanceCards(detail, blue, paleBlue),
        pw.SizedBox(height: 16),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: _moneyPanel('支給（＋）', earningEntries, detail, blue, paleBlue)),
            pw.SizedBox(width: 12),
            pw.Expanded(child: _moneyPanel('控除（－）', deductionEntries, detail, red, paleRed)),
          ],
        ),
        pw.Spacer(),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: pw.BoxDecoration(
            color: paleGreen,
            border: pw.Border.all(color: green, width: 1),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
          ),
          child: pw.Row(children: [
            pw.Expanded(child: _summaryAmount('支給合計', statement.grossPay, blue)),
            pw.Text('－', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.Expanded(child: _summaryAmount('控除合計', statement.deductions, red)),
            pw.Text('＝', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.Expanded(
              flex: 2,
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text('差引支給額', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: green)),
                pw.Text(_yen(statement.netPay), style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold, color: green)),
              ]),
            ),
          ]),
        ),
        pw.SizedBox(height: 12),
        pw.Container(
          height: 46,
          padding: const pw.EdgeInsets.all(7),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: blue, width: .55)),
          child: pw.Text('備考', style: pw.TextStyle(fontSize: 7, color: blue)),
        ),
      ],
    );
  }

  static pw.Widget _identityText(String label, String value) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(label, style: const pw.TextStyle(fontSize: 6.5)),
      pw.SizedBox(height: 2),
      pw.Text(value, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
    ],
  );

  static String _payTypeLabel(Map<String, dynamic> detail) {
    final raw = (detail['pay_type'] ?? detail['給与形態'] ?? '').toString().toLowerCase();
    if (raw == 'monthly' || raw.contains('月給')) return '月給';
    if (raw == 'hourly' || raw.contains('時給')) return '時給';
    return '日給';
  }

  static pw.Widget _attendanceCards(Map<String, dynamic> detail, PdfColor blue, PdfColor pale) {
    final items = <MapEntry<String, String>>[
      MapEntry('出勤', _dayCount(detail, const ['出勤日数'])),
      MapEntry('欠勤', _dayCount(detail, const ['欠勤日数'])),
      MapEntry('有給', _dayCount(detail, const ['有給日数'])),
      MapEntry('休日出勤', _dayCount(detail, const ['休出日数', '休日出勤', '休日出勤日数'])),
      MapEntry('残業', _hours(detail, const ['残業時間'])),
      MapEntry('早出', _hours(detail, const ['早出時間'])),
      MapEntry('深夜', _hours(detail, const ['深夜時間', '夜間時間'])),
      MapEntry('休日残業', _hours(detail, const ['休日残業時間', '法定休出時間'])),
      MapEntry('休日深夜', _hours(detail, const ['休日深夜時間'])),
      MapEntry('休日深夜残業', _hours(detail, const ['休日深夜残業時間'])),
    ];
    return pw.Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [
        for (final item in items)
          pw.Container(
            width: 54,
            height: 39,
            padding: const pw.EdgeInsets.all(4),
            decoration: pw.BoxDecoration(color: pale, border: pw.Border.all(color: blue, width: .45)),
            child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
              pw.Text(item.key, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 5.7, color: blue)),
              pw.SizedBox(height: 3),
              pw.Text(item.value.isEmpty ? '0' : item.value,
                style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold,
                  color: _isZeroDisplay(item.value.isEmpty ? '0' : item.value) ? PdfColors.grey400 : PdfColors.blue900)),
            ]),
          ),
      ],
    );
  }

  static pw.Widget _moneyPanel(String title, Map<String, Object?> entries, Map<String, dynamic> detail, PdfColor accent, PdfColor pale) {
    final visible = entries.entries.where((e) => (_asNumber(e.value) ?? 0).abs() >= 1).toList();
    final rowHeight = visible.length <= 6 ? 27.0 : visible.length <= 9 ? 22.0 : 18.0;
    return pw.Container(
      decoration: pw.BoxDecoration(border: pw.Border.all(color: accent, width: .8)),
      child: pw.Column(children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 8),
          color: pale,
          child: pw.Text(title, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: accent)),
        ),
        if (visible.isEmpty)
          pw.SizedBox(height: rowHeight)
        else
          for (final e in visible)
            pw.Container(
              height: rowHeight,
              padding: const pw.EdgeInsets.symmetric(horizontal: 8),
              decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: accent, width: .3))),
              child: pw.Row(children: [
                pw.Expanded(child: pw.Text(e.key, style: const pw.TextStyle(fontSize: 7.5))),
                pw.Expanded(child: pw.Text(_moneyExplanation(e.key, detail), textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 6))),
                pw.Text(_yen((_asNumber(e.value) ?? 0).abs().toInt()),
                    style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              ]),
            ),
      ]),
    );
  }


  static String _moneyExplanation(String label, Map<String, dynamic> detail) {
    final direct = detail['${label}計算内容'] ?? detail['${label}備考'];
    if (direct != null && direct.toString().trim().isNotEmpty) return direct.toString().trim();
    if (label == '基本給') return _payTypeLabel(detail) == '月給' ? '月固定給' : '勤務実績 × 基本単価';
    if (label.contains('残業')) return '登録単価 × 残業時間';
    if (label.contains('早出')) return '登録単価 × 早出時間';
    if (label.contains('休日')) return '登録単価 × 休日実績';
    return '';
  }

  static pw.Widget _summaryAmount(String label, int amount, PdfColor color) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.Text(label, style: pw.TextStyle(fontSize: 7, color: color)),
      pw.SizedBox(height: 2),
      pw.Text(_yen(amount), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: color)),
    ],
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
      if ((direction > 0 && value > 0) ||
          (direction < 0 && value < 0)) {
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
