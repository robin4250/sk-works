import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/worker_document_scope.dart';

void main() {
  test(
    'a shared requirement keeps one ID in all views and both destinations',
    () {
      final rows = [
        {'id': 'shared', 'scope': 'both'},
        {'id': 'own', 'scope': 'internal'},
        {'id': 'client', 'scope': 'upstream'},
      ];
      List<String?> ids(String scope) => rows
          .where((r) => workerDocumentMatchesScope(r['scope'], scope))
          .map((r) => r['id'])
          .toList();
      expect(ids('all'), ['shared', 'own', 'client']);
      expect(ids('internal'), ['shared', 'own']);
      expect(ids('upstream'), ['shared', 'client']);
      expect(workerDocumentMatchesScope('internal', 'upstream'), false);
      expect(workerDocumentMatchesScope('upstream', 'internal'), false);
      expect(workerDocumentMatchesScope('both', 'unknown'), false);
    },
  );
}
