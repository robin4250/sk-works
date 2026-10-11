import 'package:flutter/material.dart';

import '../../international/language_controller.dart';

class EmployeeResourcesPage extends StatelessWidget {
  const EmployeeResourcesPage({
    super.key,
    required this.availableKeys,
    required this.onOpen,
  });
  final Set<String> availableKeys;
  final Future<void> Function(String) onOpen;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(SkoLanguageController.tr('社員資格書類'))),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final entry in const <(String, String, IconData)>[
          ('people', '社員データ', Icons.groups_2_outlined),
          ('employee_qualifications', '従業員資格', Icons.badge_outlined),
          ('documents', '必要書類', Icons.fact_check_outlined),
        ])
          if (availableKeys.contains(entry.$1))
            Card(
              child: ListTile(
                leading: Icon(entry.$3),
                title: Text(SkoLanguageController.tr(entry.$2)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onOpen(entry.$1),
              ),
            ),
      ],
    ),
  );
}
