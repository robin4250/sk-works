const skoTestFlightInvitationUrl = 'https://testflight.apple.com/join/1rNHSpdC';

/// App installation is separate from the registration or company-link action.
/// Called only after the caller has prepared an authorized invitation.
String appendSkoInstallationInvitation(
  String message, {
  required String guideUrl,
  bool english = false,
  bool includeTestFlight = true,
}) {
  final parts = <String>[message];
  if (includeTestFlight && !message.contains(skoTestFlightInvitationUrl)) {
    parts.add('iPhone / iPad TestFlight:\n$skoTestFlightInvitationUrl');
  }
  if (guideUrl.isNotEmpty && !message.contains(guideUrl)) {
    parts.add(
      '${english ? 'Installation and getting started' : 'インストール・利用開始案内'}:\n$guideUrl',
    );
  }
  parts.add(
    english
        ? 'Installing the app does not complete registration or company linking. Follow the guide for your invitation. For other devices, check the guide for availability.'
        : 'インストールだけでは登録・会社連携は完了しません。招待の種類に合った案内に沿って進めてください。その他の端末の対応状況は案内ページで確認してください。',
  );
  return parts.join('\n\n');
}
