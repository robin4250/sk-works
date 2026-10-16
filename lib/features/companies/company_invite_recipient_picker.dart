import 'package:flutter/material.dart';
import 'trade_company_repository.dart';

/// Uses the authorized directory already loaded by the company list.
class CompanyInviteRecipientPicker extends StatelessWidget {
  const CompanyInviteRecipientPicker({
    super.key,
    required this.companies,
    required this.onSelected,
  });

  final List<TradeCompanyRecord> companies;
  final ValueChanged<TradeCompanyRecord?> onSelected;

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
          ListTile(
            leading: const Icon(Icons.dialpad),
            title: const Text('電話番号を直接入力'),
            subtitle: const Text('会社が未登録の相手にも招待できます'),
            onTap: () => onSelected(null),
          ),
          const Divider(),
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
