import 'package:flutter/material.dart';

import '../people/own_bank_account_page.dart';
import '../people/own_bank_account_repository.dart';

/// An opaque SDK session identity; never stores account contents or tokens.
class ProfileOwnBankScope {
  const ProfileOwnBankScope({required this.session, required this.workerId, required this.companyId});
  final Object session;
  final String workerId, companyId;
  bool sameAs(ProfileOwnBankScope other) => identical(session, other.session) &&
      workerId == other.workerId && companyId == other.companyId;
}

/// Entry only. The canonical repository independently checks the captured
/// session, current membership and active worker ownership before any operation.
/// Existing accounts remain metadata-only; this adds no edit/delete capability.
class ProfileOwnBankEntry extends StatelessWidget {
  const ProfileOwnBankEntry({
    super.key,
    required this.workerId,
    required this.companyId,
    this.bankGateway,
    this.currentScope,
    this.onReturned,
  });

  final String? workerId;
  final String? companyId;
  final ProfileOwnBankScope? Function()? currentScope;
  final Future<void> Function()? onReturned;

  @visibleForTesting
  final OwnBankAccountGateway? bankGateway;

  static final _uuid = RegExp(
    r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
    caseSensitive: false,
  );

  @override
  Widget build(BuildContext context) {
    final worker = workerId, company = companyId;
    final available = worker != null && company != null &&
        _uuid.hasMatch(worker) && _uuid.hasMatch(company);
    return ListTile(
      key: const Key('profile-own-bank-entry'),
      leading: const CircleAvatar(child: Icon(Icons.account_balance_outlined)),
      title: const Text('個人銀行口座'),
      subtitle: Text(available
          ? '登録状態の確認・未登録口座の登録'
          : '本人と所属会社の情報を再読み込みしてください'),
      trailing: const Icon(Icons.chevron_right),
      enabled: available,
      onTap: available
          ? () async {
              final before = currentScope?.call();
              if (onReturned != null && (before == null ||
                  before.workerId != worker || before.companyId != company)) {
                return;
              }
              await Navigator.of(context).push<void>(MaterialPageRoute(
                builder: (_) => OwnBankAccountPage(
                  workerId: worker,
                  companyId: company,
                  gateway: bankGateway,
                ),
              ));
              if (!context.mounted || before == null) return;
              final current = context.widget;
              if (current is! ProfileOwnBankEntry || current.workerId != worker ||
                  current.companyId != company) {
                return;
              }
              final after = current.currentScope?.call();
              if (after == null || !before.sameAs(after)) return;
              await current.onReturned?.call();
            }
          : null,
    );
  }
}
