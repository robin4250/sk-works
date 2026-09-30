import 'package:flutter/material.dart';

import 'app_update_check_service.dart';

class AppUpdateNoticeDialog extends StatelessWidget {
  const AppUpdateNoticeDialog({
    super.key,
    required this.notice,
    required this.onOpenStore,
    this.onLater,
  });

  final AppUpdateNoticeData notice;
  final VoidCallback onOpenStore;
  final VoidCallback? onLater;

  @override
  Widget build(BuildContext context) {
    final required = notice.isRequired;
    return PopScope(
      canPop: !required,
      child: AlertDialog(
        title: Text(
          required ? 'アプリの更新が必要です' : '新しいバージョンがあります',
        ),
        content: Text(
          '現在: ${notice.currentVersion}\n'
          '最新: ${notice.latestVersion}\n\n'
          '${required ? '安全にSKOを利用するため、App Storeから更新してください。' : 'App Storeから最新版へ更新できます。'}',
        ),
        actions: [
          if (!required)
            TextButton(
              onPressed: onLater ?? () => Navigator.of(context).pop(),
              child: const Text('あとで'),
            ),
          FilledButton(
            onPressed: onOpenStore,
            child: const Text('App Storeで更新'),
          ),
        ],
      ),
    );
  }
}
