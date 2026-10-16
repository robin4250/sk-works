// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:sk_works/features/daily_reports/daily_report_page.dart';
import 'package:sk_works/features/daily_reports/daily_report_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EditableReports extends DailyReportRepository {
  EditableReports(super.client) : super.forTesting();
  bool approved = true, signed = true, failSave = false;
  int saves = 0;
  @override
  String? get currentActorId => 'owner';
  @override
  String? get notificationRetryUserId => null;
  @override
  Future<bool> hasApprovedEdit(String reportId) async {
    expect(reportId, 'report-a');
    return approved;
  }
  @override
  Future<DailyReportRecord?> loadReport({required DateTime date,
    String? siteId, String? routeAssignmentId, String? vehicleClockInAnchorId,
    String? reportId}) async => DailyReportRecord(
      id: 'report-a', date: date, siteId: 'site-a', siteName: '対象現場',
      workDescription: '保存済み内容', status: signed ? 'signed' : 'draft', workers: [],
      reporterSignatureJson: signed ? {'strokes': []} : null,
      responsibleSignatureJson: signed ? {'strokes': []} : null);
  @override
  Future<List<DailyReportEvidenceRecord>> loadAttendanceEvidence({String? reportId,
    required DateTime date, String? siteId, String? routeAssignmentId}) async => [];
  @override
  Future<String> saveDraft({String? reportId, String? siteId,
    String? routeAssignmentId, required DateTime date, required String workDescription,
    required List<DailyReportWorkerDraft> workers, String? groupClockInAnchorId,
    String? vehicleClockInAnchorId}) async {
    saves++;
    expect(reportId, 'report-a');
    expect(workDescription, '保存済み内容');
    if (failSave || !approved) throw StateError('save denied');
    signed = false;
    approved = false;
    return reportId!;
  }
}

void main() {
  late SupabaseClient client;
  setUp(() {
    final previous = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);
    client = SupabaseClient('https://example.invalid', 'synthetic-public',
      authOptions: const AuthClientOptions(autoRefreshToken: false));
  });
  tearDown(() async { await client.dispose(); });

  Future<void> open(WidgetTester tester, EditableReports repo) async {
    await tester.pumpWidget(MaterialApp(home: DailyReportPage(
      initialDate: DateTime(2026, 10, 15), initialSiteId: 'site-a',
      initialReportId: 'report-a', repositoryForTesting: repo)));
    await tester.pumpAndSettle();
  }
  Future<void> begin(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('daily-report-begin-approved-edit'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('opening approval never clears signatures; explicit start enables both signatures',
    (tester) async {
      final repo = EditableReports(client);
      await open(tester, repo);
      expect(repo.saves, 0);
      expect(repo.signed, isTrue);
      await begin(tester);
      expect(repo.saves, 0);
      await tester.tap(find.text('編集を開始').last);
      await tester.pumpAndSettle();
      expect(repo.saves, 1);
      expect(repo.signed, isFalse);
      expect(find.byKey(const ValueKey('daily-report-begin-approved-edit')), findsNothing);
      final reporter = tester.widget<ListTile>(
        find.ancestor(of: find.text('報告者サイン'), matching: find.byType(ListTile)).first);
      expect(reporter.onTap, isNotNull);
      final supervisor = tester.widget<ListTile>(
        find.ancestor(of: find.text('責任者サイン'), matching: find.byType(ListTile)).first);
      expect(supervisor.onTap, isNotNull);
    });
  testWidgets('no approved request keeps signed report locked', (tester) async {
    final repo = EditableReports(client)..approved = false;
    await open(tester, repo);
    expect(find.byKey(const ValueKey('daily-report-begin-approved-edit')), findsNothing);
    expect(repo.saves, 0);
    final reporter = tester.widget<ListTile>(
      find.ancestor(of: find.text('報告者サイン'), matching: find.byType(ListTile)).first);
    expect(reporter.onTap, isNull);
  });
  testWidgets('cancel or save failure never reports successful edit start', (tester) async {
    final repo = EditableReports(client)..failSave = true;
    await open(tester, repo);
    await begin(tester);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(repo.saves, 0);
    await begin(tester);
    await tester.tap(find.text('編集を開始').last);
    await tester.pumpAndSettle();
    expect(repo.saves, 1);
    expect(repo.signed, isTrue);
    expect(find.text('編集できる状態になりました。編集後は報告者・責任者のサインを登録してください。'), findsNothing);
  });
  testWidgets('approval revoked after load cannot start editing', (tester) async {
    final repo = EditableReports(client);
    await open(tester, repo);
    repo.approved = false;
    await begin(tester);
    await tester.tap(find.text('編集を開始').last);
    await tester.pumpAndSettle();
    expect(repo.saves, 0);
    expect(repo.signed, isTrue);
  });
}
