import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/settings/company_income_tax_page.dart';
import 'package:url_launcher/url_launcher.dart';

import 'features/settings/company_income_tax_page_test.dart'
    show FakeIncomeTaxRepository;

const pdfLabel = '2026年（令和8年）分の税額表PDF';
const indexLabel = '年度別の税額表・関連資料';
const failedMessage = '国税庁の資料を表示できませんでした。時間をおいて再度お試しください。';

void main() {
  Future<FakeIncomeTaxRepository> open(
    WidgetTester tester,
    OfficialReferenceLauncher launcher,
  ) async {
    final repository = FakeIncomeTaxRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: CompanyIncomeTaxPage(
          companyId: 'test-company',
          repository: repository,
          referenceLauncher: launcher,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('国税庁の公式資料'));
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets('successful external launch does not open another browser', (
    tester,
  ) async {
    final calls = <LaunchMode>[];
    await open(tester, (uri, {required mode}) async {
      calls.add(mode);
      expect(
        uri.toString(),
        'https://www.nta.go.jp/publication/pamph/gensen/zeigakuhyo2026/data/all.pdf',
      );
      return true;
    });
    await tester.tap(find.text(pdfLabel));
    await tester.pumpAndSettle();
    expect(calls, [LaunchMode.externalApplication]);
    expect(find.text(failedMessage), findsNothing);
  });

  for (final externalThrows in [false, true]) {
    testWidgets(
      'external failure (throws=$externalThrows) opens same official URL in app',
      (tester) async {
        final calls = <(Uri, LaunchMode)>[];
        final repository = await open(tester, (uri, {required mode}) async {
          calls.add((uri, mode));
          if (mode == LaunchMode.externalApplication) {
            if (externalThrows) throw StateError('external unavailable');
            return false;
          }
          return true;
        });
        await tester.tap(find.text(indexLabel));
        await tester.pumpAndSettle();
        expect(calls.map((call) => call.$2), [
          LaunchMode.externalApplication,
          LaunchMode.inAppBrowserView,
        ]);
        expect(
          calls.map((call) => call.$1.toString()),
          everyElement('https://www.nta.go.jp/publication/pamph/01.htm'),
        );
        expect(find.text(failedMessage), findsNothing);
        expect(repository.uploaded, isEmpty);
        expect(repository.pdfReads, isEmpty);
      },
    );
  }

  testWidgets('both modes fail visibly and a later tap can retry', (
    tester,
  ) async {
    var calls = 0;
    await open(tester, (uri, {required mode}) async {
      calls++;
      if (mode == LaunchMode.inAppBrowserView) throw StateError('no presenter');
      return false;
    });
    await tester.tap(find.text(pdfLabel));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text(failedMessage), findsOneWidget);
    await tester.tap(find.text(pdfLabel));
    await tester.pumpAndSettle();
    expect(calls, 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'pending launch blocks duplicate taps and does not launch after dispose',
    (tester) async {
      final pending = Completer<bool>();
      final calls = <LaunchMode>[];
      await open(tester, (uri, {required mode}) {
        calls.add(mode);
        return pending.future;
      });
      await tester.tap(find.text(pdfLabel));
      await tester.pump();
      await tester.tap(find.text(indexLabel));
      expect(calls, [LaunchMode.externalApplication]);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      pending.complete(false);
      await tester.pumpAndSettle();
      expect(calls, [LaunchMode.externalApplication]);
      expect(tester.takeException(), isNull);
    },
  );
}
