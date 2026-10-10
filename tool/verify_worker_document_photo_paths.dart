import '../lib/features/people/worker_document_photos.dart';

void require(bool condition, String description) {
  if (!condition) throw StateError(description);
}

void main() {
  require(workerDocumentPaths(null).isEmpty, 'missing row');
  require(
    workerDocumentPaths({'attachment_path': 'front.jpg'}).single == 'front.jpg',
    'legacy photo preserved',
  );
  final paths = workerDocumentPaths({
    'attachment_path': 'front.jpg',
    'attachment_paths': ['front.jpg', 'back.jpg', 'extra.jpg'],
  });
  require(
    paths.join(',') == 'front.jpg,back.jpg,extra.jpg',
    'ordered full list',
  );
  require(
    workerDocumentPaths({
          'attachment_path': 'legacy.jpg',
          'attachment_paths': [],
        }).single ==
        'legacy.jpg',
    'additive migration fallback',
  );
  for (final value in [
    ['a', 'a'],
    [''],
    [null],
    'a',
  ]) {
    var rejected = false;
    try {
      workerDocumentPaths({'attachment_paths': value});
    } on StateError {
      rejected = true;
    }
    require(rejected, 'malformed or duplicate list rejected');
  }
  print(
    'PASS: legacy and ordered photo paths, migration fallback, malformed lists',
  );
}
