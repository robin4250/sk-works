import 'package:flutter/material.dart';

import 'unified_company_data_send_page.dart';

class PersonnelBundleSendPage extends StatelessWidget {
  const PersonnelBundleSendPage({
    super.key,
    required this.workerIds,
  });

  final Set<String> workerIds;

  @override
  Widget build(BuildContext context) {
    return UnifiedCompanyDataSendPage(
      kind: CompanyDataSendKind.personnel,
      workerIds: workerIds,
    );
  }
}
