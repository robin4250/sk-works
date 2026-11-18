import 'package:flutter/material.dart';

import '../chat/chat_friends_page.dart';
import '../profile/personal_details_page.dart';

const personalHomePreviewEnabled = bool.fromEnvironment(
  'SKO_PERSONAL_HOME_PREVIEW_ENABLED',
);

class PersonalHomePage extends StatelessWidget {
  const PersonalHomePage({
    super.key,
    required this.onCompanySetup,
    required this.onSignOut,
    this.workPassOnly = false,
  });

  final VoidCallback onCompanySetup;
  final Future<void> Function() onSignOut;
  final bool workPassOnly;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ワークパス'),
        actions: [TextButton(onPressed: onSignOut, child: const Text('ログアウト'))],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('個人ホーム', style: Theme.of(context).textTheme.headlineSmall),
                const Text('会社の所属なし'),
                const SizedBox(height: 16),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: const Text('個人情報'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => const PersonalDetailsPage(),
                          ),
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.people_outline),
                        title: const Text('友達'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => const ChatFriendsPage(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!workPassOnly) ...[
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: onCompanySetup,
                    child: const Text('会社を登録する'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
