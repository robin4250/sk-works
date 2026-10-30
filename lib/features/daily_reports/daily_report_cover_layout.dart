/// Shared cover capacity: keep photo and member overflow explicit, never drop it.
class DailyReportCoverLayout {
  const DailyReportCoverLayout({required this.photoCount, required this.memberCount});
  final int photoCount;
  final int memberCount;
  static const photoColumns = 6;
  static const photoRows = 2;
  static const coverPhotoCapacity = photoColumns * photoRows;
  static const coverMemberCapacity = 6;
  int get coverPhotos => photoCount.clamp(0, coverPhotoCapacity);
  int get coverMembers => memberCount.clamp(0, coverMemberCapacity);
  int get remainingPhotos => photoCount - coverPhotos;
  int get remainingMembers => memberCount - coverMembers;
}

/// Bound each paragraph by printable lines while retaining every code point.
/// Explicit newlines also consume a line, so pasted multi-line notes continue.
List<String> dailyReportDescriptionParts(String text) {
  final parts = <String>[];
  var current = StringBuffer();
  var columns = 0;
  var lines = 1;
  for (final rune in text.runes) {
    if (lines > 4) {
      parts.add(current.toString());
      current = StringBuffer(); columns = 0; lines = 1;
    }
    current.writeCharCode(rune);
    if (rune == 10) { columns = 0; lines++; }
    else { columns++; if (columns >= 42) { columns = 0; lines++; } }
  }
  if (current.isNotEmpty || parts.isEmpty) parts.add(current.toString());
  return parts;
}
