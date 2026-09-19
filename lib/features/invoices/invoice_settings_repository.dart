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

  Future<({String companyId, String role})> _membership() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('ログインが必要です。');

    final rows = await _client
        .from('company_members')
        .select('company_id, role')
        .eq('user_id', user.id)
        .limit(1);

    if (rows.isEmpty) throw StateError('会社情報が見つかりません。');

    final role = rows.first['role']?.toString() ?? 'viewer';
    if (role != 'owner' && role != 'admin') {
      throw StateError('請求書設定は管理者だけ変更できます。');
    }

    return (
      companyId: rows.first['company_id'] as String,
      role: role,
    );
  }

  Future<InvoiceSettingsData> load() async {
    final membership = await _membership();

    final rows = await _client
        .from('companies')
        .select(
          'name, tax_rate, default_welfare_rate, invoice_template_title, invoice_footer_note, bank_name, bank_branch, bank_account_type, bank_account_number, bank_account_holder',
        )
        .eq('id', membership.companyId)
        .limit(1);

    if (rows.isEmpty) throw StateError('会社情報が見つかりません。');
    final row = Map<String, dynamic>.from(rows.first);

    return InvoiceSettingsData(
      companyName: row['name']?.toString() ?? '',
      taxRate: (row['tax_rate'] as num?)?.toDouble() ?? 10,
      welfareRate:
          (row['default_welfare_rate'] as num?)?.toDouble() ?? 0,
      templateTitle:
          row['invoice_template_title']?.toString() ?? '請求書',
      footerNote: row['invoice_footer_note']?.toString() ?? '',
      bankName: row['bank_name']?.toString() ?? '',
      bankBranch: row['bank_branch']?.toString() ?? '',
      bankAccountType: row['bank_account_type']?.toString() ?? '普通',
      bankAccountNumber: row['bank_account_number']?.toString() ?? '',
      bankAccountHolder: row['bank_account_holder']?.toString() ?? '',
    );
  }

  Future<void> save(InvoiceSettingsData value) async {
    final membership = await _membership();

    await _client.from('companies').update({
      'tax_rate': value.taxRate,
      'default_welfare_rate': value.welfareRate,
      'invoice_template_title': value.templateTitle.trim().isEmpty
          ? '請求書'
          : value.templateTitle.trim(),
      'invoice_footer_note': _nullable(value.footerNote),
      'bank_name': _nullable(value.bankName),
      'bank_branch': _nullable(value.bankBranch),
      'bank_account_type': _nullable(value.bankAccountType),
      'bank_account_number': _nullable(value.bankAccountNumber),
      'bank_account_holder': _nullable(value.bankAccountHolder),
    }).eq('id', membership.companyId);
  }

  Object? _nullable(String value) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }
}
