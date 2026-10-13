import 'package:flutter/material.dart';
import 'company_allowance_identity_page.dart';
import 'company_allowance_identity_repository.dart';
import 'company_allowance_identity_helper.dart';

class CompanyAllowanceIdentityEntry extends StatelessWidget {
  const CompanyAllowanceIdentityEntry({super.key, required this.companyId, required this.canManageCompany, this.repository, this.pendingStore});
  final String companyId;
  final bool canManageCompany;
  final CompanyAllowanceIdentityRepository? repository;
  final CompanyAllowanceIdentityPendingStore? pendingStore;

  @override
  Widget build(BuildContext context) {
    if (!canManageCompany || companyId.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(child: ListTile(
      leading: const Icon(Icons.receipt_long_outlined),
      title: const Text('会社共通手当'),
      subtitle: const Text('登録済み手当の確認・編集・廃止'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CompanyAllowanceIdentityPage(
        companyId: companyId, repository: repository, pendingStore: pendingStore))),
    ));
  }
}
