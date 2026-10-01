import 'package:flutter/material.dart';

import 'unified_company_data_send_page.dart';

class WorkerDocumentSendPage extends StatelessWidget {
  const WorkerDocumentSendPage({
    super.key,
    required this.workerIds,
  });

  final Set<String> workerIds;

  @override
  Widget build(BuildContext context) {
    return UnifiedCompanyDataSendPage(
      kind: CompanyDataSendKind.workerDocument,
      workerIds: workerIds,
    );
  }
}
