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
          Center(child: ChatFriendAvatar(friend: friend, radius: 36)),
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
          ListTile(
            title: const Text('所属会社'),
            subtitle: Text(friendCompanyLabel(friend)),
          ),
          if (friend['public_profile_loaded'] != true)
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

String friendCompanyLabel(Map<String, dynamic> friend) {
  if (friend['public_profile_loaded'] != true) return '未確認';
  final company = friend['company_name']?.toString().trim() ?? '';
  return company.isEmpty ? '登録なし' : company;
}

class ChatFriendAvatar extends StatelessWidget {
  const ChatFriendAvatar({super.key, required this.friend, this.radius = 20});
  final Map<String, dynamic> friend;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final url = friend['public_profile_loaded'] == true
        ? friend['avatar_url']?.toString() ?? ''
        : '';
    return CircleAvatar(
      radius: radius,
      child: url.isEmpty
          ? const Icon(Icons.person_outline)
          : ClipOval(
              child: Image.network(
                url,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.person_outline),
              ),
            ),
    );
  }
}
