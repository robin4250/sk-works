import 'package:flutter/material.dart';

/// Company entry point prepared independently of the not-yet-installed archive
/// service. Existing registration and document generation remain accessible.
/// Do not replace this gate with a local success list or name-matched PDFs.
class SiteOrderCompanyPage extends StatelessWidget {
  const SiteOrderCompanyPage({super.key, required this.tradeCompanyId,
    required this.companyName, required this.openCompanyDetails});
  final String tradeCompanyId, companyName;
  final Future<void> Function() openCompanyDetails;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('$companyName の注文書')),
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
      Text(companyName, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 16),
      const Text('注文書・請書をまとめて保管する機能は準備中です。'
        '現在の会社情報と帳票生成は下のボタンから利用できます。'),
      const SizedBox(height: 16),
      const OutlinedButton(onPressed: null, child: Text('受信した注文書・承認待ち')),
      const OutlinedButton(onPressed: null, child: Text('過去の注文書・請書')),
      FilledButton.icon(onPressed: openCompanyDetails,
        icon: const Icon(Icons.business_outlined),
        label: const Text('会社情報・既存の帳票生成を開く')),
    ])));
}
