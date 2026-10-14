class MasterSelfOperationAuditEvent {
  const MasterSelfOperationAuditEvent({required this.action, required this.at});
  final String action;
  final DateTime at;

  static const actions = <String, (String, String)>{
    'master_device_bootstrap': (
      '最初のマスター端末を登録',
      'First master device registered',
    ),
    'master_device_lock': ('マスター端末をロック', 'Master device locked'),
    'master_device_unlock': ('マスター端末のロックを解除', 'Master device unlocked'),
    'master_device_revoke': ('マスター端末を失効', 'Master device revoked'),
    'master_recovery_contacts_update': (
      '復旧連絡先を更新',
      'Recovery contacts updated',
    ),
    'master_recovery_challenge_issued': (
      '復旧確認を発行',
      'Recovery challenge issued',
    ),
    'master_recovery_code_verified': ('復旧コードを確認', 'Recovery code verified'),
    'master_recovery_device_registered': (
      '復旧でマスター端末を登録',
      'Master device registered through recovery',
    ),
  };

  static const authActions = <String, (String, String)>{
    'login': ('ログイン', 'Sign in'),
    'logout': ('ログアウト', 'Sign out'),
    'user_recovery_requested': ('パスワード復旧を要求', 'Password recovery requested'),
    'user_reauthenticate_requested': ('再認証を要求', 'Reauthentication requested'),
    'user_confirmation_requested': (
      '連絡先確認を要求',
      'Contact confirmation requested',
    ),
    'user_updated_password': ('パスワードを更新', 'Password updated'),
    'token_revoked': ('認証トークンを失効', 'Token revoked'),
    'token_refreshed': ('認証トークンを更新', 'Token refreshed'),
    'factor_in_progress': ('追加認証の登録を開始', 'MFA enrollment started'),
    'factor_unenrolled': ('追加認証を解除', 'MFA unenrolled'),
    'challenge_created': ('追加認証確認を開始', 'MFA challenge started'),
    'verification_attempted': ('追加認証の確認を試行', 'MFA verification attempted'),
    'factor_deleted': ('追加認証を削除', 'MFA factor deleted'),
    'factor_updated': ('追加認証を更新', 'MFA factor updated'),
    'mfa_code_login': ('追加認証でログイン', 'Sign in with MFA'),
    'identity_unlinked': ('連携認証を解除', 'Identity unlinked'),
  };

  String label(bool english) {
    final labels = actions[action] ?? authActions[action]!;
    return english ? labels.$2 : labels.$1;
  }

  static List<MasterSelfOperationAuditEvent> parse(
    Object? response, {
    bool auth = false,
  }) {
    if (response is! Map ||
        response.length != 6 ||
        response['version'] != 1 ||
        response['source_provenance'] !=
            (auth
                ? 'supabase_auth_database_audit'
                : 'server_master_operation_audit') ||
        response['scope'] != 'self_master_account' ||
        response['limit'] != 100 ||
        response['cutoff'] is! String ||
        DateTime.tryParse(response['cutoff'] as String) == null ||
        response['events'] is! List) {
      throw const FormatException('Operation records unavailable');
    }
    final cutoffText = response['cutoff'] as String;
    final cutoff = DateTime.parse(cutoffText);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$')
            .hasMatch(cutoffText) ||
        cutoff.toUtc().toIso8601String() != cutoffText) {
      throw const FormatException('Operation records unavailable');
    }
    final raw = response['events'] as List;
    if (raw.length > 100) {
      throw const FormatException('Operation records unavailable');
    }
    DateTime? previous;
    return List.unmodifiable(
      raw.map((item) {
        if (item is! Map ||
            item.length != 2 ||
            !(auth ? authActions : actions).containsKey(item['action']) ||
            item['at'] is! String) {
          throw const FormatException('Operation records unavailable');
        }
        final text = item['at'] as String;
        final at = DateTime.tryParse(text);
        if (!RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$')
                .hasMatch(text) ||
            at == null ||
            at.isAfter(cutoff) ||
            at.toUtc().toIso8601String() != text ||
            (previous != null && at.isAfter(previous!))) {
          throw const FormatException('Operation records unavailable');
        }
        previous = at;
        return MasterSelfOperationAuditEvent(
          action: item['action'] as String,
          at: at,
        );
      }),
    );
  }
}
