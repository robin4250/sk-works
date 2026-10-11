import 'package:flutter/material.dart';

/// Actions wrap below the photo label so deletion stays visible on a phone.
class CompanyDocumentPhotoRow extends StatelessWidget {
  const CompanyDocumentPhotoRow({
    super.key,
    required this.label,
    required this.subtitle,
    required this.onPreview,
    this.onMoveUp,
    this.onMoveDown,
    this.onReplace,
    this.onRemove,
  });

  final String label, subtitle;
  final VoidCallback onPreview;
  final VoidCallback? onMoveUp, onMoveDown, onReplace, onRemove;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.image_outlined),
        title: Text(label),
        subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: onPreview,
      ),
      Wrap(
        spacing: 4,
        children: [
          TextButton.icon(
            onPressed: onPreview,
            icon: const Icon(Icons.zoom_in),
            label: const Text('プレビュー'),
          ),
          TextButton.icon(
            onPressed: onMoveUp,
            icon: const Icon(Icons.arrow_upward),
            label: const Text('上へ'),
          ),
          TextButton.icon(
            onPressed: onMoveDown,
            icon: const Icon(Icons.arrow_downward),
            label: const Text('下へ'),
          ),
          TextButton.icon(
            onPressed: onReplace,
            icon: const Icon(Icons.swap_horiz),
            label: const Text('差し替え'),
          ),
          TextButton.icon(
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline),
            label: const Text('写真を削除'),
          ),
        ],
      ),
      const Divider(),
    ],
  );
}
