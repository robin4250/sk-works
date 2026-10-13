import 'package:flutter/material.dart';

import 'company_transfer_send_page.dart';

class PersonnelBundleSendPage extends StatelessWidget {
  const PersonnelBundleSendPage({
    super.key,
    required this.workerIds,
  });

  final Set<String> workerIds;

  @override
  Widget build(BuildContext context) {
    return CompanyTransferSendPage(
      title: '社員データを送信',
      sourceKind: 'worker_personnel',
      subjectLabel: '社員',
      workerIds: workerIds,
      description: '社員の基本情報・資格・必要書類を一式で送信します。出所会社情報も保持します。',
    );
  }
}
