import 'package:flutter/material.dart';

import '../people/unified_company_data_send_page.dart';

class QualificationSendPage extends StatelessWidget {
  const QualificationSendPage({
    super.key,
    required this.workerIds,
  });

  final Set<String> workerIds;

  @override
  Widget build(BuildContext context) {
    return UnifiedCompanyDataSendPage(
      kind: CompanyDataSendKind.qualification,
      workerIds: workerIds,
    );
  }
}
