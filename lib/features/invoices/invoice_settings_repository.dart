import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class InvoiceSettingsData {
  const InvoiceSettingsData({
    required this.companyName,
    required this.taxRate,
    required this.welfareRate,
    required this.templateTitle,
    required this.footerNote,
    required this.bankName,
    required this.bankBranch,
    required this.bankAccountType,
    required this.bankAccountNumber,
    required this.bankAccountHolder,
  });

  final String companyName;
  final double taxRate;
  final double welfareRate;
  final String templateTitle;
  final String footerNote;
  final String bankName;
  final String bankBranch;
  final String bankAccountType;
  final String bankAccountNumber;
  final String bankAccountHolder;
}

class InvoiceSettingsRepository {
  InvoiceSettingsRepository._(this._client);

  final SupabaseClient _client;

  static InvoiceSettingsRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return InvoiceSettingsRepository._(client);
  }

  Future<String> _companyIdForManage() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('ログインが必要です。');

    final rows = await _client
        .from('company_members')
        .select('company_id')
        .eq('user_id', user.id)
        .limit(1);

    if (rows.isEmpty) throw StateError('会社情報が見つかりません。');

    final permissions = await _client.rpc('current_feature_permissions');
    final map = permissions is Map
        ? Map<String, dynamic>.from(permissions)
        : const <String, dynamic>{};

    if (map['can_manage_invoices'] != true) {
      throw StateError('請求書設定を変更する権限がありません。');
    }

    return rows.first['company_id'] as String;
  }

  Future<InvoiceSettingsData> load() async {
    final companyId = await _companyIdForManage();

    final companyRows = await _client
        .from('companies')
        .select(
          'name, tax_rate, default_welfare_rate, '
          'invoice_template_title, invoice_footer_note',
        )
        .eq('id', companyId)
        .limit(1);

    if (companyRows.isEmpty) {
      throw StateError('会社情報が見つかりません。');
    }

    final company = Map<String, dynamic>.from(companyRows.first);

    final billingRows = await _client
        .from('company_private_billing_settings')
        .select(
          'bank_name, bank_branch, bank_account_type, '
          'bank_account_number, bank_account_holder',
        )
        .eq('company_id', companyId)
        .limit(1);

    final billing = billingRows.isEmpty
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(billingRows.first);

    return InvoiceSettingsData(
      companyName: company['name']?.toString() ?? '',
      taxRate: (company['tax_rate'] as num?)?.toDouble() ?? 10,
      welfareRate:
          (company['default_welfare_rate'] as num?)?.toDouble() ?? 0,
      templateTitle:
          company['invoice_template_title']?.toString() ?? '請求書',
      footerNote: company['invoice_footer_note']?.toString() ?? '',
      bankName: billing['bank_name']?.toString() ?? '',
      bankBranch: billing['bank_branch']?.toString() ?? '',
      bankAccountType:
          billing['bank_account_type']?.toString() ?? '普通',
      bankAccountNumber:
          billing['bank_account_number']?.toString() ?? '',
      bankAccountHolder:
          billing['bank_account_holder']?.toString() ?? '',
    );
  }

  Future<void> save(InvoiceSettingsData value) async {
    await _companyIdForManage();

    await _client.rpc(
      'save_invoice_settings',
      params: {
        'p_tax_rate': value.taxRate,
        'p_welfare_rate': value.welfareRate,
        'p_template_title': value.templateTitle,
        'p_footer_note': value.footerNote,
        'p_bank_name': value.bankName,
        'p_bank_branch': value.bankBranch,
        'p_bank_account_type': value.bankAccountType,
        'p_bank_account_number': value.bankAccountNumber,
        'p_bank_account_holder': value.bankAccountHolder,
      },
    );
  }
}
