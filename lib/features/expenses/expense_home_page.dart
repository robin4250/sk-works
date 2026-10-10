import 'package:flutter/material.dart';
import 'expense_personal_page.dart';
import 'expense_management_page.dart';

class ExpenseHomePage extends StatelessWidget {
  const ExpenseHomePage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(toolbarHeight: kToolbarHeight, title: const Text('経費')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          leading: const Icon(Icons.receipt_long),
          title: const Text('自分の経費申請'),
          subtitle: const Text('申請・利用月ごとの履歴'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const ExpensePersonalPage(),
            ),
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.fact_check),
          title: const Text('全員の申請・振り分け'),
          subtitle: const Text('管理者・経費の承認担当'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const ExpenseManagementPage(),
            ),
          ),
        ),
      ],
    ),
  );
}
