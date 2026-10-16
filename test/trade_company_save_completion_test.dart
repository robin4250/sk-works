import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/companies/trade_company_page.dart';
import 'package:sk_works/features/companies/trade_company_repository.dart';

class FakeDirectory implements TradeCompanyRepository {
  final List<TradeCompanyRecord> items = [];
  Completer<String> response = Completer<String>();
  int saves = 0;
  String? lastId;
  String? lastName;
  @override
  Future<List<TradeCompanyRecord>> loadAll() async => List.of(items);
  @override
  Future<Map<String, dynamic>> linkWorkspace() async => {'enabled': false};
  @override
  Future<String> saveCompany({String? id, required String name, required String tradeRole,
    String? postalCode, String? address, String? phone, String? email,
    String? corporateNumber, String? notes, String? representativeName,
    String? representativePhone}) async {
    saves++;
    lastId = id;
    lastName = name;
    final saved = await response.future;
    items.removeWhere((item) => item.id == saved);
    items.add(TradeCompanyRecord.fromJson({'id': saved, 'name': name, 'trade_role': tradeRole}));
    return saved;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<void> open(WidgetTester tester, FakeDirectory repo, TradeCompanyPageMode mode) async {
    await tester.pumpWidget(MaterialApp(home: TradeCompanyPage(mode: mode, repository: repo)));
    await tester.pumpAndSettle();
  }
  Future<void> register(WidgetTester tester) async {
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Saved Company');
    await tester.tap(find.widgetWithText(FilledButton, '登録'));
    await tester.pump();
  }
  for (final mode in TradeCompanyPageMode.values) {
    testWidgets('registration confirms only after save and suppresses duplicate taps: $mode', (tester) async {
      final repo = FakeDirectory();
      await open(tester, repo, mode);
      await register(tester);
      expect(repo.saves, 1);
      expect(find.text('登録しました'), findsNothing);
      expect(find.text('登録中…'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField).first).enabled, isFalse);
      final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '登録中…'));
      expect(button.onPressed, isNull);
      final cancel = tester.widget<TextButton>(find.widgetWithText(TextButton, 'キャンセル'));
      expect(cancel.onPressed, isNull);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('登録中…'), findsOneWidget);
      repo.response.complete('saved');
      await tester.pumpAndSettle();
      expect(find.text('登録しました'), findsOneWidget);
      expect(repo.saves, 1);
      await tester.tap(find.text('一覧で確認'));
      await tester.pumpAndSettle();
      expect(find.text('Saved Company'), findsOneWidget);
    });
  }
  testWidgets('failure preserves input for retry and leaves cancellation available', (tester) async {
    final repo = FakeDirectory();
    await open(tester, repo, TradeCompanyPageMode.customer);
    await register(tester);
    repo.response.completeError(StateError('synthetic save rejected'));
    await tester.pumpAndSettle();
    expect(find.text('登録しました'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, 'Saved Company');
    expect(find.byKey(const ValueKey('company-save-error')), findsOneWidget);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'キャンセル')).onPressed, isNotNull);
    repo.response = Completer<String>();
    await tester.tap(find.widgetWithText(FilledButton, '登録'));
    await tester.pump();
    expect(repo.saves, 2);
    repo.response.complete('saved');
    await tester.pumpAndSettle();
    expect(find.text('登録しました'), findsOneWidget);
  });
  testWidgets('editing preserves the record ID and reports update only after save', (tester) async {
    final repo = FakeDirectory();
    repo.items.add(TradeCompanyRecord.fromJson({'id': 'existing', 'name': 'Old Company', 'trade_role': 'customer'}));
    await open(tester, repo, TradeCompanyPageMode.customer);
    await tester.tap(find.text('Old Company'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('会社情報を編集'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Updated Company');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pump();
    expect(repo.lastId, 'existing');
    expect(find.text('更新しました'), findsNothing);
    repo.response.complete('existing');
    await tester.pumpAndSettle();
    expect(find.text('更新しました'), findsOneWidget);
    expect(repo.lastName, 'Updated Company');
    await tester.tap(find.text('一覧で確認'));
    await tester.pumpAndSettle();
    expect(find.text('Updated Company'), findsOneWidget);
    expect(find.text('会社情報を更新しました'), findsNothing);
  });
}
