import 'package:flutter/material.dart';

import '../../data/supabase_backend.dart';
import '../../international/language_controller.dart';
import '../settings/company_payroll_rates_page.dart';

/// A direct home entry: viewers must not need the administrator settings menu.
class CompanyPayrollRatesHomeEntry extends StatelessWidget {
  const CompanyPayrollRatesHomeEntry({super.key});

  @override
  Widget build(BuildContext context) {
    final border = BorderSide(
      color: Theme.of(context).colorScheme.primary,
      width: 1.8,
    );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        border: Border.fromBorderSide(border),
        borderRadius: BorderRadius.circular(23),
      ),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          side: border,
          borderRadius: BorderRadius.circular(20),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: const Icon(Icons.percent),
          title: Text(SkoLanguageController.isEnglish ? 'Tax rates' : '税率設定'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const CompanyPayrollRatesHomePage(),
            ),
          ),
        ),
      ),
    );
  }
}

class CompanyPayrollRatesHomePage extends StatefulWidget {
  const CompanyPayrollRatesHomePage({super.key, this.resolveCompanyId});

  final Future<String> Function()? resolveCompanyId;

  @override
  State<CompanyPayrollRatesHomePage> createState() =>
      _CompanyPayrollRatesHomePageState();
}

class _CompanyPayrollRatesHomePageState
    extends State<CompanyPayrollRatesHomePage> {
  late Future<String> _companyId;

  @override
  void initState() {
    super.initState();
    _companyId = _resolve();
  }

  Future<String> _resolve() async {
    if (widget.resolveCompanyId != null) return widget.resolveCompanyId!();
    final client = SupabaseBackend.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw StateError('Missing session');
    // Use the same company membership selection as the existing settings page.
    final rows = await client
        .from('company_members')
        .select('company_id, role')
        .eq('user_id', userId)
        .limit(1);
    if (client.auth.currentUser?.id != userId || rows.isEmpty) {
      throw StateError('Membership unavailable');
    }
    final row = rows.first;
    if (!const {'owner', 'admin', 'viewer'}.contains(row['role'])) {
      throw StateError('Tax rates are unavailable for this role');
    }
    final id = row['company_id'];
    if (id is! String || id.isEmpty) throw StateError('Missing company');
    return id;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _companyId,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.done &&
          snapshot.hasData) {
        // The existing page uses the server's can_edit result for editing.
        return CompanyPayrollRatesPage(companyId: snapshot.data!);
      }
      final english = SkoLanguageController.isEnglish;
      return Scaffold(
        appBar: AppBar(
          toolbarHeight: kToolbarHeight,
          title: Text(english ? 'Tax rates' : '税率設定'),
        ),
        body: Center(
          child:
              snapshot.connectionState == ConnectionState.done &&
                  snapshot.hasError
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      english
                          ? 'Could not load company information.'
                          : '会社情報を読み込めませんでした。',
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => setState(() {
                        _companyId = _resolve();
                      }),
                      child: Text(english ? 'Retry' : '再試行'),
                    ),
                  ],
                )
              : const CircularProgressIndicator(),
        ),
      );
    },
  );
}
