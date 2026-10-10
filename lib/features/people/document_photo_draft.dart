/// In-memory ordered selection for a document's front, back, and extra photos.
/// No storage writes happen until a separate persistence operation succeeds.
class DocumentPhotoDraft<T> {
  DocumentPhotoDraft([Iterable<T> initial = const []])
      : _photos = List<T>.of(initial);

  final List<T> _photos;
  List<T> get photos => List<T>.unmodifiable(_photos);
  int get length => _photos.length;
  bool get isEmpty => _photos.isEmpty;

  void add(T photo) => _photos.add(photo);
  void addAll(Iterable<T> photos) => _photos.addAll(photos);
  T removeAt(int index) => _photos.removeAt(index);
  void clear() => _photos.clear();
}
