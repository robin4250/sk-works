import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/security/security_pdf_preview.dart';
import 'package:sk_works/features/security/security_actor_boundary.dart';

void main() {
  testWidgets('actor revocation removes rendered PDF and never restores it', (tester) async {
    final actors = StreamController<String?>();
    addTearDown(actors.close);
    await tester.pumpWidget(MaterialApp(home: SecurityActorBoundary(
      initialActor: 'master', actorChanges: actors.stream,
      child: SecurityPdfPreview(
        authorize: () async {},
        buildPdf: () async => Uint8List.fromList([1]),
        printPdf: (_) async => fail('native output must not run'),
        sharePdf: (_) async => fail('native output must not run'),
        previewBuilder: (_) => const Text('PDF contents'),
      ),
    )));
    await tester.pumpAndSettle();
    expect(find.text('PDF contents'), findsOneWidget);
    actors.add('other');
    await tester.pumpAndSettle();
    expect(find.text('PDF contents'), findsNothing);
    actors.add('master');
    await tester.pumpAndSettle();
    expect(find.text('PDF contents'), findsNothing);
  });

  testWidgets('checks before and after generation and every output, reusing bytes', (tester) async {
    final calls = <String>[];
    final bytes = Uint8List.fromList([1, 2, 3]);
    await tester.pumpWidget(MaterialApp(home: SecurityPdfPreview(
      authorize: () async { calls.add('authorize'); },
      buildPdf: () async { calls.add('build'); return bytes; },
      printPdf: (value) async { expect(identical(value, bytes), isTrue); calls.add('print'); },
      sharePdf: (value) async { expect(identical(value, bytes), isTrue); calls.add('share'); },
      previewBuilder: (_) => const Text('PDF contents'),
    )));
    await tester.pumpAndSettle();
    expect(calls, ['authorize', 'build', 'authorize']);
    for (final label in ['印刷', '印刷', '保存・共有']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }
    expect(calls, ['authorize', 'build', 'authorize', 'authorize', 'print', 'authorize', 'print', 'authorize', 'share']);
    await tester.pump();
    expect(calls.where((c) => c == 'build').length, 1);
  });

  for (final deniedAt in [1, 2, 3]) {
    testWidgets('authorization denial $deniedAt hides content and blocks native output', (tester) async {
      var checks = 0;
      var outputs = 0;
      await tester.pumpWidget(MaterialApp(home: SecurityPdfPreview(
        authorize: () async { if (++checks == deniedAt) throw StateError('denied'); },
        buildPdf: () async => Uint8List.fromList([1]),
        printPdf: (_) async { outputs++; },
        sharePdf: (_) async { outputs++; },
        previewBuilder: (_) => const Text('PDF contents'),
      )));
      await tester.pumpAndSettle();
      if (deniedAt == 3) {
        expect(find.text('PDF contents'), findsOneWidget);
        await tester.tap(find.text('印刷'));
        await tester.pumpAndSettle();
      }
      expect(find.text('PDF contents'), findsNothing);
      expect(outputs, 0);
      expect(find.text('出力できません。画面を閉じて開き直してください。'), findsOneWidget);
    });
  }

  testWidgets('disposing authenticated action during authorization never publishes bytes', (tester) async {
    final gate = ValueNotifier<bool>(true);
    var checks = 0;
    var outputs = 0;
    await tester.pumpWidget(MaterialApp(home: ValueListenableBuilder<bool>(
      valueListenable: gate,
      builder: (_, active, child) => active ? SecurityPdfPreview(
        authorize: () async { checks++; },
        buildPdf: () async { gate.value = false; return Uint8List.fromList([1]); },
        printPdf: (_) async { outputs++; },
        sharePdf: (_) async { outputs++; },
        previewBuilder: (_) => const Text('PDF contents'),
      ) : const Text('locked'),
    )));
    await tester.pumpAndSettle();
    expect(find.text('PDF contents'), findsNothing);
    expect(find.text('locked'), findsOneWidget);
    expect(outputs, 0);
    expect(checks, greaterThanOrEqualTo(1));
    gate.dispose();
  });
}
