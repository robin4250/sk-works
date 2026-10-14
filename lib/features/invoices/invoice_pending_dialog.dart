import 'package:flutter/material.dart';

enum InvoicePendingAction { review, reload }

class InvoicePendingDialog extends StatelessWidget {
  const InvoicePendingDialog({
    super.key,
    required this.english,
    required this.routeSourcePending,
    required this.canReviewQuantity,
    required this.quantityCheckFailed,
  });
  final bool english;
  final bool routeSourcePending;
  final bool canReviewQuantity;
  final bool quantityCheckFailed;

  @override
  Widget build(BuildContext context) {
    final String explanation;
    if (routeSourcePending) {
      explanation = english
          ? 'The signed checkout report, actual visited customers or registered rates are not ready. Check the checkout report and billing settings, then reload.'
          : '退勤日報の署名・実際の訪問先・登録単価などを確認できていません。退勤日報と請求設定を確認して再読み込みしてください。';
    } else if (quantityCheckFailed) {
      explanation = english
          ? 'Could not retrieve the quantity approval status. Check your connection and account access, then reload. No approval has been performed.'
          : '請求数量の承認状況を取得できませんでした。通信・ログイン・権限を確認して再読み込みしてください。承認処理は行われていません。';
    } else if (canReviewQuantity) {
      explanation = english
          ? 'Route billing quantity is awaiting approval. Confirm the billing site, quantity and unit price before approving.'
          : 'ルート請求数量の承認待ちです。請求に使用する現場・数量・単価を確認して承認してください。';
    } else {
      explanation = english
          ? 'The saved invoice remains pending, but there are no quantity requests this account can review. Approval may already be complete while recalculation has not reached the invoice. Reload first. If this persists, the billing server update or an authorized approver must be checked.'
          : '保存済みの請求書は未確定ですが、このアカウントで確認できる数量承認待ちはありません。承認済みでも、再計算が請求書に反映されていない場合があります。まず再読み込みしてください。変わらない場合は、請求連携のサーバー更新状況と承認権限の確認が必要です。';
    }
    return AlertDialog(
      title: Text(english ? 'Invoice amount pending' : '請求額は未確定です'),
      content: SingleChildScrollView(child: Text(
        '$explanation\n\n${english ? 'This is not a confirmed zero amount.' : '0円で確定した請求書ではありません。'}',
      )),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(english ? 'Close' : '閉じる'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, InvoicePendingAction.reload),
          child: Text(english ? 'Reload' : '再読み込み'),
        ),
        if (canReviewQuantity && !routeSourcePending && !quantityCheckFailed)
          FilledButton(
            onPressed: () => Navigator.pop(context, InvoicePendingAction.review),
            child: Text(english ? 'Review Quantity' : '請求数量を確認'),
          ),
      ],
    );
  }
}
