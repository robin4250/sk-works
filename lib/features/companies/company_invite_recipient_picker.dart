import 'package:flutter/material.dart';
import 'trade_company_repository.dart';

/// Uses the authorized directory already loaded by the company list.
class CompanyInviteRecipientPicker extends StatelessWidget {
  const CompanyInviteRecipientPicker({
    super.key,
    required this.companies,
    required this.onSelected,
    this.allowDirect = true,
  });

  final List<TradeCompanyRecord> companies;
  final ValueChanged<TradeCompanyRecord?> onSelected;
  final bool allowDirect;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .65,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('SKO招待', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ),
          if (allowDirect) ListTile(
            leading: const Icon(Icons.dialpad),
            title: const Text('電話番号を直接入力'),
            subtitle: const Text('会社が未登録の相手にも招待できます'),
            onTap: () => onSelected(null),
          ),
          if (allowDirect) const Divider(),
          if (companies.isEmpty && !allowDirect)
            const Padding(padding: EdgeInsets.all(16), child: Text('先に会社一覧に招待先を登録してください。')),
          Expanded(
            child: ListView.builder(
              itemCount: companies.length,
              itemBuilder: (context, index) {
                final company = companies[index];
                final phone = company.representativePhone.trim();
                return ListTile(
                  leading: const Icon(Icons.business_outlined),
                  title: Text(company.name),
                  subtitle: Text(phone.isEmpty
                      ? '代表者の電話番号が未登録です。次の画面で入力できます。'
                      : '${company.representativeName}　$phone'),
                  onTap: () => onSelected(company),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
