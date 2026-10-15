import 'package:flutter/material.dart';

/// Only fields returned by the approved-friend workspace are displayed.
/// Employee records and private company profiles must not be fetched here.
class ChatFriendProfilePage extends StatelessWidget {
  const ChatFriendProfilePage({super.key, required this.friend});

  final Map<String, dynamic> friend;

  @override
  Widget build(BuildContext context) {
    final name = friend['display_name']?.toString().trim();
    final skoId = friend['sko_id']?.toString() ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('友達の情報')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const CircleAvatar(
            radius: 36,
            child: Icon(Icons.person_outline, size: 40),
          ),
          const SizedBox(height: 20),
          Text(
            name == null || name.isEmpty ? 'SKOユーザー' : name,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 20),
          ListTile(
            title: const Text('SKO ID'),
            subtitle: SelectableText(skoId),
          ),
          const ListTile(title: Text('所属会社'), subtitle: Text('未確認')),
          const Text('写真・所属会社の公開情報は現在取得できません。'),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: (friend['user_id']?.toString() ?? '').isEmpty
                ? null
                : () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('チャットを始める'),
          ),
        ),
      ),
    );
  }
}
