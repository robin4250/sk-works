import 'package:flutter/material.dart';

import '../../data/supabase_backend.dart';
import '../settings/company_payroll_rates_repository.dart';
import '../settings/initial_official_company_rates.dart';
import 'company_payroll_rates_home_entry.dart';

/// Runs after sign-in/company registration. Installation alone has no company.
class InitialCompanyRatesCard extends StatefulWidget {
  const InitialCompanyRatesCard({super.key});
  @override
  State<InitialCompanyRatesCard> createState() =>
      _InitialCompanyRatesCardState();
}

class _InitialCompanyRatesCardState extends State<InitialCompanyRatesCard> {
  static final _runs = <String, Future<InitialOfficialRateResult>>{};
  late Future<InitialOfficialRateResult> _run;
  String? _actor;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _actor = SupabaseBackend.isInitialized
        ? SupabaseBackend.client.auth.currentUser?.id
        : null;
    _run = _start();
  }

  Future<InitialOfficialRateResult> _start() async {
    if (_actor == null) return InitialOfficialRateResult.preserved;
    final client = SupabaseBackend.client;
    bool current() => mounted && client.auth.currentUser?.id == _actor;
    final memberships = await client
        .from('company_members')
        .select('company_id,role')
        .eq('user_id', _actor!)
        .limit(2);
    if (!current() ||
        memberships.length != 1 ||
        !const {'owner', 'admin'}.contains(memberships.single['role'])) {
      return InitialOfficialRateResult.preserved;
    }
    final companyId = memberships.single['company_id'] as String;
    final key = '$_actor:$companyId';
    return _runs.putIfAbsent(key, () async {
      final repository = SupabaseCompanyPayrollRatesRepository();
      return InitialOfficialCompanyRates(
        repository: repository,
        fetcher: repository,
        isCurrent: current,
        loadAddress: () async {
          final company = await client
              .from('companies')
              .select('address')
              .eq('id', companyId)
              .single();
          return company['address'] as String? ?? '';
        },
        commit: (version, candidates, fallback) async {
          if (!current()) throw StateError('Session changed');
          final raw = await client.rpc(
            'initialize_official_company_rates',
            params: {
              'p_company_id': companyId,
              'p_scope_version': version,
              'p_candidates': candidates,
              'p_fallback': fallback,
            },
          );
          if (raw is! Map ||
              raw['initialized'] is! bool ||
              (raw['initialized'] == true && raw['fallback'] != fallback)) {
            throw const FormatException('Initial rate result unavailable');
          }
          return raw['initialized'] as bool;
        },
      ).run(companyId);
    });
  }

  Future<void> _openRates() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const CompanyPayrollRatesHomePage()),
    );
    if (!mounted) return;
    _runs.removeWhere((key, _) => key.startsWith('$_actor:'));
    setState(() {
      _run = _start();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed ||
        _actor == null ||
        SupabaseBackend.client.auth.currentUser?.id != _actor) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<InitialOfficialRateResult>(
      future: _run,
      builder: (context, snapshot) {
        if (snapshot.data == InitialOfficialRateResult.preserved) {
          return const SizedBox.shrink();
        }
        final loading = snapshot.connectionState != ConnectionState.done;
        final fallback = snapshot.data == InitialOfficialRateResult.fallback;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loading
                      ? '初期料率を確認しています'
                      : fallback
                      ? '初期参考値で設定しました（最新未確認）'
                      : snapshot.hasError
                      ? '初期料率の保存結果を確認できません'
                      : '公式料率で初期設定しました',
                ),
                if (loading)
                  const LinearProgressIndicator()
                else ...[
                  Text(
                    fallback
                        ? '最新の料率がある可能性があります。税率設定で「最新の公式料率を取得」を押して確認してください。'
                        : snapshot.hasError
                        ? '通信状態と会社の適用条件を確認してください。税率設定で保存済みの値を確認できます。'
                        : '会社の加入条件と適用月をご確認ください。子ども・子育て支援金は初期設定に含めていません。',
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: _openRates,
                        child: const Text('税率設定を確認'),
                      ),
                      if (!fallback && !snapshot.hasError)
                        TextButton(
                          onPressed: () => setState(() => _dismissed = true),
                          child: const Text('閉じる'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
