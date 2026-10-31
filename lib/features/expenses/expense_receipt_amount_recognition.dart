import '../qualifications/qualification_text_recognition_engine.dart';

/// Suggestions only. OCR never creates an expense or changes a saved claim.
class ExpenseReceiptAmountCandidate {
  const ExpenseReceiptAmountCandidate(this.amountYen, this.label, this.explicitTotal);
  final int amountYen;
  final String label;
  final bool explicitTotal;
}

class ExpenseReceiptAmountResult {
  const ExpenseReceiptAmountResult(this.candidates);
  final List<ExpenseReceiptAmountCandidate> candidates;
  int? get unambiguousTotal {
    final totals = candidates.where((candidate) => candidate.explicitTotal).toList();
    return totals.length == 1 ? totals.single.amountYen : null;
  }
}

class ExpenseReceiptAmountRecognition {
  const ExpenseReceiptAmountRecognition();

  /// Existing pinned, on-device Japanese OCR; no new service/upload or model.
  Future<ExpenseReceiptAmountResult> recognize(String localPath) async => parse(
    await const QualificationTextRecognitionEngine().recognizeImagePath(localPath),
  );

  static String _normalize(String input) => String.fromCharCodes(input.runes.map((c) {
    if (c >= 0xff10 && c <= 0xff19) return c - 0xfee0;
    return switch (c) { 0xff0c => 0x2c, 0xffe5 => 0xa5, 0xff0d => 0x2d, 0x3000 => 0x20, _ => c };
  }));

  static int? _yen(String input) {
    final text = input.trim();
    if (!RegExp(r'^(?:[0-9]+|[1-9][0-9]{0,2}(?:,[0-9]{3})+)$').hasMatch(text)) return null;
    final value = int.tryParse(text.replaceAll(',', ''));
    return value != null && value > 0 && value <= 999999999 ? value : null;
  }

  static ExpenseReceiptAmountResult parse(String recognizedText) {
    if (recognizedText.length > 20000) return const ExpenseReceiptAmountResult([]);
    final lines = _normalize(recognizedText).split(RegExp(r'[\r\n]+'))
      .map((line) => line.trim()).where((line) => line.isNotEmpty).toList();
    // A refund/cancellation is not a positive expense. Do not turn its amount
    // into a positive candidate even when OCR puts the label on another line.
    if (lines.any((line) => RegExp(r'返金|返品|取消|キャンセル|払戻|払い戻し|返還').hasMatch(line))) {
      return const ExpenseReceiptAmountResult([]);
    }
    final excluded = RegExp(r'お?預[りか]|お?釣[り銭]?|釣銭|小計|税抜|消費税|外税|内税|税額|単価|数量|ポイント|残高|割引|値引');
    final total = RegExp(r'税込合計|総合計|合計金額|合計|お支払[い]?額|お支払[い]?|ご請求金額|請求金額|領収金額|お買上[げ]?金額');
    final currency = RegExp(r'[¥￥]\s*([0-9][0-9,]*)(?![0-9,.])|(?<![0-9,.])([0-9][0-9,]*)\s*円');
    final bareAmount = RegExp(r'^\s*[:：]?\s*[¥￥]?\s*([0-9][0-9,]*)\s*円?\s*$');
    final byAmount = <int, ExpenseReceiptAmountCandidate>{};
    void add(int amount, String label, bool explicit) {
      final old = byAmount[amount];
      if (old == null || (!old.explicitTotal && explicit)) {
        byAmount[amount] = ExpenseReceiptAmountCandidate(amount, label, explicit);
      }
    }
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (excluded.hasMatch(line) ||
          RegExp(r'[-−‐‑‒–—﹣－▲△]\s*[¥￥]?\s*[0-9]').hasMatch(line) ||
          RegExp(r'[0-9][0-9,]*\s*円?\s*[-−‐‑‒–—﹣－▲△]\s*$').hasMatch(line) ||
          RegExp(r'[（(]\s*[¥￥]?\s*[0-9][0-9,]*\s*円?\s*[）)]').hasMatch(line)) continue;
      final label = total.firstMatch(line);
      if (label != null) {
        final tail = line.substring(label.end);
        final match = bareAmount.firstMatch(tail);
        if (match != null) {
          final value = _yen(match.group(1)!);
          if (value != null) add(value, label.group(0)!, true);
          continue;
        }
        // A label-only line may have its currency amount immediately below it.
        if (tail.trim().isEmpty && index + 1 < lines.length && !excluded.hasMatch(lines[index + 1])) {
          final next = bareAmount.firstMatch(lines[index + 1]);
          if (next != null) {
            final value = _yen(next.group(1)!);
            if (value != null) add(value, label.group(0)!, true);
          }
        }
      }
      for (final match in currency.allMatches(line)) {
        final value = _yen(match.group(1) ?? match.group(2)!);
        if (value != null) add(value, '金額候補', false);
      }
    }
    final values = byAmount.values.toList()
      ..sort((a, b) => a.explicitTotal == b.explicitTotal ? 0 : (a.explicitTotal ? -1 : 1));
    // Never truncate competing totals into an apparently unambiguous result.
    if (values.length > 12) return const ExpenseReceiptAmountResult([]);
    return ExpenseReceiptAmountResult(List.unmodifiable(values));
  }
}
