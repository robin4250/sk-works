import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/settings/company_income_tax_page.dart';
import 'package:sk_works/features/settings/company_income_tax_repository.dart';

const company = '00000000-0000-4000-8000-000000000001';
IncomeTaxPdfFile pdf() => IncomeTaxPdfFile(name: '2030.pdf', bytes: '%PDF-fixture'.codeUnits);
IncomeTaxUploadRequest request() => IncomeTaxUploadRequest.create(companyId: company, year: 2030, kind: 'monthly',
  startsOn: '2030-01-01', endsOn: '2030-12-31', sourceUrl: 'https://example.org/table.pdf', publisher: '登録情報元', file: pdf());
Map<String, dynamic> row(IncomeTaxUploadRequest request) => {
  'table_id': request.tableId, 'version': 1, 'value': request.value,
  'official_document_verified': false, 'calculation_rules_verified': false, 'common_data_approved': false,
  'registered_by': 'admin', 'registered_at': '2026-10-10T00:00:00Z',
};

class FakeIncomeTaxRepository implements CompanyIncomeTaxRepository {
  CompanyIncomeTaxTablesData data = const CompanyIncomeTaxTablesData(tables: [], selected: null, history: []);
  final List<IncomeTaxUploadRequest> uploaded = [];
  bool loseReply = false;
  bool failUpload = false;
  bool failRead = false;
  @override
  Future<CompanyIncomeTaxTablesData> read({required String companyId, required String date, required String kind}) async {
    if (failRead) throw StateError('offline');
    return data;
  }
  @override
  Future<CompanyIncomeTaxTable> registerPdf(IncomeTaxUploadRequest request) async {
    uploaded.add(request);
    if (failUpload) throw const IncomeTaxUploadIncomplete();
    final saved = CompanyIncomeTaxTable.fromJson(row(request), request.companyId);
    data = CompanyIncomeTaxTablesData(tables: [saved], selected: null, history: []);
    if (loseReply) throw StateError('reply lost');
    return saved;
  }
  @override
  Future<String> pdfUrl(String storagePath) async => 'https://example.org/signed.pdf';
}

Future<void> open(WidgetTester tester, FakeIncomeTaxRepository repository) async {
  await tester.pumpWidget(MaterialApp(home: CompanyIncomeTaxPage(companyId: company, repository: repository, pickPdf: () async => pdf())));
  await tester.pumpAndSettle();
}
Future<void> fillRegistration(WidgetTester tester) async {
  await tester.tap(find.text('PDFを登録'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('income-year')), '2030');
  await tester.tap(find.text('PDFを選択（10MB以下）'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('income-source-url')), 'https://example.org/table.pdf');
  await tester.tap(find.text('内容を確認'));
  await tester.pumpAndSettle();
}

void main() {
  test('rejects missing PDF magic, non-PDF name and oversize bytes before upload', () {
    expect(() => IncomeTaxPdfFile(name: 'file.pdf', bytes: 'not a PDF'.codeUnits), throwsFormatException);
    expect(() => IncomeTaxPdfFile(name: 'file.png', bytes: '%PDF-fixture'.codeUnits), throwsFormatException);
    expect(() => IncomeTaxPdfFile(name: 'file.pdf', bytes: List.filled(incomeTaxPdfMaxBytes + 1, 0)), throwsFormatException);
  });
  test('request keeps PDF bytes immutable and validates civil period/year', () {
    final upload = request();
    expect(upload.value['document_hash'], 'ed41915c09594a9cfbd60c7094cde97444d46c73277d2d84947f73edfc251742');
    expect(upload.value['storage_path'], '$company/${upload.tableId}/1/${upload.value['document_hash']}.pdf');
    expect(() => upload.file.bytes[0] = 0, throwsUnsupportedError);
    expect(() => parseIncomeTaxDate('2030-02-30'), throwsFormatException);
    expect(() => IncomeTaxUploadRequest.create(companyId: company, year: 2030, kind: 'monthly',
      startsOn: '2029-01-01', endsOn: '2030-12-31', sourceUrl: 'https://example.org/table.pdf', publisher: 'source', file: pdf()), throwsFormatException);
  });
  test('included final day converts civil year and leap boundaries without timezone conversion', () {
    expect(incomeTaxExclusiveEnd('2030-12-31'), '2031-01-01');
    expect(incomeTaxIncludedLastDay('2031-01-01'), '2030-12-31');
    expect(incomeTaxExclusiveEnd('2028-02-28'), '2028-02-29');
    expect(incomeTaxExclusiveEnd('2028-02-29'), '2028-03-01');
    expect(incomeTaxIncludedLastDay('2028-03-01'), '2028-02-29');
    expect(incomeTaxExclusiveEnd('2100-02-28'), '2100-03-01');
    expect(incomeTaxIncludedLastDay('2100-03-01'), '2100-02-28');
  });
  test('invalid source and filename metadata fails before any upload or RPC', () async {
    var uploads = 0;
    var calls = 0;
    final repository = SupabaseCompanyIncomeTaxRepository(upload: (_, bytes) async { uploads++; }, rpc: (_, parameters) async { calls++; return null; });
    for (final invalid in [
      {'url': 'https://example.org/${List.filled(2048, 'a').join()}', 'publisher': 'source', 'filename': '2030.pdf'},
      {'url': 'https://example.org/table.pdf', 'publisher': List.filled(201, 'a').join(), 'filename': '2030.pdf'},
      {'url': 'https://example.org/table.pdf', 'publisher': 'source', 'filename': '${List.filled(197, 'a').join()}.pdf'},
      {'url': 'https://example.org/table.pdf', 'publisher': 'source', 'filename': 'folder/file.pdf'},
      {'url': 'https://example.org/table.pdf', 'publisher': 'source', 'filename': r'folder\file.pdf'},
    ]) {
      final attempt = () async {
        final upload = IncomeTaxUploadRequest.create(companyId: company, year: 2030, kind: 'monthly', startsOn: '2030-01-01', endsOn: '2030-12-31',
          sourceUrl: invalid['url']!, publisher: invalid['publisher']!, file: IncomeTaxPdfFile(name: invalid['filename']!, bytes: '%PDF-fixture'.codeUnits));
        await repository.registerPdf(upload);
      };
      await expectLater(attempt(), throwsFormatException);
    }
    expect(uploads, 0);
    expect(calls, 0);
  });
  test('metadata RPC is never called after failed byte upload', () async {
    var rpcCalls = 0;
    final repository = SupabaseCompanyIncomeTaxRepository(upload: (_, bytes) async => throw StateError('upload failed'),
      rpc: (_, parameters) async { rpcCalls++; return null; });
    await expectLater(repository.registerPdf(request()), throwsA(isA<IncomeTaxUploadIncomplete>()));
    expect(rpcCalls, 0);
  });
  test('uploads actual PDF before metadata and rejects wrong saved identity', () async {
    final upload = request();
    final events = <String>[];
    final repository = SupabaseCompanyIncomeTaxRepository(upload: (path, bytes) async {
      events.add('upload'); expect(bytes, pdf().bytes); expect(path, upload.value['storage_path']);
    }, rpc: (_, parameters) async {
      events.add('metadata'); expect(parameters['p_confirmed'], true); expect(parameters['p_expected_version'], 0);
      return {...row(upload), 'table_id': '00000000-0000-4000-8000-000000000002'};
    });
    await expectLater(repository.registerPdf(upload), throwsFormatException);
    expect(events, ['upload', 'metadata']);
  });
  test('client cannot turn upload into verified or shared data via returned flags', () async {
    final upload = request();
    for (final flag in ['official_document_verified', 'common_data_approved']) {
      final repository = SupabaseCompanyIncomeTaxRepository(upload: (_, bytes) async {}, rpc: (_, parameters) async => {...row(upload), flag: true});
      await expectLater(repository.registerPdf(upload), throwsFormatException);
    }
  });
  test('merely uploaded metadata cannot be returned as applicable table', () {
    final upload = request();
    expect(() => CompanyIncomeTaxTablesData.fromJson({'tables': [row(upload)], 'selected': row(upload), 'history': []},
      company, '2030-04-01', 'monthly'), throwsFormatException);
    final data = CompanyIncomeTaxTablesData.fromJson({'tables': [row(upload)], 'selected': null, 'history': []}, company, '2030-04-01', 'monthly');
    expect(data.selected, isNull);
    expect(data.tables.single.officialVerified, isFalse);
  });
  testWidgets('cancel confirmation uploads nothing; confirmed registration remains unverified', (tester) async {
    final repository = FakeIncomeTaxRepository();
    await open(tester, repository);
    await fillRegistration(tester);
    expect(find.text('適用開始 2030-01-01'), findsOneWidget);
    expect(find.text('適用最終日 2030-12-31'), findsOneWidget);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(repository.uploaded, isEmpty);
    await fillRegistration(tester);
    await tester.tap(find.text('確認して登録'));
    await tester.pumpAndSettle();
    expect(repository.uploaded, hasLength(1));
    expect(find.text('未検証'), findsOneWidget);
    expect(find.text('確認日の適用候補はありません'), findsOneWidget);
  });
  testWidgets('lost reply blocks new registration and reread confirms same request without retransmission', (tester) async {
    final repository = FakeIncomeTaxRepository()..loseReply = true;
    await open(tester, repository);
    await fillRegistration(tester);
    await tester.tap(find.text('確認して登録'));
    await tester.pumpAndSettle();
    expect(find.text('PDFを未検証資料として登録しました'), findsNothing);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'PDFを登録')).onPressed, isNull);
    await tester.tap(find.text('再読み込み'));
    await tester.pumpAndSettle();
    expect(repository.uploaded, hasLength(1));
    expect(find.text('PDFの登録を確認しました'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'PDFを登録')).onPressed, isNotNull);
  });
  testWidgets('pre-metadata upload failure allows explicit retry with the same request', (tester) async {
    final repository = FakeIncomeTaxRepository()..failUpload = true;
    await open(tester, repository);
    await fillRegistration(tester);
    await tester.tap(find.text('確認して登録'));
    await tester.pumpAndSettle();
    expect(repository.uploaded, hasLength(1));
    expect(repository.data.tables, isEmpty);
    expect(find.text('PDFを未検証資料として登録しました'), findsNothing);
    expect(find.text('ファイルを選び直す'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'アップロードを再試行')).onPressed, isNotNull);
    final originalId = repository.uploaded.single.tableId;
    repository.failUpload = false;
    await tester.tap(find.text('アップロードを再試行'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('確認して登録'));
    await tester.pumpAndSettle();
    expect(repository.uploaded, hasLength(2));
    expect(repository.uploaded.last.tableId, originalId);
    expect(repository.data.tables, hasLength(1));
    expect(find.text('未検証'), findsOneWidget);
  });
  testWidgets('failed read gives retry without a false empty list or register action', (tester) async {
    final repository = FakeIncomeTaxRepository()..failRead = true;
    await open(tester, repository);
    expect(find.text('登録済み資料はありません'), findsNothing);
    expect(find.text('PDFを登録'), findsNothing);
    repository.failRead = false;
    await tester.tap(find.text('再読み込み'));
    await tester.pumpAndSettle();
    expect(find.text('登録済み資料はありません'), findsOneWidget);
  });
}
