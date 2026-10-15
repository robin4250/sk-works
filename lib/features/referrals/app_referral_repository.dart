import 'package:supabase_flutter/supabase_flutter.dart';

/// Employee membership invitations and initial QR credentials are intentionally
/// outside this repository. No client API awards points or confirms identity.
class AppReferralRepository {
  const AppReferralRepository(this.client);
  final SupabaseClient client;

  Future<Map<String, dynamic>> load({bool master = false}) async {
    final raw = await client.rpc(
      master ? 'app_referral_master_snapshot' : 'app_referral_snapshot',
    );
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
