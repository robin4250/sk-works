import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/company_seal_snapshot.dart';
import 'trade_document_actor_boundary.dart';

/// Attach only current preview metadata. Never use this on finalized documents.
Future<Map<String, dynamic>> companyWithCurrentUploadedSeal(
    SupabaseClient client, Map<String, dynamic> company, String companyId) async {
  final actor = client.auth.currentUser?.id;
  if (actor == null) throw StateError('ログインが必要です。');
  final lease = TradeDocumentActorLease(initialActor: actor,
    actorChanges: client.auth.onAuthStateChange.map((event) => event.session?.user.id));
  try {
    final raw = await client.rpc('company_current_uploaded_seal', params: {'p_company_id': companyId});
    lease.verify();
    if (raw is! Map || raw['company_id'] != companyId || raw['company_name'] != company['name']) {
      throw StateError('現在の会社角印を確認できません。');
    }
    final value = raw['snapshot'];
    if (value != null) {
      final snapshot = CompanySealSnapshot.fromJson(value);
      if (snapshot.companyId != companyId || snapshot.name != company['name'] || snapshot.uploadedPng == null) {
        throw StateError('現在の会社角印の対象が一致しません。');
      }
    }
    return {...company, 'company_seal_uploaded_snapshot': value};
  } on PostgrestException catch (e) {
    lease.verify();
    if (e.code != 'PGRST202' && e.code != '42883') rethrow;
    return company;
  } finally { lease.dispose(); }
}
