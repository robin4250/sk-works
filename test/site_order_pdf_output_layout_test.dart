import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/sites/site_order_workflow_pdf_page.dart';
import 'package:sk_works/features/sites/site_order_workflow_repository.dart';
import 'package:sk_works/features/shared/trade_document_output_layout.dart';

class _Api extends SiteOrderWorkflowApi {
  bool retired = false;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
  @override
  bool get invalidated => retired;
  @override
  void requireCurrent() {
    if (retired) throw StateError('retired');
  }

  @override
  Future<void> verify() async => requireCurrent();
  @override
  Future<Uint8List> original(String id, String kind) async =>
      Uint8List.fromList([1]);
  @override
  Future<Map<String, dynamic>> originalPayload(String id, String kind) async =>
      {'frozen': true};
  void retire() {
    retired = true;
    notifyListeners();
  }
}

void main() {
  const channel = MethodChannel('net.nfet.printing');
  testWidgets(
    'selected A3 preview and shared PDF use identical derived bytes; returning to A4 restores original',
    (tester) async {
      Uint8List? shared;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'sharePdf') {
              shared = call.arguments['doc'] as Uint8List;
              return true;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final api = _Api();
      await tester.pumpWidget(
        MaterialApp(
          home: SiteOrderWorkflowPdfPage(
            api: api,
            packageId: 'package',
            title: '注文書',
            previewBuilder: (bytes) => Text('preview-${bytes.single}'),
            outputBuilder: (payload, layout, original) async {
              expect(payload['frozen'], true);
              expect(original.single, 1);
              expect(layout, TradeDocumentOutputLayout.a3Landscape);
              return Uint8List.fromList([3]);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('preview-1'), findsOneWidget);
      await tester.tap(
        find.byType(DropdownButtonFormField<TradeDocumentOutputLayout>),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('A3横・見開き1枚（2ページを左右に配置）').last);
      await tester.pumpAndSettle();
      expect(find.text('preview-3'), findsOneWidget);
      await tester.tap(find.byTooltip('保存・共有'));
      await tester.pumpAndSettle();
      expect(shared, orderedEquals([3]));
      await tester.tap(
        find.byType(DropdownButtonFormField<TradeDocumentOutputLayout>),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('A4縦・2ページ（帳票＋契約条項）').last);
      await tester.pumpAndSettle();
      expect(find.text('preview-1'), findsOneWidget);
    },
  );
  testWidgets(
    'failed conversion restores A4 selector, preview and shared bytes',
    (tester) async {
      Uint8List? shared;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'sharePdf') {
              shared = call.arguments['doc'] as Uint8List;
              return true;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SiteOrderWorkflowPdfPage(
            api: _Api(),
            packageId: 'package',
            title: '注文書',
            previewBuilder: (bytes) => Text('preview-${bytes.single}'),
            outputBuilder: (_, __, ___) async => throw StateError('failed'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byType(DropdownButtonFormField<TradeDocumentOutputLayout>),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('A3横・見開き1枚（2ページを左右に配置）').last);
      await tester.pumpAndSettle();
      final state = tester.state<FormFieldState<TradeDocumentOutputLayout>>(
        find.byType(DropdownButtonFormField<TradeDocumentOutputLayout>),
      );
      expect(state.value, TradeDocumentOutputLayout.a4TwoPages);
      expect(find.text('preview-1'), findsOneWidget);
      await tester.tap(find.byTooltip('保存・共有'));
      await tester.pumpAndSettle();
      expect(shared, orderedEquals([1]));
    },
  );
  testWidgets('scope revocation discards an in-flight derivative', (
    tester,
  ) async {
    final api = _Api();
    final pending = Completer<Uint8List>();
    await tester.pumpWidget(
      MaterialApp(
        home: SiteOrderWorkflowPdfPage(
          api: api,
          packageId: 'package',
          title: '請書',
          previewBuilder: (bytes) => Text('private-${bytes.single}'),
          outputBuilder: (_, __, ___) => pending.future,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byType(DropdownButtonFormField<TradeDocumentOutputLayout>),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('A3横・見開き1枚（2ページを左右に配置）').last);
    await tester.pump();
    api.retire();
    await tester.pump();
    pending.complete(Uint8List.fromList([3]));
    await tester.pumpAndSettle();
    expect(find.text('private-1'), findsNothing);
    expect(find.text('private-3'), findsNothing);
    expect(find.textContaining('ログイン・会社の状態が変わりました'), findsOneWidget);
  });
}
