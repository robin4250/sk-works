import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/data/supabase_backend.dart';
import 'package:sk_works/features/auth/secondary_entry_access.dart';
import 'package:sk_works/features/auth/secondary_protected_page.dart';

import 'operation_reauthentication_repository_test.dart' as base;

class PageAccess extends SecondaryEntryAccess {
  bool opened=false;
  int verifications=0;
  int invalidations=0;
  @override bool get requiredByServer=>true;
  @override bool get isOpen=>opened;
  @override Future<void> prepare() async {}
  @override Future<bool> unlock(String password) async {
    verifications++;opened=password=='synthetic-entry-password';return opened;
  }
  @override void invalidate(){opened=false;invalidations++;notifyListeners();}
  @override Future<void> close() async {invalidate();}
}
Future<void> settle(WidgetTester tester) async {
  for(var i=0;i<5;i++) {
    await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:10)));
    await tester.pump(const Duration(milliseconds:20));
  }
  await tester.pumpAndSettle();
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if(!const bool.fromEnvironment('SKO_ENTRY_ACCESS_FIXTURE')) {
    test('entry fixture requires isolated endpoint',(){},skip:'Dedicated entry-access workflow');return;
  }
  setUpAll(() async {
    expect(SupabaseBackendConfig.url,'https://entry-access-fixture.invalid');
    expect(SupabaseBackendConfig.publishableKey,'public_fixture');
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url:SupabaseBackendConfig.url,publishableKey:SupabaseBackendConfig.publishableKey,
      debug:false,authOptions:const FlutterAuthClientOptions(autoRefreshToken:false,detectSessionInUri:false),
      httpClient:MockClient((request) async {
        if(request.url.path.endsWith('/secondary_password_configured'))return http.Response('true',200,headers:{'content-type':'application/json'},request:request);
        throw StateError('Page must verify through its entry delegate, not a second password endpoint');
      }));
    await SupabaseBackend.initializeIfConfigured();
  });
  tearDownAll(()=>Supabase.instance.dispose());
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/local_auth'),(call) async {
        if(call.method=='isDeviceSupported'||call.method=='deviceSupportsBiometrics')return true;
        if(call.method=='getAvailableBiometrics')return ['face'];
        throw StateError('No local biometric boolean may create server authorization');
      });
  });
  tearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/local_auth'),null));
  testWidgets('password once at entry; repeated child actions never ask again; background relocks', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.runAsync(()=>Supabase.instance.client.auth.setInitialSession(jsonEncode({
      'access_token':base.token(base.actorA,base.sessionA),'refresh_token':'synthetic-refresh','expires_in':3600,'token_type':'bearer',
      'user':{'id':base.actorA,'aud':'authenticated','created_at':'2026-10-26T00:00:00Z'}})));
    final access=PageAccess();var writes=0;
    await tester.pumpWidget(MaterialApp(home:SecondaryProtectedPage(title:'勤怠管理',entryAccess:()=>access,
      child:Scaffold(body:TextButton(onPressed:(){writes++;},child:const Text('合成の管理操作'))))));
    await settle(tester);
    expect(find.text('第2認証が必要です'),findsOneWidget);
    expect(find.text('合成の管理操作'),findsNothing);
    expect(find.textContaining('Face ID / Touch IDで開く'),findsNothing);
    await tester.enterText(find.byType(TextField).first,'synthetic-entry-password');
    await tester.tap(find.text('第2パスワードで開く'));await settle(tester);
    for(var i=0;i<3;i++){await tester.tap(find.text('合成の管理操作'));await tester.pump();}
    expect(writes,3);expect(access.verifications,1);expect(find.text('第2認証が必要です'),findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();expect(access.isOpen,false);expect(find.text('合成の管理操作'),findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);await settle(tester);
    expect(find.text('第2認証が必要です'),findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());await tester.runAsync(()=>Future<void>.delayed(Duration.zero));
    expect(access.invalidations,greaterThanOrEqualTo(2));
  });
}
