import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/domain/company_seal_design.dart';
import 'package:sk_works/domain/company_seal_snapshot.dart';
import 'package:sk_works/features/payroll/payroll_confirmation_repository.dart';
import 'package:sk_works/features/payroll/payroll_pdf_service.dart';
import 'package:sk_works/features/payroll/payroll_statement_repository.dart';
import 'package:sk_works/features/payroll/payroll_statement_source_repository.dart';
import 'package:sk_works/features/shared/pdf_bytes_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixturePath = Platform.environment['SKO_PAYROLL_SEAL_FIXTURE_PATH'];
  final fontPath = Platform.environment['SKO_PDF_FONT_PATH'];

  test('actual SQL payroll seal responses reach the adopted PDF and freeze after finalization', () async {
    final fixture = jsonDecode(File(fixturePath!).readAsStringSync()) as Map;
    final records = <String, PayrollStatementRecord>{};
    for (final key in [
      'draft',
      'finalized',
      'finalizedAfterStyleChange',
      'historicalFinalized',
      'offDraft',
    ]) {
      records[key] = payrollStatementFromRow(
        Map<String, dynamic>.from(fixture[key] as Map),
        null,
      );
    }
    final current = CompanySealSnapshot.fromJson(
      records['draft']!.detail['company_seal_snapshot'],
    );
    expect(CompanySealDesign.isPng(current.style), isTrue);
    expect(current.companyId, CompanySealDesign.companyId);
    expect(records['draft']!.isDraft, isTrue);
    for (final key in ['finalized', 'finalizedAfterStyleChange']) {
      expect(records[key]!.workflowState, 'finalized');
      expect(
        records[key]!.detail['company_seal_snapshot'],
        records['draft']!.detail['company_seal_snapshot'],
      );
    }
    expect(
      CompanySealSnapshot.fromJson(
        records['historicalFinalized']!.detail['company_seal_snapshot'],
      ).style,
      'legacy',
    );
    expect(records['offDraft']!.detail['company_seal_enabled'], isFalse);

    final output = Directory('build/payroll-current-seal-proof')
      ..createSync(recursive: true);
    final fontData = ByteData.sublistView(File(fontPath!).readAsBytesSync());
    for (final entry in records.entries) {
      var confirmationReads = 0;
      final repository = PayrollStatementSourceRepository(
        readManagement: (_) async => [entry.value],
        readSelf: () async => throw StateError('unexpected self fallback'),
        readConfirmation: (_) async {
          confirmationReads++;
          return PayrollConfirmationStatus.fromJson({'confirmed': false});
        },
      );
      final source = await repository.load(entry.value);
      expect(identical(source.statement, entry.value), isTrue);
      expect(confirmationReads, entry.value.isDraft ? 1 : 0);

      final cache = PdfBytesCache();
      var builds = 0;
      Future<Uint8List> generate() {
        builds++;
        final font = pw.Font.ttf(fontData);
        return PayrollPdfService.buildPdf(
          source.statement,
          regularFont: font,
          boldFont: font,
        );
      }

      final preview = await cache.get(generate);
      final print = await cache.get(generate);
      final share = await cache.get(generate);
      expect(identical(preview, print), isTrue);
      expect(identical(preview, share), isTrue);
      expect(builds, 1);
      final pngExpected = ![
        'historicalFinalized',
        'offDraft',
      ].contains(entry.key);
      expect(latin1.decode(preview).contains('/SMask'), pngExpected);
      File('${output.path}/${entry.key}.pdf').writeAsBytesSync(preview);
    }
  }, skip: fixturePath == null || fontPath == null);
}
