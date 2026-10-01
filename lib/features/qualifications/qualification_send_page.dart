import 'package:flutter/material.dart';

import '../people/company_transfer_send_page.dart';

class QualificationSendPage extends StatelessWidget {
  const QualificationSendPage({
    super.key,
    required this.workerIds,
  });

  final Set<String> workerIds;

  @override
  Widget build(BuildContext context) {
    return CompanyTransferSendPage(
      title: '資格データを送信',
      sourceKind: 'worker_qualification',
      subjectLabel: '資格',
      workerIds: workerIds,
      description: '資格情報と登録済み資格証画像を、全部または選択した資格だけ送信します。',
    );
  }
}
