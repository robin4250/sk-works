import 'package:flutter/material.dart';

/// Presentation only. The caller must derive [state] from a verified server
/// response; this widget cannot determine or change an Apple identity.
enum AppleRecoveryNoticeState { checking, held, unavailable, linked, retry }

class AppleRecoveryNotice extends StatelessWidget {
  const AppleRecoveryNotice({required this.state, super.key});

  final AppleRecoveryNoticeState state;

  @override
  Widget build(BuildContext context) {
    final (title, detail) = switch (state) {
      AppleRecoveryNoticeState.checking => (
          'Apple連携を確認中',
          '現在のログインを保ったまま、連携の状態を確認しています。',
        ),
      AppleRecoveryNoticeState.held => (
          'Apple連携を確認しています',
          '連携の結果を確認できるまで、Appleの追加は保留です。現在のログイン方法を引き続き使えます。',
        ),
      AppleRecoveryNoticeState.unavailable => (
          '連携の状態を確認できません',
          '通信状態を確認してから再度お試しください。現在のログイン方法を引き続き使えます。',
        ),
      AppleRecoveryNoticeState.linked => (
          'Apple連携を確認しました',
          '同じSKOアカウントへの連携が確認できました。',
        ),
      AppleRecoveryNoticeState.retry => (
          'Appleの本人確認からやり直せます',
          '新しくAppleの本人確認を行ってください。',
        ),
    };
    return Semantics(
      liveRegion: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(detail),
            ],
          ),
        ),
      ),
    );
  }
}
