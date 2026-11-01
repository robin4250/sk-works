import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/sites/site_order_original_review.dart';
import 'package:sk_works/features/sites/site_order_delivery_journal.dart';
import 'package:sk_works/features/sites/site_order_original_review_page.dart';
import 'package:sk_works/features/sites/site_order_outgoing_consent.dart';
import 'package:sk_works/features/sites/site_order_outgoing_execution.dart';
import 'package:sk_works/features/sites/site_order_outgoing_recovery_page.dart';
import 'package:sk_works/features/sites/site_order_outgoing_journal.dart';
import 'package:sk_works/features/sites/site_order_workflow_repository.dart';

String id(int n) => '96000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
final evidence = Map<String, dynamic>.from(
  jsonDecode(
    File('tool/canonical_renderer/synthetic-evidence.json').readAsStringSync(),
  ) as Map,
);
final company = (evidence['body'] as Map)['issuer_company_id'] as String;
final recipient =
    (evidence['body'] as Map)['counterparty_company_id'] as String;
final reference = SiteOrderConsentReference(
  prepare: SiteOrderPendingPrepare(
    siteId: id(1),
    documentId: id(2),
    localId: id(3),
    tradeId: id(4),
    requestId: id(5),
    sessionId: id(6),
  ),
  previewId: id(7),
  operationId: id(8),
  decisionId: id(9),
  bodyHash: 'a' * 64,
);
final pdf = Uint8List.fromList(
  ascii.encode('%PDF-1.7\nsynthetic original bytes\n%%EOF'),
);

class Api extends SiteOrderWorkflowApi {
  bool allowed = true,
      sameSession = true,
      retired = false,
      shared = false,
      unknown = false,
      saved = true,
      missingRate = false,
      missingAmount = false,
      consentNotObserved = false;
  int shares = 0, registers = 0, reads = 0, records = 0;
  @override
  bool get invalidated => retired;
  @override
  void requireCurrent() {
    if (retired) throw StateError('retired');
  }

  @override
  Future<bool> canMutateOutgoingReference(SiteOrderConsentReference r) async =>
      allowed && sameSession;
  Map<String, dynamic> raw() => {
    'contract_version': 1,
    'operation_id': id(8),
    'company_id': company,
    'site_id': id(1),
    'document_id': id(2),
    'local_document_id': id(3),
    'trade_company_id': id(4),
    'request_id': id(5),
    'preview_id': id(7),
    'decision_id': id(9),
    'job_id': id(10),
    'body_hash': 'a' * 64,
    'render_hash': evidence['render_hash'],
    'original_saved': saved,
    'original_receipt_id': saved ? id(11) : null,
    'pdf_sha256': saved ? sha256.convert(pdf).toString() : null,
    'pdf_byte_length': saved ? pdf.length : null,
    'sharing_state': shared ? 'recipient_stored' : 'not_observed',
    'package_id': shared ? id(12) : null,
    'recipient_company_id': recipient,
    'recipient_approval_state': 'not_checked',
    'device_push_confirmed': false,
    'read_only': true,
    'retry_automatically': false,
    'journal_clearable': false,
  };
  SiteOrderExecutionObservation observation() =>
      SiteOrderExecutionObservation.decode(
        raw(),
        reference,
        company,
        jobId: id(10),
        recipientCompanyId: recipient,
      );
  SiteOrderOriginalReview review() {
    final e = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(evidence)) as Map,
    );
    (e['body'] as Map)['transaction_id'] = id(2);
    if (missingAmount) (e['body'] as Map)['total_amount_yen'] = null;
    (e['body'] as Map)['form_fields'] = {
      'rows': [
        {
          'unit_price_yen': missingRate ? null : 100,
          'unit': '人日',
          'quantity': '1',
        },
      ],
    };
    return SiteOrderOriginalReview.decode(
      {
        'contract_version': 1,
        'purpose': 'persisted_original_review',
        'read_only': true,
        'same_session': sameSession,
        'status': raw(),
        'evidence': e,
      },
      reference,
      company,
      jobId: id(10),
      recipientCompanyId: recipient,
    );
  }

  @override
  Future<SiteOrderExecutionObservation> inspectOutgoingExecution(
    SiteOrderConsentReference r, {
    required String jobId,
    required String recipientCompanyId,
  }) async {
    requireCurrent();
    reads++;
    return observation();
  }

  @override
  Future<SiteOrderOriginalReview> reviewOutgoingOriginal(
    SiteOrderConsentReference r, {
    required String jobId,
    required String recipientCompanyId,
  }) async => review();
  @override
  Future<Uint8List> outgoingOriginalBytes(
    SiteOrderConsentReference r,
    SiteOrderOriginalReview review,
  ) async => pdf;
  @override
  Future<SiteOrderExecutionObservation> registerOutgoingOriginal(
    SiteOrderConsentReference r, {
    required String jobId,
    required String recipientCompanyId,
    required bool confirmed,
  }) async {
    registers++;
    if (unknown) throw const SiteOrderResultUnknown();
    saved = true;
    return observation();
  }

  @override
  Future<SiteOrderExecutionObservation> shareOutgoingOriginal(
    SiteOrderConsentReference r, {
    required String jobId,
    required String recipientCompanyId,
    required bool confirmed,
  }) async {
    expect(confirmed, true);
    shares++;
    if (unknown) throw const SiteOrderResultUnknown();
    shared = true;
    return observation();
  }

  @override
  Future<SiteOrderDeliveryRecord> recordOutgoingDelivery(
    SiteOrderConsentReference r, {
    required String jobId,
    required String recipientCompanyId,
  }) async {
    requireCurrent();
    records++;
    return SiteOrderDeliveryRecord.fromObservation(
      id(90),
      company,
      r,
      observation(),
    );
  }

  @override
  Future<List<SiteOrderPendingPrepare>> pendingOutgoing(String siteId) async =>
      [];
  @override
  Future<List<SiteOrderConsentReference>> pendingOutgoingConsents(
    String siteId,
  ) async => [reference];
  @override
  Future<SiteOrderConsentObservation> inspectOutgoingConsent(
    SiteOrderConsentReference r,
  ) async {
    final value = raw();
    return SiteOrderConsentObservation.decode(
      consentNotObserved
          ? {
              'contract_version': 1,
              'operation_state': 'decision_not_observed',
              'retry_automatically': false,
              'can_send': false,
              'journal_clearable': false,
              'read_only': true,
              'same_session': sameSession,
            }
          : {
              for (final key in [
                'contract_version',
                'preview_id',
                'operation_id',
                'job_id',
                'company_id',
                'site_id',
                'document_id',
                'local_document_id',
                'trade_company_id',
                'request_id',
                'body_hash',
                'render_hash',
              ])
                key: value[key],
              'operation_state': 'decision_job_prepared',
              'decision_request_id': id(9),
              'original_registered': false,
              'sent': false,
              'can_send': false,
              'journal_clearable': false,
              'retry_automatically': false,
            },
      reference,
      company,
    );
  }

  @override
  Future<SiteOrderExecutionObservation> resolveOutgoingExecutionForReview(
    SiteOrderConsentReference r, {
    required String jobId,
  }) async {
    reads++;
    expect(jobId, id(10));
    return observation();
  }

  void retire() {
    retired = true;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> pump(WidgetTester tester, Api api) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(
    MaterialApp(
      home: SiteOrderOriginalReviewPage(
        api: api,
        reference: reference,
        jobId: id(10),
        recipientCompanyId: recipient,
        previewBuilder: (_) => const Text('verified original PDF'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> finalDialog(WidgetTester tester) async {
  await tester.tap(find.byType(CheckboxListTile));
  await tester.pump();
  await tester.tap(find.text('共有内容を最終確認'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('missing total refuses final send and never substitutes zero', (tester) async {
    final api = Api()..missingAmount = true;
    await pump(tester, api);
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '共有内容を最終確認'));
    expect(button.onPressed, isNull);
    expect(find.text('発注金額（総額）：未設定（送信できません）'), findsOneWidget);
    expect(api.shares, 0);
  });

  test('original snapshot and bytes are both bound before display', () {
    final api = Api();
    final review = api.review();
    expect(review.verifyBytes(pdf), pdf);
    expect(
      () => review.verifyBytes(Uint8List.fromList([...pdf, 0])),
      throwsStateError,
    );
    final body = review.body;
    body['work_name'] = 'tampered';
    expect(review.body['work_name'], isNot('tampered'));
  });
  testWidgets(
    'OFF and new session keep original readable with persistent close, no mutation controls',
    (tester) async {
      final api = Api()
        ..allowed = false
        ..sameSession = false;
      await pump(tester, api);
      expect(find.text('verified original PDF'), findsOneWidget);
      expect(find.text('閉じる'), findsOneWidget);
      expect(find.text('共有内容を最終確認'), findsNothing);
      expect(find.text('確認済み内容の原本を保存'), findsNothing);
      expect(api.shares, 0);
    },
  );
  testWidgets(
    'checkbox and final dialog are separate; cancel retains original and never shares',
    (tester) async {
      final api = Api();
      await pump(tester, api);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await finalDialog(tester);
      expect(find.text('送信内容の最終確認'), findsOneWidget);
      final shown = tester.widget<Text>(find.byKey(const Key('site-order-send-question'))).data!;
      expect(shown, '${(evidence['body'] as Map)['work_name']}を${((evidence['body'] as Map)['counterparty'] as Map)['name']}へ100円で送りますが良いですか？');
      expect(find.textContaining('送る協力会社と金額があっていればこのまま送ります'), findsOneWidget);
      expect(api.shares, 0);
      await tester.tap(find.text('原本の確認に戻る'));
      await tester.pumpAndSettle();
      expect(api.shares, 0);
      await finalDialog(tester);
      await tester.tap(find.text('この会社・金額で送る'));
      await tester.pumpAndSettle();
      expect(api.shares, 1);
      expect(find.textContaining('相手の承認は未確認'), findsOneWidget);
      expect(find.text('共有内容を最終確認'), findsNothing);
    },
  );
  testWidgets('unknown share becomes status only without repeated mutation', (
    tester,
  ) async {
    final api = Api()..unknown = true;
    await pump(tester, api);
    await finalDialog(tester);
    await tester.tap(find.text('この会社・金額で送る'));
    await tester.pumpAndSettle();
    expect(api.shares, 1);
    expect(find.text('共有内容を最終確認'), findsNothing);
    await tester.tap(find.text('保存・共有結果を照会'));
    await tester.pumpAndSettle();
    expect(api.shares, 1);
    expect(find.text('共有内容を最終確認'), findsNothing);
  });
  testWidgets(
    'company retirement masks an open final dialog and prevents confirmation',
    (tester) async {
      final api = Api();
      await pump(tester, api);
      await finalDialog(tester);
      api.retire();
      await tester.pumpAndSettle();
      expect(find.text('この会社・金額で送る'), findsNothing);
      expect(find.text('表示を閉じました'), findsOneWidget);
      expect(find.textContaining('合成工事'), findsNothing);
      expect(api.shares, 0);
    },
  );
  testWidgets(
    'record sender delivery explicitly while OFF/new SID without claiming recipient approval',
    (tester) async {
      final api = Api()
        ..shared = true
        ..allowed = false
        ..sameSession = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push<SiteOrderDeliveryRecord>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SiteOrderOriginalReviewPage(
                      api: api,
                      reference: reference,
                      jobId: id(10),
                      recipientCompanyId: recipient,
                      previewBuilder: (_) =>
                          const Text('verified original PDF'),
                    ),
                  ),
                ),
                child: const Text('site home'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('site home'));
      await tester.pumpAndSettle();
      expect(api.records, 0);
      expect(find.textContaining('相手の承認は未確認'), findsOneWidget);
      await tester.tap(find.text('共有結果を保管して閉じる'));
      await tester.pumpAndSettle();
      expect(api.records, 1);
      expect(api.shares, 0);
      expect(api.registers, 0);
      expect(find.text('site home'), findsOneWidget);
    },
  );
  testWidgets(
    'recovery pins server purpose recipient and stays available OFF with new SID',
    (tester) async {
      final api = Api()
        ..allowed = false
        ..sameSession = false;
      await tester.pumpWidget(
        MaterialApp(
          home: SiteOrderOutgoingRecoveryPage(api: api, siteId: id(1)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('押印確認の保存結果を照会'));
      await tester.pumpAndSettle();
      expect(find.text('保存原本・共有状態を確認'), findsOneWidget);
      expect(api.reads, 1);
      expect(api.shares, 0);
      expect(api.registers, 0);
      expect(find.textContaining('共有はまだ'), findsNothing);
    },
  );
  testWidgets('unobserved consent never opens original or starts a mutation', (
    tester,
  ) async {
    final api = Api()..consentNotObserved = true;
    await tester.pumpWidget(
      MaterialApp(
        home: SiteOrderOutgoingRecoveryPage(api: api, siteId: id(1)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('押印確認の保存結果を照会'));
    await tester.pumpAndSettle();
    expect(find.text('保存原本・共有状態を確認'), findsNothing);
    expect(api.reads, 0);
    expect(api.shares, 0);
    expect(api.registers, 0);
  });
  for (final changed in ['api', 'reference', 'job', 'recipient']) {
    testWidgets(
      'reused page rejects changed $changed identity without adopting data',
      (tester) async {
        final api = Api();
        await pump(tester, api);
        final other = Api();
        final nextRef = SiteOrderConsentReference(
          prepare: reference.prepare,
          previewId: id(97),
          operationId: id(98),
          decisionId: id(99),
          bodyHash: 'b' * 64,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: SiteOrderOriginalReviewPage(
              api: changed == 'api' ? other : api,
              reference: changed == 'reference' ? nextRef : reference,
              jobId: changed == 'job' ? id(90) : id(10),
              recipientCompanyId: changed == 'recipient' ? id(91) : recipient,
              previewBuilder: (_) => const Text('must not show old PDF'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('must not show old PDF'), findsNothing);
        expect(find.textContaining('会社・ログイン状態を確認'), findsOneWidget);
        expect(find.text('共有内容を最終確認'), findsNothing);
        expect(other.reads, 0);
        expect(api.shares, 0);
        expect(other.shares, 0);
      },
    );
  }
  testWidgets('missing rate stays visibly unset and cannot open final share', (
    tester,
  ) async {
    final api = Api()..missingRate = true;
    await pump(tester, api);
    expect(find.textContaining('未設定'), findsOneWidget);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '共有内容を最終確認'),
    );
    expect(button.onPressed, isNull);
    expect(api.shares, 0);
  });
  testWidgets('unknown original registration cannot be repeated', (
    tester,
  ) async {
    final api = Api()
      ..saved = false
      ..unknown = true;
    await pump(tester, api);
    await tester.tap(find.text('確認済み内容の原本を保存'));
    await tester.pumpAndSettle();
    expect(api.registers, 1);
    expect(find.text('確認済み内容の原本を保存'), findsNothing);
    await tester.tap(find.text('保存・共有結果を照会'));
    await tester.pumpAndSettle();
    expect(api.registers, 1);
    expect(find.text('確認済み内容の原本を保存'), findsNothing);
  });
}
