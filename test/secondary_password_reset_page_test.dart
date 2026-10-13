import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/auth/secondary_password_reset_page.dart';

class _Access implements SecondaryPasswordResetAccess {
  String? actor = 'test-user';
  bool approved = true;
  bool failSave = false;
  bool failAuth = false;
  bool primaryApproved = true;
  int primaryCalls = 0;
  Completer<bool>? primaryPending;
  int authCalls = 0;
  int saves = 0;
  String? saved;
  Completer<bool>? authPending;
  Completer<void>? savePending;
  @override
  String? get currentUserId => actor;
  @override
  Future<bool> authenticate() async {
    authCalls++;
    if (failAuth) throw StateError('test biometric error');
    return authPending == null ? approved : await authPending!.future;
  }

  @override
  Future<bool> authenticateWithPassword(String password) async {
    primaryCalls++;
    return primaryPending == null
        ? primaryApproved
        : await primaryPending!.future;
  }

  @override
  Future<void> save(String password) async {
    saves++;
    saved = password;
    await savePending?.future;
    if (failSave) throw StateError('test transport failure');
  }
}

Future<void> _open(WidgetTester tester, _Access access) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final result = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => SecondaryPasswordResetPage(access: access),
                ),
              );
              if (context.mounted && result == true) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('reset completed')),
                );
              }
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _approve(WidgetTester tester) async {
  await tester.tap(find.text('本人確認する'));
  await tester.pumpAndSettle();
}

Future<void> _fill(
  WidgetTester tester, {
  String confirmation = 'test-password',
}) async {
  await tester.enterText(
    find.byKey(const Key('reset-password')),
    'test-password',
  );
  await tester.enterText(find.byKey(const Key('reset-confirm')), confirmation);
}

void main() {
  testWidgets(
    'successful biometric confirmation and matching password return success',
    (tester) async {
      final access = _Access();
      await _open(tester, access);
      expect(find.byType(TextField), findsNothing);
      await _approve(tester);
      await _fill(tester);
      await tester.tap(find.text('再設定する'));
      await tester.pumpAndSettle();
      expect(access.saves, 1);
      expect(access.saved, 'test-password');
      expect(find.text('reset completed'), findsOneWidget);
    },
  );

  testWidgets(
    'cancelled biometric confirmation cannot enter or save a password',
    (tester) async {
      final access = _Access()..approved = false;
      await _open(tester, access);
      await _approve(tester);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('再設定する'), findsNothing);
      expect(access.saves, 0);
    },
  );

  testWidgets('mismatch and short passwords are not submitted', (tester) async {
    final access = _Access();
    await _open(tester, access);
    await _approve(tester);
    await _fill(tester, confirmation: 'different-password');
    await tester.tap(find.text('再設定する'));
    await tester.pump();
    expect(find.text('確認用の第2パスワードが一致していません。'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('reset-password')), 'short');
    await tester.tap(find.text('再設定する'));
    await tester.pump();
    expect(find.text('第2パスワードは8文字以上で設定してください。'), findsOneWidget);
    expect(access.saves, 0);
  });

  testWidgets(
    'save failure clears approval and permits a freshly authenticated retry',
    (tester) async {
      final access = _Access()..failSave = true;
      await _open(tester, access);
      await _approve(tester);
      await _fill(tester);
      await tester.tap(find.text('再設定する'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('保存結果を確認できませんでした'), findsOneWidget);
      access.failSave = false;
      await _approve(tester);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('reset-password')))
            .controller!
            .text,
        isEmpty,
      );
      await _fill(tester);
      await tester.tap(find.text('再設定する'));
      await tester.pumpAndSettle();
      expect(access.authCalls, 2);
      expect(access.saves, 2);
      expect(find.text('reset completed'), findsOneWidget);
    },
  );

  testWidgets('ordinary inactive clears entered password and approval', (
    tester,
  ) async {
    final access = _Access();
    await _open(tester, access);
    await _approve(tester);
    await _fill(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await _approve(tester);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('reset-password')))
          .controller!
          .text,
      isEmpty,
    );
    expect(access.saves, 0);
  });

  testWidgets(
    'biometric prompt inactive is allowed but approval waits for resumed',
    (tester) async {
      final access = _Access()..authPending = Completer<bool>();
      await _open(tester, access);
      await tester.tap(find.text('本人確認する'));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      access.authPending!.complete(true);
      await tester.pump();
      expect(find.byType(TextField), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNWidgets(2));
    },
  );

  testWidgets('backgrounding during biometric prompt rejects delayed success', (
    tester,
  ) async {
    final access = _Access()..authPending = Completer<bool>();
    await _open(tester, access);
    await tester.tap(find.text('本人確認する'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    access.authPending!.complete(true);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(access.saves, 0);
  });

  testWidgets(
    'actor change during authentication and before save prevents write',
    (tester) async {
      final access = _Access()..authPending = Completer<bool>();
      await _open(tester, access);
      await tester.tap(find.text('本人確認する'));
      await tester.pump();
      access.actor = 'other-user';
      access.authPending!.complete(true);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      access.authPending = null;
      await _approve(tester);
      await _fill(tester);
      access.actor = 'third-user';
      await tester.tap(find.text('再設定する'));
      await tester.pumpAndSettle();
      expect(access.saves, 0);
      expect(find.byType(TextField), findsNothing);
    },
  );

  testWidgets(
    'duplicate save is suppressed and actor change rejects old success',
    (tester) async {
      final access = _Access()..savePending = Completer<void>();
      await _open(tester, access);
      await _approve(tester);
      await _fill(tester);
      final save = tester
          .widget<FilledButton>(find.byType(FilledButton))
          .onPressed!;
      save();
      save();
      await tester.pump();
      expect(access.saves, 1);
      access.actor = 'other-user';
      access.savePending!.complete();
      await tester.pumpAndSettle();
      expect(find.text('reset completed'), findsNothing);
      expect(find.byType(TextField), findsNothing);
    },
  );

  testWidgets(
    'backgrounding during save reports uncertainty and ignores stale completion',
    (tester) async {
      final access = _Access()..savePending = Completer<void>();
      await _open(tester, access);
      await _approve(tester);
      await _fill(tester);
      await tester.tap(find.text('再設定する'));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      access.savePending!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('保存結果を確認できません'), findsOneWidget);
      expect(find.text('reset completed'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(access.saves, 1);
    },
  );

  testWidgets('leaving during authentication ignores delayed callback', (
    tester,
  ) async {
    final access = _Access()..authPending = Completer<bool>();
    await _open(tester, access);
    await tester.tap(find.text('本人確認する'));
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    access.authPending!.complete(true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(access.saves, 0);
    expect(find.text('reset completed'), findsNothing);
  });
  testWidgets('no signed-in actor cannot start authentication', (tester) async {
    final access = _Access()..actor = null;
    await _open(tester, access);
    await _approve(tester);
    expect(access.authCalls, 0);
    expect(access.saves, 0);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('biometric exception does not authorize reset', (tester) async {
    final access = _Access()..failAuth = true;
    await _open(tester, access);
    await _approve(tester);
    expect(find.text('生体認証を利用できません。もう一度お試しください。'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(access.saves, 0);
  });

  testWidgets('disposed save completion cannot pop the previous page', (
    tester,
  ) async {
    final access = _Access()..savePending = Completer<void>();
    await _open(tester, access);
    await _approve(tester);
    await _fill(tester);
    await tester.tap(find.text('再設定する'));
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    access.savePending!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('open'), findsOneWidget);
    expect(find.text('reset completed'), findsNothing);
  });
  testWidgets(
    'primary password verification permits reset and clears its input',
    (tester) async {
      final access = _Access();
      await _open(tester, access);
      await tester.tap(find.text('本パスワード'));
      await tester.pump();
      final input = find.byKey(const Key('primary-password'));
      expect(tester.widget<TextField>(input).obscureText, isTrue);
      final controller = tester.widget<TextField>(input).controller!;
      await tester.enterText(input, 'test-primary-password');
      await _approve(tester);
      expect(controller.text, isEmpty);
      expect(access.primaryCalls, 1);
      expect(access.authCalls, 0);
      await _fill(tester);
      await tester.tap(find.text('再設定する'));
      await tester.pumpAndSettle();
      expect(access.saves, 1);
      expect(find.text('reset completed'), findsOneWidget);
    },
  );

  testWidgets('primary password rejection keeps reset locked', (tester) async {
    final access = _Access()..primaryApproved = false;
    await _open(tester, access);
    await tester.tap(find.text('本パスワード'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('primary-password')),
      'test-primary-password',
    );
    await _approve(tester);
    expect(find.byKey(const Key('reset-password')), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('primary-password')))
          .controller!
          .text,
      isEmpty,
    );
    expect(access.saves, 0);
  });

  testWidgets(
    'actor switch during primary password verification rejects completion',
    (tester) async {
      final access = _Access()..primaryPending = Completer<bool>();
      await _open(tester, access);
      await tester.tap(find.text('本パスワード'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('primary-password')),
        'test-primary-password',
      );
      await tester.tap(find.text('本人確認する'));
      await tester.pump();
      access.actor = 'other-user';
      access.primaryPending!.complete(true);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reset-password')), findsNothing);
      expect(access.saves, 0);
    },
  );

  testWidgets(
    'primary verification inactive is not treated as a native biometric prompt',
    (tester) async {
      final access = _Access()..primaryPending = Completer<bool>();
      await _open(tester, access);
      await tester.tap(find.text('本パスワード'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('primary-password')),
        'test-primary-password',
      );
      await tester.tap(find.text('本人確認する'));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      access.primaryPending!.complete(true);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reset-password')), findsNothing);
      expect(access.saves, 0);
    },
  );

  testWidgets('devices without biometrics default to primary password', (
    tester,
  ) async {
    final access = _Access();
    await tester.pumpWidget(
      MaterialApp(
        home: SecondaryPasswordResetPage(
          access: access,
          biometricAvailable: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('primary-password')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('primary-password')),
      'test-primary-password',
    );
    await _approve(tester);
    expect(find.byKey(const Key('reset-password')), findsOneWidget);
    expect(access.primaryCalls, 1);
    expect(access.authCalls, 0);
  });
  testWidgets(
    '320pt width and 1.3 text scale fit both verification methods and new inputs',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final access = _Access();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: SecondaryPasswordResetPage(access: access),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('本パスワード'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(
        find.byKey(const Key('primary-password')),
        'test-primary-password',
      );
      await tester.ensureVisible(find.text('本人確認する'));
      await _approve(tester);
      expect(tester.takeException(), isNull);
      await _fill(tester);
      await tester.ensureVisible(find.text('再設定する'));
      expect(tester.takeException(), isNull);
    },
  );
}
