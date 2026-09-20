String friendlyAuthErrorMessage(String raw) {
  final message = raw.trim();
  final lower = message.toLowerCase();

  if (lower.contains('rate limit') ||
      lower.contains('too many requests') ||
      lower.contains('over request rate limit')) {
    return 'SMSの送信回数が多いため、少し待ってから再度お試しください。';
  }

  if ((lower.contains('otp') || lower.contains('token')) &&
      (lower.contains('invalid') ||
       lower.contains('expired') ||
       lower.contains('not found'))) {
    return '承認コードが無効または期限切れです。SMSを再送して新しいコードを入力してください。';
  }

  if (lower.contains('sms') &&
      (lower.contains('provider') ||
       lower.contains('not configured') ||
       lower.contains('configuration'))) {
    return 'SMS送信設定を確認できません。管理者にSMSプロバイダ設定の確認を依頼してください。';
  }

  if (lower.contains('user already registered') ||
      lower.contains('already been registered')) {
    return 'この携帯電話番号はすでに登録されています。ログインをお試しください。';
  }

  if (lower.contains('invalid login credentials')) {
    return '携帯電話番号またはパスワードを確認してください。';
  }

  return message.isEmpty ? '認証処理に失敗しました。' : message;
}
