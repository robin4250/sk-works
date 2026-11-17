import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_installation_invitation.dart';

const skoGooglePlayInternalTestingUrl =
    'https://play.google.com/apps/testing/com.skworks.sko';

class RegistrationCompletionActions extends StatelessWidget {
  const RegistrationCompletionActions({super.key, required this.onContinue});

  final VoidCallback onContinue;

  Future<void> _open(BuildContext context, String url) async {
    try {
      if (await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank')) return;
    } catch (_) {
      // The web session remains available if the store cannot be opened.
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('配布ページを開けませんでした。もう一度お試しください。')),
      );
    }
  }

  Future<void> _install(BuildContext context) async {
    final url = switch (Theme.of(context).platform) {
      TargetPlatform.iOS => skoTestFlightInvitationUrl,
      TargetPlatform.android => skoGooglePlayInternalTestingUrl,
      _ => null,
    };
    if (url != null) {
      await _open(context, url);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.phone_iphone_outlined),
              title: const Text('iPhone・iPad（TestFlight）'),
              onTap: () => _open(sheetContext, skoTestFlightInvitationUrl),
            ),
            ListTile(
              title: const Text('Android（Google Play 内部テスト）'),
              onTap: () => _open(sheetContext, skoGooglePlayInternalTestingUrl),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FilledButton(onPressed: onContinue, child: const Text('このままWebで使う')),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: () => _install(context),
        child: const Text('アプリを入れる'),
      ),
    ],
  );
}

class RegistrationCompletionPage extends StatelessWidget {
  const RegistrationCompletionPage({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('登録完了')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: ListView(
            padding: const EdgeInsets.all(20),
            shrinkWrap: true,
            children: [
              const Icon(Icons.check_circle_outline, size: 48),
              const SizedBox(height: 16),
              Text(
                '登録が完了しました',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 24),
              RegistrationCompletionActions(onContinue: onContinue),
            ],
          ),
        ),
      ),
    ),
  );
}
