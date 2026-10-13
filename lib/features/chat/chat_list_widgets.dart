import 'package:flutter/material.dart';

/// Count conversations once, even when a group appears in multiple filters.
int chatUnreadTotal(Iterable<Map<String, dynamic>> groups, Map<String, int> counts) {
  final ids = groups.map((g) => g['id']?.toString()).whereType<String>().toSet();
  return ids.fold(0, (sum, id) => sum + ((counts[id] ?? 0) > 0 ? counts[id]! : 0));
}

class ChatUnreadBadge extends StatelessWidget {
  const ChatUnreadBadge({super.key, required this.count});
  final int count;
  @override
  Widget build(BuildContext context) => count <= 0 ? const SizedBox.shrink() : Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
    decoration: BoxDecoration(color: Colors.red.shade700, borderRadius: BorderRadius.circular(20)),
    child: Text('$count', textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
  );
}

class ChatConversationTile extends StatelessWidget {
  const ChatConversationTile({super.key, required this.name, required this.preview,
    required this.time, required this.unreadCount, required this.icon, this.avatarUrl,
    required this.onTap});
  final String name, preview, time;
  final int unreadCount;
  final IconData icon;
  final String? avatarUrl;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(radius: 24, child: avatarUrl == null || avatarUrl!.isEmpty
          ? Icon(icon) : ClipOval(child: Image.network(avatarUrl!, width: 48, height: 48,
            fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(icon)))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 5),
          Text(preview, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ])),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(time, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          ChatUnreadBadge(count: unreadCount),
        ]),
      ]),
    ),
  );
}
