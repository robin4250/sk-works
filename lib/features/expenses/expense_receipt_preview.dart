import 'package:flutter/material.dart';
import '../../data/supabase_backend.dart';

class ExpenseReceiptPreview extends StatefulWidget {
  const ExpenseReceiptPreview({super.key, required this.objectPath});
  final String objectPath;
  @override
  State<ExpenseReceiptPreview> createState() => _ExpenseReceiptPreviewState();
}
class _ExpenseReceiptPreviewState extends State<ExpenseReceiptPreview> {
  late final Future<String> _url = SupabaseBackend.client.storage.from('expense-receipts').createSignedUrl(widget.objectPath, 300);
  @override
  Widget build(BuildContext context) => FutureBuilder<String>(future: _url, builder: (context, snapshot) {
    if (snapshot.hasError) return const Text('領収書の写真を取得できません。開き直して確認してください。');
    if (!snapshot.hasData) return const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator());
    return Image.network(snapshot.data!, height: 220, fit: BoxFit.contain,
      errorBuilder: (_, error, stack) => const Text('領収書の写真を表示できません。'));
  });
}
