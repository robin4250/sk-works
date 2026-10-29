import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/qualifications/qualification_cloud_page.dart';
import 'package:sk_works/features/qualifications/qualification_cloud_repository.dart';
import 'package:sk_works/features/qualifications/qualification_certificate_repository.dart';
import 'package:sk_works/international/language_controller.dart';
import 'package:sk_works/international/language_pack_registry.dart';

class _Cloud implements QualificationCloudRepository {
  @override Future<bool Function()> captureAttachmentReadScope() async => () => false;
  int writes = 0;
  @override
  Future<Map<String, dynamic>> loadAll() async => {
    'masters': [{'id': 'master', 'name': '登録済みの資格・講習'}],
    'workers': [{'id': 'worker', 'name': '登録済み社員'}],
    'qualifications': <Map<String, dynamic>>[],
  };
  @override
  Future<bool> canManageMaster() async => true;
  @override
  Future<bool> canManageWorkerQualifications() async => true;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    writes++;
    throw StateError('Opening and cancelling must not write');
  }
}
class _Certificates implements QualificationCertificateRepository {
  @override
  Future<bool> canManageCertificates() async => false;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No certificate mutation expected');
}
void main() {
  setUp(() => SkoLanguageController.pack.value =
      LanguagePackRegistry.resolve('ja'));
  tearDown(() => SkoLanguageController.pack.value =
      LanguagePackRegistry.resolve('ja'));
  for (final size in [const Size(320, 640), const Size(390, 844), const Size(1024, 768)]) {
    for (final master in [false, true]) {
      testWidgets('qualification dialog master=$master width=${size.width} remains usable with keyboard',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final keyboard = ValueNotifier<double>(0);
        final repository = _Cloud();
        await tester.pumpWidget(MaterialApp(
          builder: (context, child) => ValueListenableBuilder<double>(
            valueListenable: keyboard,
            builder: (context, bottom, _) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                viewInsets: EdgeInsets.only(bottom: bottom),
                textScaler: const TextScaler.linear(1.3),
              ),
              child: child!,
            ),
          ),
          home: QualificationCloudPage(
            repository: repository, certificateRepository: _Certificates()),
        ));
        await tester.pumpAndSettle();
        await tester.tap(master ? find.byTooltip('資格マスター追加') : find.text('資格を登録'));
        await tester.pumpAndSettle();
        final dialog = find.byType(AlertDialog);
        expect(dialog, findsOneWidget);
        final field = find.descendant(of: dialog, matching: find.byType(TextField)).first;
        final available = size.width - 80;
        expect(tester.getSize(field).width, greaterThanOrEqualTo(available < 512 ? available : 512));
        final outerWidth = size.width - 32;
        expect(tester.getSize(field).width, lessThanOrEqualTo(outerWidth < 560 ? outerWidth : 560));
        keyboard.value = 260;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final cancel = find.descendant(of: dialog, matching: find.text('キャンセル'));
        expect(tester.getCenter(cancel).dy, lessThan(size.height - 260));
        await tester.tap(cancel);
        keyboard.value = 0;
        await tester.pumpAndSettle();
        expect(dialog, findsNothing);
        expect(repository.writes, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        keyboard.dispose();
      });
    }
  }
}
