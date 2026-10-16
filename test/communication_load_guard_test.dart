import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sk_works/features/notes/notes_cloud_repository.dart';
import 'package:sk_works/features/albums/albums_cloud_repository.dart';
import 'package:sk_works/features/albums/albums_cloud_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/notes/notes_cloud_page.dart';

class FakeNotes implements NotesCloudRepository {
  List<Map<String, dynamic>> groups = [{'id': 'g', 'name': 'allowed'}];
  Future<List<Map<String, dynamic>>> Function() content = () async =>
      [{'id': 'n', 'title': 'private note', 'body': '', 'is_pinned': false}];
  @override
  Future<List<Map<String, dynamic>>> loadGroups() async => groups;
  @override
  Future<List<Map<String, dynamic>>> loadNotes(String groupId) => content();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class FakeAlbums implements AlbumsCloudRepository {
  List<Map<String, dynamic>> groups = [{'id': 'g', 'name': 'allowed'}];
  Future<List<Map<String, dynamic>>> Function() content = () async =>
      [{'id': 'a', 'name': 'private album', 'description': ''}];
  @override
  Future<List<Map<String, dynamic>>> loadGroups() async => groups;
  @override
  Future<List<Map<String, dynamic>>> loadAlbums(String groupId) => content();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final album in [false, true]) {
    testWidgets('refresh removes stale content after access loss: album=$album', (tester) async {
      final notes = FakeNotes();
      final albums = FakeAlbums();
      await tester.pumpWidget(MaterialApp(home: album
          ? AlbumsCloudPage(repository: albums, currentActorId: () => 'actor')
          : NotesCloudPage(repository: notes, currentActorId: () => 'actor')));
      await tester.pumpAndSettle();
      expect(find.text(album ? 'private album' : 'private note'), findsOneWidget);
      notes.groups = [];
      albums.groups = [];
      await tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh();
      await tester.pumpAndSettle();
      expect(find.text(album ? 'private album' : 'private note'), findsNothing);
    });
    testWidgets('late content from previous actor is rejected: album=$album', (tester) async {
      var actor = 'before';
      final pending = Completer<List<Map<String, dynamic>>>();
      final notes = FakeNotes()..content = () => pending.future;
      final albums = FakeAlbums()..content = () => pending.future;
      await tester.pumpWidget(MaterialApp(home: album
          ? AlbumsCloudPage(repository: albums, currentActorId: () => actor)
          : NotesCloudPage(repository: notes, currentActorId: () => actor)));
      await tester.pump();
      actor = 'after';
      pending.complete([{'id': 'old', 'name': 'old secret', 'title': 'old secret'}]);
      await tester.pump();
      expect(find.text('old secret'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  test('old group response cannot replace a newer group', () {
    final guard = CommunicationLoadGuard();
    final old = guard.invalidate();
    final current = guard.invalidate();
    expect(guard.accepts(old, 'a', 'a', requestedGroup: 'g1', currentGroup: 'g2'), isFalse);
    expect(guard.accepts(current, 'a', 'a', requestedGroup: 'g2', currentGroup: 'g2'), isTrue);
  });
  test('logout and account switch reject previous actor data', () {
    final guard = CommunicationLoadGuard();
    final ticket = guard.invalidate();
    expect(guard.accepts(ticket, 'a', null), isFalse);
    expect(guard.accepts(ticket, 'a', 'b'), isFalse);
    expect(guard.accepts(ticket, null, null), isFalse);
  });
  test('permission reload invalidates pending content even for same actor', () {
    final guard = CommunicationLoadGuard();
    final ticket = guard.invalidate();
    guard.invalidate();
    expect(guard.accepts(ticket, 'a', 'a', requestedGroup: 'g', currentGroup: 'g'), isFalse);
  });
}
