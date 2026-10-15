import 'package:flutter/material.dart';

/// Searches only the selected direct conversation already authorized by RLS.
class ChatDirectSearchPage extends StatefulWidget {
  const ChatDirectSearchPage({
    super.key,
    required this.messages,
    required this.peerName,
  });
  final List<Map<String, dynamic>> messages;
  final String peerName;
  @override
  State<ChatDirectSearchPage> createState() => _ChatDirectSearchPageState();
}

class _ChatDirectSearchPageState extends State<ChatDirectSearchPage> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final matches = query.isEmpty
        ? <Map<String, dynamic>>[]
        : widget.messages
              .where(
                (row) => (row['body']?.toString() ?? '').toLowerCase().contains(
                  query,
                ),
              )
              .toList();
    return Scaffold(
      appBar: AppBar(title: Text('${widget.peerName}のトーク検索')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'トーク内容を検索',
                hintText: '住所など',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text('この個別トークで読み込み済みのメッセージが対象です。'),
          ),
          if (query.isNotEmpty) Text('${matches.length}件'),
          Expanded(
            child: ListView.builder(
              itemCount: matches.length,
              itemBuilder: (context, index) {
                final row = matches[index];
                return ListTile(
                  title: Text(
                    row['body']?.toString() ?? '',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${row['sender_display_name'] ?? 'SKOユーザー'}　${row['sent_at'] ?? ''}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(context, row['id']?.toString()),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
