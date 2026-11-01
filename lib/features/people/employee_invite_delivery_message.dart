/// The existing general installation guide remains available even when a
/// TestFlight participation URL is not configured. This does not prove that
/// the recipient installed the app or that an invitation was delivered.
const employeeInviteInstallationGuide =
    'https://skojapan.com/install/employee/';

/// Syntax validation only: it does not contact Apple or assert build access.
/// Keep the code case exactly as configured. URL-shaped examples such as
/// `/...`, `<code>` or `YOUR_CODE` cannot pass this supported token grammar.
String? employeeInviteTestFlightUrl(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  final uri = Uri.tryParse(text);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != 'testflight.apple.com' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.pathSegments.length != 2 ||
      uri.pathSegments.first != 'join') {
    return null;
  }
  final code = uri.pathSegments.last;
  if (!RegExp(r'^[A-Za-z0-9]+$').hasMatch(code) ||
      text != 'https://testflight.apple.com/join/$code') {
    return null;
  }
  return text;
}

String employeeInviteDeliveryMessage({
  required String name,
  required String phone,
  required String temporaryPassword,
  String? testFlightUrl,
  bool english = false,
}) {
  final testFlight = employeeInviteTestFlightUrl(testFlightUrl);
  return [
    english
        ? 'An SKO employee registration has been created.'
        : 'SKOの従業員登録が作成されました。',
    if (name.trim().isNotEmpty)
      english ? 'Name: ${name.trim()}' : '氏名: ${name.trim()}',
    if (testFlight != null)
      'TestFlight: $testFlight'
    else
      english
          ? 'TestFlight participation URL is not configured or is unavailable. Contact your administrator.'
          : 'TestFlight参加URLは未設定、または利用できない形式です。管理者に確認してください。',
    english ? 'Installation and getting started:' : 'インストール・利用開始案内:',
    employeeInviteInstallationGuide,
    english ? 'Phone: $phone' : '電話番号: $phone',
    english
        ? 'Temporary password: $temporaryPassword'
        : '初期パスワード: $temporaryPassword',
    english
        ? 'If SKO is already installed, sign in with the temporary password. Set your permanent password after the first sign-in.'
        : 'SKOをインストール済みの場合は、初期パスワードでログインしてください。初回ログイン後に本パスワードを設定します。',
  ].join('\n');
}
