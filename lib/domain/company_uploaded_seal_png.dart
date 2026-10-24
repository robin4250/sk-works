import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;

/// A bounded, integrity-checked upload. The UI must additionally decode it with
/// instantiateImageCodec before preview/save; this class validates the container.
class CompanyUploadedSealPng {
  CompanyUploadedSealPng._(this._bytes, this.width, this.height, this.sha256);
  static const maxBytes = 1024 * 1024;
  static const maxBase64Characters = ((maxBytes + 2) ~/ 3) * 4;
  // PostgreSQL wraps base64 at 76 columns. CRLF is the longest supported
  // separator: 1 MiB -> 1,398,104 base64 characters + 18,396 * 2.
  static const maxRawBase64Characters =
      maxBase64Characters + ((maxBase64Characters - 1) ~/ 76) * 2;
  static const minDimension = 32;
  static const maxDimension = 2048;
  final Uint8List _bytes;
  final int width, height;
  final String sha256;
  Uint8List get bytes => _bytes.asUnmodifiableView();
  String get base64 => base64Encode(_bytes);

  factory CompanyUploadedSealPng.fromBase64(String value, {String? expectedSha256}) {
    if (value.length > maxRawBase64Characters) {
      throw const FormatException('角印PNGは1MB以下にしてください。');
    }
    var normalizedLength = 0;
    for (var index = 0; index < value.length; index++) {
      final code = value.codeUnitAt(index);
      if (code == 13 || code == 10) {
        continue;
      }
      if (!(code >= 65 && code <= 90 ||
          code >= 97 && code <= 122 ||
          code >= 48 && code <= 57 ||
          code == 43 || code == 47 || code == 61)) {
        throw const FormatException('角印PNGのBase64形式が不正です。');
      }
      if (++normalizedLength > maxBase64Characters) {
        throw const FormatException('角印PNGは1MB以下にしてください。');
      }
    }
    var normalized = value;
    if (normalizedLength != value.length) {
      // Allocate only after both raw and normalized bounds have been checked.
      final characters = Uint8List(normalizedLength);
      var offset = 0;
      for (var index = 0; index < value.length; index++) {
        final code = value.codeUnitAt(index);
        if (code != 13 && code != 10) {
          characters[offset++] = code;
        }
      }
      normalized = ascii.decode(characters);
    }
    final decoded = base64Decode(normalized);
    if (decoded.length > maxBytes) {
      throw const FormatException('角印PNGは1MB以下にしてください。');
    }
    return CompanyUploadedSealPng.fromBytes(decoded, expectedSha256: expectedSha256);
  }

  factory CompanyUploadedSealPng.fromBytes(Uint8List value, {String? expectedSha256}) {
    final bytes = Uint8List.fromList(value);
    if (bytes.length < 57 || bytes.length > maxBytes) {
      throw const FormatException('角印PNGは1MB以下にしてください。');
    }
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    for (var n = 0; n < signature.length; n++) {
      if (bytes[n] != signature[n]) throw const FormatException('PNG画像を選択してください。');
    }
    final data = ByteData.sublistView(bytes);
    var offset = 8, width = 0, height = 0;
    var hasData = false, ended = false;
    while (offset + 12 <= bytes.length) {
      final length = data.getUint32(offset);
      final end = offset + 12 + length;
      if (end > bytes.length) throw const FormatException('PNG画像が途中で切れています。');
      final typeBytes = bytes.sublist(offset + 4, offset + 8);
      if (typeBytes.any((b) => !(b >= 65 && b <= 90 || b >= 97 && b <= 122))) {
        throw const FormatException('PNG画像の形式が不正です。');
      }
      final type = String.fromCharCodes(typeBytes);
      if (_crc32(bytes, offset + 4, offset + 8 + length) != data.getUint32(offset + 8 + length)) {
        throw const FormatException('PNG画像が破損しています。');
      }
      if (offset == 8) {
        if (type != 'IHDR' || length != 13) throw const FormatException('PNG画像の形式が不正です。');
        width = data.getUint32(offset + 8);
        height = data.getUint32(offset + 12);
        if (width < minDimension || width > maxDimension || height < minDimension || height > maxDimension ||
            bytes[offset + 16] != 8 || ![2, 6].contains(bytes[offset + 17]) ||
            bytes[offset + 18] != 0 || bytes[offset + 19] != 0 || bytes[offset + 20] != 0) {
          throw const FormatException('32〜2048pxのRGB/RGBA PNGを選択してください。');
        }
      } else if (type == 'IHDR') {
        throw const FormatException('PNG画像の形式が不正です。');
      }
      if (['acTL', 'fcTL', 'fdAT'].contains(type)) throw const FormatException('静止画PNGを選択してください。');
      if (typeBytes.first >= 65 && typeBytes.first <= 90 && !['IHDR', 'PLTE', 'IDAT', 'IEND'].contains(type)) {
        throw const FormatException('未対応のPNG形式です。');
      }
      if (type == 'IDAT') hasData = true;
      if (type == 'IEND') {
        if (length != 0 || !hasData || end != bytes.length) throw const FormatException('PNG画像の形式が不正です。');
        ended = true;
        break;
      }
      offset = end;
    }
    if (!ended) throw const FormatException('PNG画像が途中で切れています。');
    final hash = crypto.sha256.convert(bytes).toString();
    if (expectedSha256 != null && expectedSha256 != hash) throw const FormatException('保存した角印PNGと画像が一致しません。');
    return CompanyUploadedSealPng._(bytes, width, height, hash);
  }

  static int _crc32(Uint8List bytes, int start, int end) {
    var crc = 0xffffffff;
    for (var n = start; n < end; n++) {
      crc ^= bytes[n];
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc >>> 1) ^ ((crc & 1) != 0 ? 0xedb88320 : 0);
      }
    }
    return (crc ^ 0xffffffff) & 0xffffffff;
  }
}
