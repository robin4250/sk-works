import '../../domain/company_seal_design.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class CompanySealStyleSettings {
  const CompanySealStyleSettings({
    required this.companyId,
    required this.name,
    required this.style,
    required this.available,
    this.documentSnapshotsAvailable = false,
    this.pngStyles = const [],
  });
  final String companyId;
  final String name;
  final String style;
  final bool available;
  final bool documentSnapshotsAvailable;
  final List<String> pngStyles;
}

class CompanySealStyleRepository {
  CompanySealStyleRepository._(this._client);
  final SupabaseClient _client;

  static CompanySealStyleRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized ||
        SupabaseBackend.client.auth.currentUser == null) {
      return null;
    }
    return CompanySealStyleRepository._(SupabaseBackend.client);
  }

  Future<({String companyId, String name})> loadContext() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Authentication required.');
    // Never guess a target company from the first membership.
    final memberships = await _client
        .from('company_members')
        .select('company_id,role')
        .eq('user_id', user.id);
    if (memberships.length != 1 ||
        !['owner', 'admin'].contains(memberships.single['role'])) {
      throw StateError('An exact administrator company is required.');
    }
    final companyId = memberships.single['company_id'] as String;
    final value = await _client
        .from('companies')
        .select('name')
        .eq('id', companyId)
        .single();
    return (companyId: companyId, name: value['name'] as String);
  }

  Future<CompanySealStyleSettings> load(
    ({String companyId, String name}) context,
  ) async {
    final companyId = context.companyId;
    try {
      final result = await _client.rpc(
        'company_seal_style_settings',
        params: {'p_company_id': companyId},
      );
      final value = Map<String, dynamic>.from(result as Map);
      if (value['company_id'] != companyId ||
          (value['company_seal_style'] is! String ||
              !CompanySealDesign.supported(
                value['company_seal_style'] as String,
              ))) {
        throw StateError('Unexpected company seal settings.');
      }
      final styles = (value['png_styles'] as List? ?? const []).cast<String>();
      if (styles.any((style) => !CompanySealDesign.isPng(style)) ||
          (CompanySealDesign.isPng(value['company_seal_style'] as String) &&
              !styles.contains(value['company_seal_style'])) ||
          ((styles.isNotEmpty ||
                  CompanySealDesign.isPng(
                    value['company_seal_style'] as String,
                  )) &&
              !CompanySealDesign.matches(
                companyId,
                value['company_name'] as String,
              ))) {
        throw StateError('Unexpected PNG seal company.');
      }
      return CompanySealStyleSettings(
        companyId: companyId,
        name: value['company_name'] as String,
        style: value['company_seal_style'] as String,
        available: true,
        documentSnapshotsAvailable: value['document_snapshot_version'] == 1,
        pngStyles: List.unmodifiable(styles),
      );
    } on PostgrestException catch (error) {
      if (error.code != 'PGRST202' && error.code != '42883') rethrow;
      return CompanySealStyleSettings(
        companyId: companyId,
        name: context.name,
        style: 'legacy',
        available: false,
      );
    }
  }

  Future<void> save(CompanySealStyleSettings settings, String style) async {
    if (!settings.available) throw StateError('Style saving is unavailable.');
    final result = await _client.rpc(
      'save_company_seal_style',
      params: {
        'p_company_id': settings.companyId,
        'p_style': style,
        'p_expected_name': settings.name,
      },
    );
    final value = Map<String, dynamic>.from(result as Map);
    if (value['company_id'] != settings.companyId ||
        value['company_seal_style'] != style) {
      throw StateError('Saved company seal style was not confirmed.');
    }
  }
}
