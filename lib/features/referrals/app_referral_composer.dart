import 'app_installation_invitation.dart';

enum AppReferralComposeOutcome {
  recorded,
  busy,
  prepareFailed,
  launchFailed,
  recordFailed,
  actorChanged,
}

/// A prepared invitation is reused after a local failure. This tracks opening
/// the SMS composer, never delivery or registration, and stores no credentials.
class AppReferralComposer {
  AppReferralComposer({
    required this.actorId,
    required this.prepare,
    required this.openComposer,
    required this.recordOpened,
  });

  final String? Function() actorId;
  final Future<Map<String, dynamic>> Function(
    String name,
    String phone,
    bool friendInvite,
  )
  prepare;
  final Future<bool> Function(Uri uri) openComposer;
  final Future<void> Function(String id) recordOpened;

  bool _busy = false;
  (String, String, String, bool, String)? _key;
  String? _invitationId;
  Uri? _uri;
  bool _opened = false;

  bool get needsRecordRetry => _opened && _invitationId != null;

  void _clear() {
    _key = null;
    _invitationId = null;
    _uri = null;
    _opened = false;
  }

  Future<AppReferralComposeOutcome> send({
    required String name,
    required String phone,
    required bool friendInvite,
    String distributionKey = '',
    String guideUrl = '',
  }) async {
    if (_busy) {
      return AppReferralComposeOutcome.busy;
    }
    final actor = actorId();
    if (actor == null) {
      _clear();
      return AppReferralComposeOutcome.actorChanged;
    }
    _busy = true;
    try {
      var canonicalPhone = phone.replaceAll(RegExp(r'[\s()\-]'), '');
      if (canonicalPhone.startsWith('+81')) {
        canonicalPhone = '0${canonicalPhone.substring(3)}';
      }
      final key = (
        actor,
        name.trim(),
        canonicalPhone,
        friendInvite,
        '$distributionKey|$guideUrl',
      );
      if (_key != key) {
        _clear();
      }
      if (_invitationId == null) {
        Map<String, dynamic> result;
        try {
          result = await prepare(name.trim(), phone.trim(), friendInvite);
        } catch (_) {
          return AppReferralComposeOutcome.prepareFailed;
        }
        if (actorId() != actor) {
          _clear();
          return AppReferralComposeOutcome.actorChanged;
        }
        final id = result['id'];
        final recipient = result['phone'];
        final message = result['message'];
        if (id is! String ||
            id.isEmpty ||
            recipient is! String ||
            recipient.isEmpty ||
            message is! String ||
            message.isEmpty) {
          return AppReferralComposeOutcome.prepareFailed;
        }
        _key = key;
        _invitationId = id;
        final body = guideUrl.isNotEmpty
            ? appendSkoInstallationInvitation(
                message,
                guideUrl: guideUrl,
                includeTestFlight: distributionKey.split(':').first == 'testflight',
              )
            : message;
        _uri = Uri(
          scheme: 'sms',
          path: recipient,
          queryParameters: {'body': body},
        );
      }
      if (!_opened) {
        try {
          if (!await openComposer(_uri!)) {
            return AppReferralComposeOutcome.launchFailed;
          }
          _opened = true;
        } catch (_) {
          return AppReferralComposeOutcome.launchFailed;
        }
      }
      if (actorId() != actor) {
        _clear();
        return AppReferralComposeOutcome.actorChanged;
      }
      try {
        await recordOpened(_invitationId!);
      } catch (_) {
        return AppReferralComposeOutcome.recordFailed;
      }
      _clear();
      return AppReferralComposeOutcome.recorded;
    } finally {
      _busy = false;
    }
  }
}
