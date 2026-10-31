import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/data/supabase_backend.dart';
import 'package:sk_works/features/auth/secondary_protected_page.dart';
import 'package:sk_works/features/attendance/attendance_management_page.dart';
import 'attendance_management_entry_page_test.dart' as entry;
import 'attendance_management_bulk_calendar_test.dart' as calendar;
import 'attendance_unrecorded_punches_test.dart' as fixture;
import 'operation_reauthentication_repository_test.dart' as tokens;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if(!const bool.fromEnvironment('SKO_ENTRY_ACCESS_FIXTURE')) {
    test('bulk entry boundary requires isolated endpoint',(){},skip:'Dedicated synthetic entry workflow');return;
  }
  setUpAll(() async {
    expect(SupabaseBackendConfig.url,'https://entry-access-fixture.invalid');
    expect(SupabaseBackendConfig.publishableKey,'public_fixture');
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url:SupabaseBackendConfig.url,publishableKey:SupabaseBackendConfig.publishableKey,
      debug:false,authOptions:const FlutterAuthClientOptions(autoRefreshToken:false,detectSessionInUri:false),
      httpClient:MockClient((request) async {
        if(request.url.path.endsWith('/secondary_password_configured')) {
          return http.Response('true',200,headers:{'content-type':'application/json'},request:request);
        }
        throw StateError('Unexpected synthetic entry endpoint ${request.url.path}');
      }));
    await SupabaseBackend.initializeIfConfigured();
  });
  tearDownAll(()=>Supabase.instance.dispose());
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/local_auth'),(call) async {
        if(call.method=='isDeviceSupported'||call.method=='deviceSupportsBiometrics')return true;
        if(call.method=='getAvailableBiometrics')return ['face'];
        throw StateError('Unexpected native-auth fixture method');
      });
  });
  tearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/local_auth'),null));

  for(final boundary in ['entry revoked','background']) {
    testWidgets('actual secondary gate $boundary removes the open bulk confirmation and prevents mutation',(tester) async {
      tester.view.physicalSize=const Size(430,932);tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
      final wire=fixture.Fixture();await tester.runAsync(wire.start);
      final repository=calendar.BulkCalendarFixture(wire.client);
      final access=entry.PageAccess();
      await tester.runAsync(()=>Supabase.instance.client.auth.setInitialSession(jsonEncode({
        'access_token':tokens.token(fixture.actor,fixture.actor),'refresh_token':'synthetic-refresh',
        'expires_in':3600,'token_type':'bearer','user':{'id':fixture.actor,'aud':'authenticated','created_at':'2026-01-01T00:00:00Z'},
      })));
      try {
        await tester.pumpWidget(MaterialApp(home:SecondaryProtectedPage(title:'勤怠管理',entryAccess:()=>access,
          child:AttendanceManagementPage(repository:repository,restrictedRecovery:true))));
        await entry.settle(tester);
        await tester.enterText(find.byType(TextField).first,'synthetic-entry-password');
        await tester.tap(find.text('第2パスワードで開く'));await entry.settle(tester);
        await tester.tap(find.widgetWithText(Tab,'一括'));await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(CheckboxListTile,'検証社員'));await tester.pumpAndSettle();
        final scroll=find.descendant(of:find.byType(ListView).last,matching:find.byType(Scrollable)).first;
        final day=find.byKey(const ValueKey('bulk-calendar-day-3'));
        await tester.scrollUntilVisible(day,200,scrollable:scroll);await tester.ensureVisible(day);
        await tester.tap(day);await tester.pump();
        final remove=find.widgetWithText(OutlinedButton,'選択範囲を一括削除');
        await tester.scrollUntilVisible(remove,250,scrollable:scroll);await tester.ensureVisible(remove);
        await tester.tap(remove);await tester.pumpAndSettle();
        expect(find.byType(AlertDialog),findsOneWidget);
        if(boundary=='entry revoked') {
          access.invalidate();
        } else {
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog),findsNothing);
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        }
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog),findsNothing);
        expect(find.textContaining('従業員：検証社員'),findsNothing);
        expect(find.textContaining('出勤印のない人も'),findsNothing);
        expect(find.byType(AttendanceManagementPage),findsNothing);
        expect(find.text('第2認証が必要です'),findsOneWidget);
        expect(wire.calls.where((request)=>request.url.path.endsWith('/force_manage_attendance')),isEmpty);
        expect(tester.takeException(),isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());await tester.pump();
        if(boundary=='background') {
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        }
        await tester.runAsync(wire.client.dispose);
      }
    });
  }
}
