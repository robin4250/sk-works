import 'dart:typed_data';

/// A bounded signature/type check for avatar uploads, not a malware scanner or
/// full image decoder. Storage authorization and server limits remain required.
class AvatarUploadFormat {
  const AvatarUploadFormat._(this.mime, this.extension);
  final String mime, extension;
  static const maxBytes = 10 * 1024 * 1024;

  static AvatarUploadFormat inspect(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw StateError('プロフィール写真は10MB以内にしてください。');
    }
    bool starts(List<int> value) =>
        bytes.length >= value.length &&
        List.generate(
          value.length,
          (i) => bytes[i] == value[i],
        ).every((v) => v);
    if (starts([0xff, 0xd8, 0xff])) {
      return const AvatarUploadFormat._('image/jpeg', '.jpg');
    }
    if (starts([137, 80, 78, 71, 13, 10, 26, 10])) {
      return const AvatarUploadFormat._('image/png', '.png');
    }
    if (starts('GIF87a'.codeUnits) || starts('GIF89a'.codeUnits)) {
      return const AvatarUploadFormat._('image/gif', '.gif');
    }
    if (bytes.length >= 12 &&
        starts('RIFF'.codeUnits) &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return const AvatarUploadFormat._('image/webp', '.webp');
    }
    // ISO BMFF: inspect the bounded ftyp box, not the supplied filename.
    if (bytes.length >= 16 &&
        String.fromCharCodes(bytes.sublist(4, 8)) == 'ftyp') {
      final size = ByteData.sublistView(bytes, 0, 4).getUint32(0);
      if (size >= 16 && size <= 256 && size <= bytes.length && size % 4 == 0) {
        final brands = <String>[
          String.fromCharCodes(bytes.sublist(8, 12)),
          for (var i = 16; i < size; i += 4)
            String.fromCharCodes(bytes.sublist(i, i + 4)),
        ];
        if (!brands.any((b) => b == 'avif' || b == 'avis')) {
          if (brands.any(const {'heic', 'heix', 'hevc', 'hevx'}.contains)) {
            return const AvatarUploadFormat._('image/heic', '.heic');
          }
          if (brands.any(const {'heif', 'mif1', 'msf1'}.contains)) {
            return const AvatarUploadFormat._('image/heif', '.heif');
          }
        }
      }
    }
    throw StateError('JPEG・PNG・GIF・WebP・HEIC・HEIFの写真を選択してください。');
  }
}
