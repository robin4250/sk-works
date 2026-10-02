import 'package:flutter/material.dart';

import 'company_transfer_send_page.dart';

class SignatureSendPage extends StatelessWidget {
  const SignatureSendPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const CompanyTransferSendPage(
      title: 'サイン一覧を送信',
      sourceKind: 'daily_report_signature',
      subjectLabel: 'サイン',
      workerIds: <String>{},
      description: '日報に保存済みの責任者・代表者・監督者サインから、全部または必要なサインだけを選択して送信します。',
    );
  }
}
