import 'package:flutter/material.dart';

/// Unpublished, read-only presentation of a server-verified review result.
/// The caller must obtain `review` through the authenticated server contract
/// each time this page is opened; this widget does not grant access.
class InvoiceRevisionReviewPage extends StatelessWidget {
  const InvoiceRevisionReviewPage({super.key, required this.review});
  final Map<String, dynamic> review;

  @override
  Widget build(BuildContext context) {
    final snapshot = review['proposed_snapshot'];
    final grandTotal = review['grand_total'];
    if (review['status'] != 'review_only' || snapshot is! Map ||
        snapshot.containsKey('company_seal_snapshot') ||
        snapshot.containsKey('approval_snapshot') ||
        snapshot['sites'] is! List || !_validAmount(grandTotal) ||
        (snapshot.containsKey('expense_extra_amount_yen') && !_validAmount(snapshot['expense_extra_amount_yen'])) ||
        (snapshot.containsKey('document_final_adjustment_yen') && !_validAmount(snapshot['document_final_adjustment_yen']))) {
      return Scaffold(
        appBar: AppBar(title: const Text('請求書の訂正案')),
        body: const SafeArea(child: Center(child: Text('訂正案を確認できません。再読み込みしてください。'))),
      );
    }
    final sites = snapshot['sites'] as List;
    final valid = sites.every((site) => site is Map &&
        site['site_name'] is String && site['lines'] is List &&
        (site['lines'] as List).every((line) => line is Map &&
            line['work_content'] is String && _validAmount(line['amount']) &&
            (line['quantity'] == null || _validQuantity(line['quantity']))));
    if (!valid) {
      return Scaffold(
        appBar: AppBar(title: const Text('請求書の訂正案')),
        body: const SafeArea(child: Center(child: Text('訂正案の内訳を確認できません。再読み込みしてください。'))),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('請求書の訂正案')),
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(color: Theme.of(context).colorScheme.secondaryContainer,
            child: const Padding(padding: EdgeInsets.all(16), child: Text(
              '訂正案・未発行\nこの画面は内容確認用です。以前の請求書と印影は保存されています。',
              style: TextStyle(fontWeight: FontWeight.bold)))),
          const SizedBox(height: 8),
          for (final rawSite in sites) ...[
            Builder(builder: (context) {
              final site = rawSite as Map;
              final lines = site['lines'] as List;
              return Card(child: Padding(padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(site['site_name'] as String, style: Theme.of(context).textTheme.titleMedium),
                  for (final rawLine in lines)
                    Builder(builder: (context) {
                      final line = rawLine as Map;
                      final quantity = line['quantity'];
                      return ListTile(contentPadding: EdgeInsets.zero,
                        title: Text(line['work_content'] as String),
                        subtitle: quantity == null || quantity == 0 ? null : Text('数量 ${_decimal(quantity as num)}'),
                        trailing: Text('${_money(line['amount'] as num)}円'));
                    }),
                ])));
            }),
          ],
          if ((snapshot['expense_extra_amount_yen'] as num? ?? 0) != 0)
            ListTile(title: const Text('経費等'), trailing: Text('${_money(snapshot['expense_extra_amount_yen'] as num)}円')),
          if ((snapshot['document_final_adjustment_yen'] as num? ?? 0) != 0)
            ListTile(title: const Text('追加・調整'), trailing: Text('${_money(snapshot['document_final_adjustment_yen'] as num)}円')),
          Card(child: ListTile(title: const Text('訂正案の請求金額'),
            trailing: Text('${_money(grandTotal as num)}円',
              style: const TextStyle(fontWeight: FontWeight.bold)))),
        ],
      )),
    );
  }
}

bool _validAmount(Object? value) => value is num && value.isFinite &&
    value == value.roundToDouble() && value.abs() <= 2147483647;
bool _validQuantity(Object? value) => value is num && value.isFinite && value.abs() <= 1000000;
String _decimal(num value) => value == value.roundToDouble()
    ? value.toInt().toString() : value.toString();
String _money(num value) => value.toInt().toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
