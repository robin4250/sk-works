import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/notifications/notification_bell.dart';

void main() {
  test('認証エラーで旧応答を破棄し、回復時に再取得', () async {
    final state = NotificationBadgeRefresh();
    final pending = Completer<void>();
    final old = state.refresh(currentActor: () => 'a',
      loadUnread: () async { await pending.future; return []; },
      loadPending: () async => []);
    state.authError();
    expect(state.uncertain, isTrue);
    pending.complete();
    await old;
    expect(state.uncertain, isTrue);
    await state.refresh(currentActor: () => 'a', loadUnread: () async => [],
      loadPending: () async => []);
    expect(state.uncertain, isFalse);
  });

  test('失敗は0件と区別し回復後に解除', () async {
    final state = NotificationBadgeRefresh();
    await state.refresh(currentActor: () => 'a', loadUnread: () async => [],
      loadPending: () async => throw StateError('pending unavailable'));
    expect(state.count, 0);
    expect(state.uncertain, isTrue);
    await state.refresh(currentActor: () => 'a', loadUnread: () async => [],
      loadPending: () async => []);
    expect(state.count, 0);
    expect(state.uncertain, isFalse);
    await state.refresh(currentActor: () => 'a',
      loadUnread: () async => throw StateError('unread unavailable'),
      loadPending: () async => []);
    expect(state.uncertain, isTrue);
  });

  test('古いアカウントの失敗を新アカウントへ引き継がない', () async {
    final state = NotificationBadgeRefresh();
    final pending = Completer<void>();
    var actor = 'a';
    final first = state.refresh(currentActor: () => actor,
      loadUnread: () async { await pending.future; throw StateError('old'); },
      loadPending: () async => []);
    actor = 'b';
    pending.complete();
    await first;
    await state.refresh(currentActor: () => actor, loadUnread: () async => [],
      loadPending: () async => []);
    expect(state.uncertain, isFalse);
    expect(state.count, 0);
  });

  test('取得中に切替えた新しい本人の結果は古い失敗で消えない', () async {
    final state = NotificationBadgeRefresh();
    final firstPending = Completer<void>();
    var actor = 'a';
    final first = state.refresh(currentActor: () => actor,
      loadUnread: () async { await firstPending.future; throw StateError('old'); },
      loadPending: () async => []);
    actor = 'b';
    await state.refresh(currentActor: () => actor, loadUnread: () async => [],
      loadPending: () async => throw StateError('new'));
    expect(state.uncertain, isTrue);
    firstPending.complete();
    await first;
    expect(state.uncertain, isTrue);
  });

  test('同じ本人の再ログインでも古いセッションの応答を破棄', () async {
    final state = NotificationBadgeRefresh();
    final oldPending = Completer<void>();
    final first = state.refresh(currentActor: () => 'a',
      loadUnread: () async { await oldPending.future; throw StateError('old session'); },
      loadPending: () async => []);
    state.invalidate(); // Authイベントにより本人が同じでも世代を更新する。
    await state.refresh(currentActor: () => 'a', loadUnread: () async => [],
      loadPending: () async => []);
    expect(state.uncertain, isFalse);
    oldPending.complete();
    await first;
    expect(state.uncertain, isFalse);
  });

}
