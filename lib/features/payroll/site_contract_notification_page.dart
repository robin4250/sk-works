import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import 'site_contract_review_page.dart';

/// Resolves a receipt owned by the current account; a notice is never authority.
class SiteContractNotificationPage extends StatefulWidget {
  const SiteContractNotificationPage({super.key, required this.notificationId});
  final String notificationId;

  @override
  State<SiteContractNotificationPage> createState() => _SiteContractNotificationPageState();
}

class _SiteContractNotificationPageState extends State<SiteContractNotificationPage> {
  String? _company;
  String? _item;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!SupabaseBackend.isInitialized || SupabaseBackend.client.auth.currentUser == null) {
      setState(() => _error = 'ログインが必要です。');
      return;
    }
    final actor = SupabaseBackend.client.auth.currentUser!.id;
    try {
      final value = await SupabaseBackend.client.rpc('get_site_contract_notification_target',
        params: {'p_notification': widget.notificationId});
      if (!mounted) {
        return;
      }
      if (SupabaseBackend.client.auth.currentUser?.id != actor || value is! Map ||
          value['company_id'] is! String || value['shared_item_id'] is! String ||
          (value['company_id'] as String).isEmpty || (value['shared_item_id'] as String).isEmpty) {
        throw const FormatException('通知の対象を確認できません。');
      }
      setState(() { _company = value['company_id'] as String; _item = value['shared_item_id'] as String; });
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(() => _error = const {'42883', 'PGRST202', '55000'}.contains(error.code)
          ? '契約通知はまだ利用できません。利用設定または提供開始を確認してください。'
          : 'この契約を開けません。会社・共有現場・利用権限を確認してください。');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = '通知の対象を確認できません。通知一覧から開き直してください。');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_company != null && _item != null) {
      return SiteContractReviewPage(sharedItemId: _item!, companyId: _company!);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('現場契約の通知')),
      body: Center(child: _error == null
        ? const CircularProgressIndicator()
        : Padding(padding: const EdgeInsets.all(24), child: Text(_error!))),
    );
  }
}
