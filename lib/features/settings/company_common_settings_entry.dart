import 'package:flutter/material.dart';
import '../auth/secondary_protected_page.dart';
import 'company_common_settings_page.dart';

class CompanyCommonSettingsEntry extends StatelessWidget {
  const CompanyCommonSettingsEntry({super.key, required this.companyId, required this.canManageCompany});
  final String companyId;
  final bool canManageCompany;
  @override
  Widget build(BuildContext context) {
    if (!canManageCompany || companyId.trim().isEmpty) return const SizedBox.shrink();
    return Card(child: ListTile(
      leading: const Icon(Icons.receipt_long_outlined),
      title: const Text('会社共通設定'),
      subtitle: const Text('消費税・福利厚生費・追加式の支給／控除'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
        SecondaryProtectedPage(title: '会社共通設定',
          child: CompanyCommonSettingsPage(companyId: companyId)))),
    ));
  }
}
