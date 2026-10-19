import 'package:supabase_flutter/supabase_flutter.dart';

/// Employee membership invitations and initial QR credentials are intentionally
/// outside this repository. No client API awards points or confirms identity.
class AppReferralRepository {
  const AppReferralRepository(this.client);
  final SupabaseClient client;
  String? get currentActorId => client.auth.currentUser?.id;
  Stream<String?> watchActorChanges() => client.auth.onAuthStateChange
      .map((state) => state.session?.user.id).distinct();

  Future<Map<String, dynamic>> load({bool master = false}) async {
    dynamic raw;
    try {
      raw = await client.rpc('app_distribution_snapshot', params: {'p_master': master});
    } on PostgrestException catch (error) {
      if (error.code != 'PGRST202') rethrow;
      raw = await client.rpc(master ? 'app_referral_master_snapshot' : 'app_referral_snapshot');
    }
    return Map<String, dynamic>.from(raw as Map);
  }

  Future<Map<String, dynamic>> prepare(
    String name,
    String phone, {
    bool friendInvite = false,
  }) async {
    final raw = await client.rpc(
      'app_referral_prepare',
      params: {
        'p_name': name.trim(),
        'p_phone': phone.trim(),
        'p_source': friendInvite ? 'friend_add' : 'app_invite',
      },
    );
    return Map<String, dynamic>.from(raw as Map);
  }

  Future<Map<String, dynamic>> prepareDistribution(
    String name, String phone, String channel, String kind,
  ) async {
    final raw = await client.rpc('app_distribution_prepare', params: {
      'p_name': name.trim(), 'p_phone': phone.trim(),
      'p_channel': channel, 'p_kind': kind,
    });
    return Map<String, dynamic>.from(raw as Map);
  }

  Future<void> saveDistributionLinks(String testflight, String web, String guide) =>
    client.rpc('app_distribution_save_links', params: {
      'p_testflight_url': testflight.trim(), 'p_web_url': web.trim(),
      'p_public_url': guide.trim(),
    });

  /// Flags and channel links are separate server writes. The atomic RPC never
  /// sends or rewrites the legacy distribution URL. A partial backend rollout
  /// fails closed; do not fall back to a read-then-write of a stale URL.
  Future<void> saveSettingsPreservingDistributionUrl({
    required bool enabled,
    required bool publicEnabled,
    required bool notifyMaster,
  }) => client.rpc('app_referral_save_flags', params: {
    'p_enabled': enabled,
    'p_public_enabled': publicEnabled,
    'p_notify_master': notifyMaster,
  });

  Future<void> recordComposerOpened(String id) => client.rpc(
    'app_referral_composer_opened',
    params: {'p_invitation_id': id},
  );

  Future<void> saveSettings({
    required bool enabled,
    required bool publicEnabled,
    required bool notifyMaster,
    required String url,
  }) => client.rpc(
    'app_referral_save_settings',
    params: {
      'p_enabled': enabled,
      'p_public_enabled': publicEnabled,
      'p_notify_master': notifyMaster,
      'p_distribution_url': url.trim(),
    },
  );
}

String referralJapanTime(String value) {
  final date = DateTime.tryParse(value)?.toUtc().add(const Duration(hours: 9));
  if (date == null) return '日時不明';
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}/${two(date.month)}/${two(date.day)} ${two(date.hour)}:${two(date.minute)} JST';
}

