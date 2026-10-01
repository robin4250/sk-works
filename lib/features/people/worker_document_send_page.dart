import 'package:flutter/material.dart';

import 'company_transfer_send_page.dart';

class WorkerDocumentSendPage extends StatelessWidget {
  const WorkerDocumentSendPage({
    super.key,
    required this.workerIds,
  });

  final Set<String> workerIds;

  @override
  Widget build(BuildContext context) {
    return CompanyTransferSendPage(
      title: '必要書類を送信',
      sourceKind: 'worker_document',
      subjectLabel: '書類',
      workerIds: workerIds,
      description: '送信可能な必要書類から、全部または必要な書類だけを選択して送信します。',
    );
  }
}
