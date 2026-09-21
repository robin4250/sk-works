import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class RequiredDocumentAttention {
  const RequiredDocumentAttention({
    required this.missingCount,
    required this.missingNames,
    required this.needsLicense,
    required this.needsQualification,
  });

  final int missingCount;
  final List<String> missingNames;
  final bool needsLicense;
  final bool needsQualification;

  bool get hasMissing => missingCount > 0;
}

class HomeAttentionRepository {
  HomeAttentionRepository._(this._client);

  final SupabaseClient _client;

  static HomeAttentionRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    if (SupabaseBackend.client.auth.currentUser == null) return null;
    return HomeAttentionRepository._(SupabaseBackend.client);
  }

  Future<RequiredDocumentAttention> loadRequiredDocumentAttention() async {
    final value = await _client.rpc('current_user_required_document_attention');
    if (value is! Map) {
      return const RequiredDocumentAttention(
        missingCount: 0,
        missingNames: [],
        needsLicense: false,
        needsQualification: false,
      );
    }
    final row = Map<String, dynamic>.from(value);
    final names = <String>[
      for (final item in (row['missing_names'] as List<dynamic>? ?? const []))
        item.toString(),
    ];
    return RequiredDocumentAttention(
      missingCount: row['missing_count'] is int
          ? row['missing_count'] as int
          : int.tryParse(row['missing_count']?.toString() ?? '') ?? 0,
      missingNames: names,
      needsLicense: row['needs_license'] == true,
      needsQualification: row['needs_qualification'] == true,
    );
  }
}
