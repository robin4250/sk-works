import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/help/manual_content.dart';

void main() {
  test('role manuals keep requested page counts', () {
    expect(ManualContent.general.length, 10);
    expect(ManualContent.subAdmin.length, 15);
    expect(ManualContent.admin.length, 20);
    expect(ManualContent.pamphlet.length, 20);
  });

  test('admin manual does not inherit sub-admin-only restrictions', () {
    final adminText = ManualContent.admin
        .map((section) => [
              section.title,
              section.summary,
              section.support,
              ...section.steps,
            ].join(' '))
        .join(' ');

    expect(adminText, isNot(contains('請求書・現場単価は対象外')));
    expect(adminText, contains('会社単価・手当設定'));
    expect(adminText, contains('管理者用現場データ'));
    expect(adminText, contains('個人事業主・一人親方'));
  });

  test('membership roles map to the correct manual', () {
    expect(
      ManualContent.fromMembershipRole('viewer'),
      ManualRole.general,
    );
    expect(
      ManualContent.fromMembershipRole('manager'),
      ManualRole.subAdmin,
    );
    expect(
      ManualContent.fromMembershipRole('admin'),
      ManualRole.admin,
    );
    expect(
      ManualContent.fromMembershipRole('owner'),
      ManualRole.admin,
    );
  });

  test('manual UI includes push-button and support guidance', () {
    final source =
        File('lib/features/help/manual_library_page.dart').readAsStringSync();

    expect(source, contains('⭕ ここを押す'));
    expect(source, contains('サポート・補足'));
    expect(source, contains('PDFを開く'));
    expect(source, contains('SKOパンフレット 20ページを開く'));
  });

  test('manual PDF supports A4 preview printing and sharing', () {
    final source =
        File('lib/features/help/manual_pdf_service.dart').readAsStringSync();

    expect(source, contains('PdfPageFormat.a4'));
    expect(source, contains('PdfPreview'));
    expect(source, contains('allowPrinting: true'));
    expect(source, contains('allowSharing: true'));
    expect(source, contains('ここを押す'));
    expect(source, contains('画面イメージ'));
  });

  test('profile and help expose role-specific manual entry points', () {
    final profile =
        File('lib/features/profile/profile_page.dart').readAsStringSync();
    final help = File('lib/features/help/help_page.dart').readAsStringSync();
    final app = File('lib/app_v2.dart').readAsStringSync();

    expect(profile, contains('使い方・説明書'));
    expect(help, contains('使い方・説明書を開く'));
    expect(app, contains('ManualContent.fromMembershipRole(_identity.role)'));
  });
}
