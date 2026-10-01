import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class QualificationRecognitionRepository {
  QualificationRecognitionRepository._(this._client);

  final SupabaseClient _client;

  static QualificationRecognitionRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return QualificationRecognitionRepository._(client);
  }

  Future<Map<String, List<Map<String, dynamic>>>> loadMatchingData() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('SKOへのログインが必要です。');
    final memberships = await _client
        .from('company_members')
        .select('company_id')
        .eq('user_id', user.id)
        .limit(1);
    if (memberships.isEmpty) throw StateError('会社情報が見つかりません。');
    final companyId = memberships.first['company_id'] as String;

    final values = await Future.wait([
      _client
          .from('qualification_master')
          .select('id, name, category, issuer, expiry_required, is_active')
          .eq('company_id', companyId)
          .eq('is_active', true)
          .order('name'),
      _client
          .from('qualification_master_aliases')
          .select('qualification_master_id, alias_name')
          .eq('company_id', companyId),
      _client
          .from('workers')
          .select('id, name')
          .eq('company_id', companyId)
          .eq('status', 'active')
          .order('name'),
    ]);

    return {
      'masters': List<Map<String, dynamic>>.from(values[0] as List),
      'aliases': List<Map<String, dynamic>>.from(values[1] as List),
      'workers': List<Map<String, dynamic>>.from(values[2] as List),
    };
  }
}
