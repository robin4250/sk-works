/// In-memory ordered selection for a document's front, back, and extra photos.
/// No storage writes happen until a separate persistence operation succeeds.
class DocumentPhotoDraft<T> {
  DocumentPhotoDraft([Iterable<T> initial = const []])
      : _photos = List<T>.of(initial);

  final List<T> _photos;
  List<T> get photos => List<T>.unmodifiable(_photos);
  int get length => _photos.length;
  bool get isEmpty => _photos.isEmpty;
  bool get hasFrontAndBack => _photos.length >= 2;

  void add(T photo) => _photos.add(photo);
  void addAll(Iterable<T> photos) => _photos.addAll(photos);
  T removeAt(int index) => _photos.removeAt(index);
  void clear() => _photos.clear();

  /// Replace only the selected draft image; persisted attachments are separate.
  void replaceAt(int index, T photo) => _photos[index] = photo;

  /// Keep the user's explicit front/back/extra ordering.
  void move(int from, int to) {
    if (from < 0 || from >= _photos.length ||
        to < 0 || to >= _photos.length) {
      throw RangeError('Invalid photo position.');
    }
    if (from == to) return;
    final photo = _photos.removeAt(from);
    _photos.insert(to, photo);
  }
}
