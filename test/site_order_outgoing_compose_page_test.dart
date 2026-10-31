import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/sites/site_order_outgoing_compose_page.dart';
import 'package:sk_works/features/sites/site_order_outgoing_consent.dart';
import 'package:sk_works/features/sites/site_order_outgoing_consent_preview.dart';
import 'package:sk_works/features/sites/site_order_outgoing_entry_page.dart';
import 'package:sk_works/features/sites/site_order_outgoing_journal.dart';
import 'package:sk_works/features/sites/site_order_workflow_repository.dart';

String _id(int n) => '94000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
final _evidence = jsonDecode(
  File('tool/canonical_renderer/synthetic-evidence.json').readAsStringSync(),
) as Map;
SiteOrderReviewedInput _input(int n) {
  final pending = SiteOrderPendingPrepare(
    siteId: _id(1),
    documentId: _id(n),
    localId: _id(n + 1),
    tradeId: _id(2),
    requestId: _id(n + 2),
    sessionId: _id(3),
  );
  final body = Map<String, dynamic>.from(
    jsonDecode(jsonEncode(_evidence['body'])) as Map,
  )..['transaction_id'] = pending.documentId;
  return SiteOrderReviewedInput(pending, body, 'a' * 64);
}

class _Api extends SiteOrderWorkflowApi {
  bool retired = false,
      allowed = true,
      prepareUnknown = false,
      confirmUnknown = false,
      mismatch = false;
  String prepareState = 'prepared_review_required', retirement = 'retired';
  int prepares = 0,
      previews = 0,
      confirms = 0,
      inspections = 0,
      retirements = 0;
  SiteOrderReviewedInput? prepared;
  SiteOrderConsentReference? saved;
  Completer<void>? confirmBarrier;
  @override
  bool get invalidated => retired;
  @override
  void requireCurrent() {
    if (retired) throw StateError('retired');
  }

  @override
  Future<void> verify() async {
    requireCurrent();
  }

  @override
  Future<bool> canCreateOutgoing() async {
    requireCurrent();
    return allowed;
  }

  @override
  Future<List<SiteOrderPendingPrepare>> pendingOutgoing(String siteId) async =>
      const [];
  @override
  Future<List<SiteOrderConsentReference>> pendingOutgoingConsents(
    String siteId,
  ) async => saved == null ? const [] : [saved!];
  @override
  Future<void> prepareUnsignedOutgoing(
    SiteOrderPendingPrepare entry,
    Map<String, dynamic> body,
    String fingerprint,
  ) async {
    requireCurrent();
    prepares++;
    prepared = SiteOrderReviewedInput(entry, body, fingerprint);
    if (prepareUnknown) throw const SiteOrderResultUnknown();
  }

  @override
  Future<String> inspectUnsignedForReview(SiteOrderPendingPrepare entry) async {
    inspections++;
    requireCurrent();
    return prepareState;
  }

  @override
  Future<String> retireOutgoing(
    SiteOrderPendingPrepare entry, {
    required bool confirmed,
  }) async {
    expect(confirmed, true);
    retirements++;
    requireCurrent();
    return retirement;
  }

  @override
  Future<SiteOrderOutgoingConsentPreview> previewUnsignedOutgoing(
    SiteOrderPendingPrepare entry,
  ) async {
    requireCurrent();
    previews++;
    final body = prepared!.body;
    if (mismatch) body['notes'] = 'not the reviewed body';
    return SiteOrderOutgoingConsentPreview.fromServerEnvelope({
      'purpose': 'unsigned_review',
      'preview_only': true,
      'can_register': false,
      'can_send': false,
      'preview_id': _id(40),
      'operation_id': _id(41),
      'document_id': entry.documentId,
      'revision': 1,
      'body_hash': 'b' * 64,
      'source_hash': 'c' * 64,
      'seal_hash': (_evidence['seals'] as List).single['seal_hash'],
      'renderer_contract': 'sko-original-form-20261029-v1',
      'body': body,
      'own_seal': (_evidence['seals'] as List).single,
    });
  }

  @override
  Future<Uint8List> renderUnsignedOutgoing(
    SiteOrderOutgoingConsentPreview preview,
  ) async => Uint8List.fromList('%PDF-synthetic'.codeUnits);
  SiteOrderConsentObservation observation(SiteOrderConsentReference r) =>
      SiteOrderConsentObservation.decode(
        {
          'contract_version': 1,
          'operation_state': 'decision_job_prepared',
          'decision_request_id': r.decisionId,
          'preview_id': r.previewId,
          'operation_id': r.operationId,
          'job_id': _id(42),
          'company_id': (_evidence['body'] as Map)['issuer_company_id'],
          'site_id': r.prepare.siteId,
          'document_id': r.prepare.documentId,
          'local_document_id': r.prepare.localId,
          'trade_company_id': r.prepare.tradeId,
          'request_id': r.prepare.requestId,
          'body_hash': r.bodyHash,
          'render_hash': 'd' * 64,
          'original_registered': false,
          'sent': false,
          'can_send': false,
          'journal_clearable': false,
          'retry_automatically': false,
        },
        r,
        (_evidence['body'] as Map)['issuer_company_id'],
      );
  @override
  Future<SiteOrderConsentObservation> confirmUnsignedOutgoing(
    SiteOrderConsentReference reference, {
    required bool confirmed,
  }) async {
    expect(confirmed, true);
    confirms++;
    saved = reference;
    await confirmBarrier?.future;
    if (confirmUnknown) throw const SiteOrderResultUnknown();
    return observation(reference);
  }

  @override
  Future<SiteOrderConsentObservation> inspectOutgoingConsent(
    SiteOrderConsentReference reference,
  ) async {
    inspections++;
    return observation(reference);
  }

  void retireScope() {
    retired = true;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(
  WidgetTester tester,
  _Api api, {
  List<SiteOrderReviewedInput?>? seen,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(
    MaterialApp(
      home: SiteOrderOutgoingComposePage(
        api: api,
        siteId: _id(1),
        issueDate: '2026-10-31',
        previewBuilder: (_) => const Text('サーバーPDF'),
        inputBuilder: (old) {
          seen?.add(old);
          return Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('入力を閉じる'),
                  ),
                  FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, _input(old == null ? 10 : 60)),
                    child: const Text('記入して確定'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _inputDone(WidgetTester tester) async {
  await tester.tap(find.text('注文書を入力'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('記入して確定'));
  await tester.pumpAndSettle();
}

Future<void> _prepare(WidgetTester tester) async {
  await _inputDone(tester);
  await tester.tap(find.text('押印前の内容を確認'));
  await tester.pumpAndSettle();
}

Future<void> _agree(WidgetTester tester) async {
  await tester.tap(find.byType(CheckboxListTile));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'no consent before explicit review checkbox; confirmed job is not sent success',
    (tester) async {
      final api = _Api();
      await _pump(tester, api);
      await _prepare(tester);
      expect(api.prepares, 1);
      expect(api.confirms, 0);
      expect(find.text('サーバーPDF'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '押印内容を確定'))
            .onPressed,
        isNull,
      );
      await _agree(tester);
      await tester.tap(find.text('押印内容を確定'));
      await tester.pumpAndSettle();
      expect(api.confirms, 1);
      expect(find.textContaining('原本・共有の確認へ進めます'), findsOneWidget);
      expect(find.text('入力画面に戻る'), findsNothing);
      expect(find.text('共有送信'), findsNothing);
      await tester.tap(find.text('保存結果を照会'));
      await tester.pumpAndSettle();
      expect(api.confirms, 1);
    },
  );
  testWidgets(
    'prepare ACK unknown reads same identity before fresh preview and never prepares twice',
    (tester) async {
      final api = _Api()..prepareUnknown = true;
      await _pump(tester, api);
      await _prepare(tester);
      expect(api.prepares, 1);
      expect(api.previews, 0);
      await tester.tap(find.text('準備結果を照会'));
      await tester.pumpAndSettle();
      expect(api.prepares, 1);
      expect(api.previews, 1);
      expect(api.confirms, 0);
    },
  );
  testWidgets('not observed and advanced never become a reviewable order', (
    tester,
  ) async {
    for (final state in ['not_observed', 'advanced', 'changed']) {
      final api = _Api()
        ..prepareUnknown = true
        ..prepareState = state;
      await _pump(tester, api);
      await _prepare(tester);
      await tester.tap(find.text('準備結果を照会'));
      await tester.pumpAndSettle();
      expect(api.previews, 0);
      expect(api.confirms, 0);
      expect(find.byType(CheckboxListTile), findsNothing);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();
    }
  });
  testWidgets('mismatched server body cannot reach consent', (tester) async {
    final api = _Api()..mismatch = true;
    await _pump(tester, api);
    await _prepare(tester);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(api.confirms, 0);
  });
  testWidgets(
    'return to input requires verified retirement and passes retained RAM input',
    (tester) async {
      final api = _Api(), seen = <SiteOrderReviewedInput?>[];
      await _pump(tester, api, seen: seen);
      await _prepare(tester);
      await tester.tap(find.text('入力画面に戻る'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('準備を停止して入力へ'));
      await tester.pumpAndSettle();
      expect(api.retirements, 1);
      expect(seen.length, 2);
      expect(seen.last!.body, api.prepared!.body);
      await tester.tap(find.text('記入して確定'));
      await tester.pumpAndSettle();
      expect(api.prepares, 1);
      expect(api.confirms, 0);
    },
  );
  testWidgets('failed retirement cannot enable editing or stale consent', (
    tester,
  ) async {
    final api = _Api()..retirement = 'advanced';
    await _pump(tester, api);
    await _prepare(tester);
    await tester.tap(find.text('入力画面に戻る'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('準備を停止して入力へ'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.text('記入して確定'), findsNothing);
    expect(api.confirms, 0);
  });
  testWidgets(
    'OFF before consent prevents mutation while recovery stays available',
    (tester) async {
      final api = _Api();
      await _pump(tester, api);
      await _prepare(tester);
      await _agree(tester);
      api.allowed = false;
      await tester.tap(find.text('押印内容を確定'));
      await tester.pumpAndSettle();
      expect(api.confirms, 0);
      expect(find.text('確認待ちの注文'), findsOneWidget);
    },
  );
  testWidgets(
    'unknown consent and scope retirement mask financial preview and prevent repeat writes',
    (tester) async {
      final api = _Api()..confirmUnknown = true;
      await _pump(tester, api);
      await _prepare(tester);
      await _agree(tester);
      await tester.tap(find.text('押印内容を確定'));
      await tester.pumpAndSettle();
      expect(api.confirms, 1);
      expect(find.text('押印内容を確定'), findsNothing);
      expect(find.text('入力画面に戻る'), findsNothing);
      api.retireScope();
      await tester.pumpAndSettle();
      expect(find.text('サーバーPDF'), findsNothing);
      expect(api.confirms, 1);
    },
  );
  testWidgets('retired input cancellation never enables old-ID preparation', (
    tester,
  ) async {
    final api = _Api();
    await _pump(tester, api);
    await _prepare(tester);
    final old = api.prepared!.pending;
    await tester.tap(find.text('入力画面に戻る'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('準備を停止して入力へ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('入力を閉じる'));
    await tester.pumpAndSettle();
    expect(find.text('押印前の内容を確認'), findsNothing);
    expect(api.prepares, 1);
    await tester.tap(find.text('入力画面に戻る'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('記入して確定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('押印前の内容を確認'));
    await tester.pumpAndSettle();
    expect(api.prepares, 2);
    expect(api.prepared!.pending.documentId, isNot(old.documentId));
    expect(api.prepared!.pending.requestId, isNot(old.requestId));
  });
}
