import 'package:flutter/material.dart';
import 'expense_personal_page.dart';
import 'expense_management_page.dart';
import 'expense_surface_card.dart';

class ExpenseHomePage extends StatelessWidget {
  const ExpenseHomePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xfff5f7fa),
    appBar: AppBar(toolbarHeight: kToolbarHeight, title: const Text('経費')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _entry(context, Icons.receipt_long_outlined, '自分の経費申請',
          '申請・利用月ごとの履歴', const ExpensePersonalPage()),
        const SizedBox(height: 12),
        _entry(context, Icons.fact_check_outlined, '全員の申請・振り分け',
          '管理者・経費の承認担当', const ExpenseManagementPage()),
      ],
    ),
  );

  Widget _entry(BuildContext context, IconData icon, String title,
    String subtitle, Widget page) {
    void open() => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page));
    final colors = Theme.of(context).colorScheme;
    return ExpenseSurfaceCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          CircleAvatar(radius: 17,
            backgroundColor: colors.primary.withValues(alpha: .09),
            child: Icon(icon, color: colors.primary, size: 22)),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(
            fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87))),
          IconButton(tooltip: title, onPressed: open,
            icon: const Icon(Icons.chevron_right), color: colors.primary),
        ]),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 12),
        Align(alignment: Alignment.centerRight, child: SizedBox(width: 112,
          child: OutlinedButton(
            onPressed: open,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(112, 44), foregroundColor: colors.primary,
              side: BorderSide(color: colors.primary),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: const Text('開く', style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700)),
          ))),
      ]),
    );
  }
}
