import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/domain/company_uploaded_seal_png.dart';
import 'package:sk_works/features/settings/company_seal_image_versions_repository.dart';
import 'package:sk_works/features/settings/company_seal_png_repository.dart';
import 'package:sk_works/features/settings/company_seal_png_uploader.dart';

const company = (
  companyId: '00000000-0000-0000-0000-000000000001',
  name: '検証株式会社',
);
const emptyMessage = '追加保存した角印はありません。画像を追加保存すると、ここで選べます。';

class _Settings implements CompanySealPngSource {
  int saves = 0;
  @override
  Future<CompanySealPngSettings> load(UploadedSealCompany company) async =>
      CompanySealPngSettings(company: company, available: true);
  @override
  Future<CompanySealPngSettings> save(
    CompanySealPngSettings settings, {
    CompanyUploadedSealPng? png,
    required bool enabled,
  }) async {
    saves++;
    throw StateError('Empty history must not save or select');
  }
}

class _UnusedClient extends Fake implements SupabaseClient {}

class _Versions extends CompanySealImageVersionsRepository {
  _Versions(super.client);
  Completer<List<CompanySealImageVersion>> response = Completer();
  @override
  Future<bool> allowed() async => true;
  @override
  Future<List<CompanySealImageVersion>> list(
    UploadedSealCompany company, {
    CompanySealImageVersion? before,
  }) => response.future;
}

void main() {
  testWidgets(
    'empty state appears only after successful history load, never during reload or failure',
    (tester) async {
      final client = _UnusedClient();
      final versions = _Versions(client), settings = _Settings();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CompanySealPngUploader(
                company: company,
                source: settings,
                versionsForTesting: versions,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(emptyMessage), findsNothing);
      final button = find.text('追加保存した角印を選ぶ');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(find.text(emptyMessage), findsNothing);
      versions.response.complete([]);
      await tester.pumpAndSettle();
      expect(find.text(emptyMessage), findsOneWidget);
      versions.response = Completer();
      await tester.tap(button);
      await tester.pump();
      expect(find.text(emptyMessage), findsNothing);
      versions.response.completeError(StateError('synthetic failure'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(emptyMessage), findsNothing);
      expect(find.text('角印の履歴を読み込めません。追加保存の準備を確認してください。'), findsOneWidget);
      expect(settings.saves, 0);
    },
  );

  testWidgets(
    'changing company clears the previous successfully empty history state',
    (tester) async {
      final client = _UnusedClient();
      final versions = _Versions(client), settings = _Settings();
      Widget page(UploadedSealCompany context) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CompanySealPngUploader(
              company: context,
              source: settings,
              versionsForTesting: versions,
            ),
          ),
        ),
      );
      await tester.pumpWidget(page(company));
      await tester.pumpAndSettle();
      final button = find.text('追加保存した角印を選ぶ');
      await tester.ensureVisible(button);
      await tester.tap(button);
      versions.response.complete([]);
      await tester.pumpAndSettle();
      expect(find.text(emptyMessage), findsOneWidget);
      await tester.pumpWidget(
        page((
          companyId: '00000000-0000-0000-0000-000000000003',
          name: '別の検証株式会社',
        )),
      );
      await tester.pumpAndSettle();
      expect(find.text(emptyMessage), findsNothing);
      expect(settings.saves, 0);
    },
  );
}
