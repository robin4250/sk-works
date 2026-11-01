import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/sites/site_order_workflow_page.dart';
import 'package:sk_works/features/sites/site_order_workflow_repository.dart';
import 'package:sk_works/features/notifications/notification_target_policy.dart';

const package = '00000000-0000-0000-0000-000000000001';

class _Api extends SiteOrderWorkflowApi {
  bool expired = false, enabled = true, approved = false, stored = false;
  int approvals = 0, previews = 0, reconciliations = 0;
  bool pendingApproval = false, rejected = false;
  int refusals = 0, recoveries = 0;
  bool pendingReply = false;
  int globalHistoryReads = 0;
  final siteReads = <String>[];
  Completer<List<Map<String, dynamic>>>? siteHistoryHold;
  Completer<Map<String, dynamic>>? hold;
  @override
  bool get invalidated => expired;
  void retire() {
    expired = true;
    notifyListeners();
  }

  @override
  void requireCurrent() {
    if (expired) throw StateError('retired');
  }

  @override
  Future<void> verify() async => requireCurrent();
  @override
  Future<Map<String, dynamic>> detail(String id) async => {
    'package_id': id,
    'is_recipient': true,
    'can_write': enabled,
    'approved': approved,
    'rejected': rejected,
    'reply_recipient_stored': stored,
    'reply_original_registered': stored,
    'site_projection': {
      'name': '共有現場',
      'address': '確認用住所',
      'notes': '非公開金額99999',
    },
    'body': {
      'work_name': '確認現場',
      'period_start': '2026-10-01',
      'period_end': '2026-10-31',
    },
  };
  @override
  Future<bool> hasPendingApproval(String id) async => pendingApproval;
  @override
  Future<String?> reconcileApproval(String id) async {
    if (!pendingApproval) return null;
    reconciliations++;
    pendingApproval = false;
    return 'cancelled';
  }

  @override
  Future<List<Map<String, dynamic>>> history({
    String? before,
    String? beforeId,
  }) async { globalHistoryReads++; return []; }
  @override
  Future<List<Map<String, dynamic>>> historyForSite(String siteId, {
    String? before, String? beforeId,
  }) async {
    siteReads.add(siteId);
    return siteHistoryHold == null ? [{
      'package_id': package, 'created_at': '2026-10-31T00:00:00Z',
      'work_name': '保存された工事名称', 'period_start': '2026-10-01',
      'period_end': '2026-10-31', 'pdf_sha256': 'a' * 64,
    }] : siteHistoryHold!.future;
  }
  @override
  Future<List<Map<String, dynamic>>> targets(String id) async => [
    {'trade_id': package, 'name': '取引会社', 'connection_fingerprint': 'a' * 64},
  ];
  @override
  Future<Map<String, dynamic>> preview(
    String id,
    Map<String, dynamic> target,
  ) async {
    previews++;
    return {
      'preview_id': package,
      'body_hash': 'b' * 64,
      'own_seal': {'seal_hash': 'c' * 64},
    };
  }

  @override
  Future<Uint8List> renderReview(Map<String, dynamic> preview) async =>
      Uint8List.fromList([1, 2, 3]);
  @override
  Future<Map<String, dynamic>> approve(
    Map<String, dynamic> preview,
    String requestId,
  ) async {
    approvals++;
    if (hold != null) return hold!.future;
    approved = true;
    stored = true;
    return {
      'result': {'status': 'recipient_stored'},
    };
  }

  @override
  Future<Map<String, dynamic>> refuse(String id, String request) async {
    refusals++;
    rejected = true;
    return {'package_id': id, 'request_id': request, 'status': 'rejected'};
  }

  @override
  Future<bool> hasPendingReplyRecovery(String id) async => pendingReply;
  @override
  Future<Map<String, dynamic>> previewReplyRecovery(String id) async {
    previews++;
    return {'package_id': id, 'preview_id': package};
  }

  @override
  Future<Uint8List> renderReplyRecovery(Map<String, dynamic> preview) =>
      renderReview(preview);
  @override
  Future<Map<String, dynamic>> recoverReply(
    Map<String, dynamic> preview,
    String requestId,
  ) async {
    recoveries++;
    stored = true;
    return {
      'result': {'status': 'recipient_stored', 'package_id': package},
    };
  }

  @override
  Future<Map<String, dynamic>> resume(String id) async => {
    'result': {'status': 'recipient_stored'},
  };
  @override
  Future<Uint8List> original(String id, String kind) async =>
      Uint8List.fromList([1, 2, 3]);
  @override
  Future<Map<String, dynamic>> originalPayload(String id, String kind) async =>
      {};
}

Widget _app(_Api api) => MaterialApp(
  home: SiteOrderWorkflowPage(
    initialPackageId: package,
    api: api,
    previewBuilder: (_) =>
        const Center(child: Text('原本プレビュー', key: ValueKey('private-pdf'))),
  ),
);

void main() {
  testWidgets('site entry uses the exact scoped endpoint and preserves saved title and period', (tester) async {
    final api = _Api();
    await tester.pumpWidget(MaterialApp(home: SiteOrderWorkflowPage(
      api: api, siteId: package, siteName: '対象現場',
    )));
    await tester.pumpAndSettle();
    expect(api.siteReads, [package]);
    expect(api.globalHistoryReads, 0);
    expect(find.text('対象現場の注文履歴'), findsOneWidget);
    expect(find.text('保存された工事名称'), findsOneWidget);
    expect(find.text('2026-10-01 ～ 2026-10-31'), findsOneWidget);
    expect(api.approvals, 0);
  });
  testWidgets('a late former site response cannot populate a changed site', (tester) async {
    final api = _Api()..siteHistoryHold = Completer<List<Map<String, dynamic>>>();
    await tester.pumpWidget(MaterialApp(home: SiteOrderWorkflowPage(api: api, siteId: package)));
    await tester.pump();
    await tester.pumpWidget(MaterialApp(home: SiteOrderWorkflowPage(
      api: api, siteId: '00000000-0000-0000-0000-000000000002',
    )));
    api.siteHistoryHold!.complete([{'work_name': '以前の現場情報'}]);
    await tester.pumpAndSettle();
    expect(find.text('以前の現場情報'), findsNothing);
    expect(find.text('現場が変わりました。一覧から開き直してください。'), findsOneWidget);
    expect(api.siteReads, [package]);
  });
  test('package notification requires its exact saved UUID', () {
    expect(notificationTargetIsValid('site_order_package', null), isFalse);
    expect(notificationTargetIsValid('site_order_package', 'wrong'), isFalse);
    expect(notificationTargetIsValid('site_order_package', package), isTrue);
  });
  testWidgets(
    'recipient refusal requires a separate explicit confirmation and removes approval actions',
    (tester) async {
      final api = _Api();
      await tester.pumpWidget(_app(api));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('注文を辞退'));
      await tester.tap(find.text('注文を辞退'));
      await tester.pumpAndSettle();
      expect(api.refusals, 0);
      await tester.tap(find.text('戻る'));
      await tester.pumpAndSettle();
      expect(api.refusals, 0);
      await tester.tap(find.text('注文を辞退'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('辞退を送信'));
      await tester.pumpAndSettle();
      expect(api.refusals, 1);
      expect(find.text('辞退済み'), findsOneWidget);
      expect(find.text('内容と自社印を確認して承認'), findsNothing);
      expect(find.text('注文を辞退'), findsNothing);
      expect(api.approvals, 0);
    },
  );
  testWidgets(
    'a missing signed-in account shows a closed entry rather than an endless loader',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SiteOrderWorkflowPage(initialPackageId: package),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ログイン状態を確認してください。'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );
  testWidgets(
    'opening a notification/detail never approves; OFF retains original view',
    (tester) async {
      final api = _Api()..enabled = false;
      await tester.pumpWidget(_app(api));
      await tester.pumpAndSettle();
      expect(api.approvals, 0);
      expect(api.previews, 0);
      expect(find.text('内容と自社印を確認して承認'), findsNothing);
      await tester.tap(find.text('注文書を見る'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('private-pdf')), findsOneWidget);
      expect(find.byTooltip('閉じる'), findsOneWidget);
      await tester.tap(find.byTooltip('閉じる'));
      await tester.pumpAndSettle();
      expect(find.text('注文書を見る'), findsOneWidget);
      expect(api.approvals, 0);
    },
  );
  testWidgets(
    'reopened pending approval remains blocked until the explicit exact-operation barrier',
    (tester) async {
      final api = _Api()..pendingApproval = true;
      await tester.pumpWidget(_app(api));
      await tester.pumpAndSettle();
      expect(find.text('住所：確認用住所'), findsOneWidget);
      expect(find.textContaining('99999'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '内容と自社印を確認して承認'),
            )
            .onPressed,
        isNull,
      );
      expect(api.previews, 0);
      expect(api.reconciliations, 0);
      await tester.tap(find.text('保存状態を確認'));
      await tester.pumpAndSettle();
      expect(api.reconciliations, 1);
      expect(find.text('前の承認は受け付けられていません。内容を確認して承認し直せます。'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '内容と自社印を確認して承認'),
            )
            .onPressed,
        isNotNull,
      );
      expect(api.approvals, 0);
    },
  );
  testWidgets(
    'full review requires explicit checkbox before the single approval action',
    (tester) async {
      final api = _Api();
      await tester.pumpWidget(_app(api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('内容と自社印を確認して承認'));
      await tester.pumpAndSettle();
      expect(find.text('確認用・未承認'), findsOneWidget);
      final before = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '承認して請書を送る'),
      );
      expect(before.onPressed, isNull);
      expect(api.approvals, 0);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.text('承認して請書を送る'));
      await tester.pumpAndSettle();
      expect(api.approvals, 1);
      expect(find.text('承認しました。請書は相手の保管先に保存されました。'), findsOneWidget);
    },
  );
  testWidgets(
    'closing an in-flight approval preserves UNKNOWN and does not double-pop or retry',
    (tester) async {
      final api = _Api()..hold = Completer<Map<String, dynamic>>();
      await tester.pumpWidget(_app(api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('内容と自社印を確認して承認'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.text('承認して請書を送る'));
      await tester.pump();
      expect(api.approvals, 1);
      await tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .maybePop();
      await tester.pump();
      expect(find.text('請書・自社印の確認'), findsOneWidget);
      await tester.tap(find.byTooltip('閉じる'));
      await tester.pumpAndSettle();
      expect(find.text('保存結果を確認できません。再送せず「保存状態を確認」を押してください。'), findsOneWidget);
      await tester.tap(find.text('保存状態を確認'));
      await tester.pumpAndSettle();
      expect(find.text('結果はまだ確定できません。再送せず、保存状態を再確認してください。'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '内容と自社印を確認して承認'),
            )
            .onPressed,
        isNull,
      );
      expect(api.previews, 1);
      api.hold!.complete({
        'result': {'status': 'recipient_stored'},
      });
      await tester.pumpAndSettle();
      expect(find.text('注文・請書'), findsOneWidget);
      expect(api.approvals, 1);
      expect(find.text('承認しました。請書は相手の保管先に保存されました。'), findsNothing);
    },
  );
  testWidgets('scope retirement immediately removes a visible private PDF', (
    tester,
  ) async {
    final api = _Api();
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('注文書を見る'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('private-pdf')), findsOneWidget);
    api.retire();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('private-pdf')), findsNothing);
    expect(find.byTooltip('閉じる'), findsOneWidget);
    expect(api.approvals, 0);
  });
  testWidgets('reply restart requires preview and explicit seal confirmation', (
    tester,
  ) async {
    final api = _Api()..approved = true;
    await tester.pumpWidget(
      MaterialApp(
        home: SiteOrderPackagePage(
          api: api,
          packageId: package,
          previewBuilder: (_) => const Text('recovery PDF'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('内容と自社印を確認して返信を再開'));
    await tester.pumpAndSettle();
    expect(find.text('recovery PDF'), findsOneWidget);
    expect(api.recoveries, 0);
    final button = find.widgetWithText(FilledButton, '確認して返信を再開');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(api.recoveries, 1);
    expect(find.text('請書を相手先に保管済み'), findsOneWidget);
  });
}
