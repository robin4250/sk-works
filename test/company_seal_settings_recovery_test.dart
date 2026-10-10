import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/settings/company_seal_settings_page.dart';
import 'package:sk_works/features/settings/company_seal_style_repository.dart';

class _Source implements CompanySealSettingsDataSource {
  String company = 'company';
  String style = 'aoyagi_reisho';
  bool enabled = true;
  bool failStyle = false;
  int styleLoads = 0;
  int saves = 0;
  Completer<void>? pending;

  @override
  Future<CompanySealContext> loadContext() async =>
      (companyId: company, name: '株式会社テスト');
  @override
  Future<bool> loadEnabled() async => enabled;
  @override
  Future<bool> saveEnabled(bool value) async {
    saves++;
    return enabled = value;
  }

  @override
  Future<CompanySealStyleSettings> loadStyle(CompanySealContext context) async {
    styleLoads++;
    await pending?.future;
    if (failStyle) throw StateError('unavailable');
    return CompanySealStyleSettings(
      companyId: context.companyId,
      name: context.name,
      style: style,
      available: true,
    );
  }

  @override
  Future<void> saveStyle(
    CompanySealStyleSettings settings,
    String value,
  ) async {
    saves++;
    style = value;
  }
}

Future<void> _open(
  WidgetTester tester,
  _Source source,
  Future<String> Function(String) coverage,
) async {
  await tester.binding.setSurfaceSize(const Size(900, 1500));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: CompanySealSettingsPage(dataSource: source, loadCoverage: coverage),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'coverage failure preserves legacy preview and visibility, blocks Reisho',
    (tester) async {
      final source = _Source();
      await _open(
        tester,
        source,
        (_) async => throw StateError('asset missing'),
      );
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      final dropdown = tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>),
      );
      dropdown.onChanged!('legacy');
      await tester.pump();
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNotNull,
      );
      // Recovery does not bypass the required PDF preview before style saving.
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged!(
        false,
      );
      await tester.pumpAndSettle();
      expect(source.enabled, isFalse);
      expect(source.saves, 1);
    },
  );

  testWidgets(
    'retry remains busy until coverage completes and ignores duplicate callbacks',
    (tester) async {
      final source = _Source()..failStyle = true;
      final coverage = Completer<String>();
      await _open(tester, source, (_) => coverage.future);
      final retry = tester
          .widget<TextButton>(find.widgetWithText(TextButton, '再読み込み'))
          .onPressed!;
      source.failStyle = false;
      retry();
      retry();
      await tester.pump();
      expect(source.styleLoads, 2);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNull,
      );
      coverage.complete('');
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNotNull,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'company switch during failed coverage clears editable settings',
    (tester) async {
      final source = _Source();
      await _open(tester, source, (_) async {
        source.company = 'other';
        throw StateError('asset missing');
      });
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.text('会社の選択が変わりました。再読み込みしてください。'), findsOneWidget);
      expect(source.saves, 0);
    },
  );

  testWidgets('company switch before visibility save prevents write', (
    tester,
  ) async {
    final source = _Source();
    await _open(tester, source, (_) async => '');
    source.company = 'other';
    tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged!(
      false,
    );
    await tester.pumpAndSettle();
    expect(source.saves, 0);
    expect(find.text('会社角印の設定を保存できませんでした。'), findsOneWidget);
  });

  testWidgets('disposed page ignores delayed load completion', (tester) async {
    final source = _Source()..pending = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: CompanySealSettingsPage(
          dataSource: source,
          loadCoverage: (_) async => '',
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    source.pending!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
