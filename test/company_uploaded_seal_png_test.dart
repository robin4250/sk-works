import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/company_uploaded_seal_png.dart';

void main() {
  const png = 'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAALUlEQVR4nO3OIQEAAAwEoetf+hdjBoWlVat9mYCAgICAgICAgICAgICAwHfgAIP/+kx2iamjAAAAAElFTkSuQmCC';
  test('valid alpha PNG is copied and content hash remains stable', () {
    final input = base64Decode(png);
    final image = CompanyUploadedSealPng.fromBytes(input);
    expect(image.width, 32); expect(image.height, 32);
    expect(image.sha256, '30ca1a5ef40b92ff14e0d5f9b4a2a9930ae2013a6cd9d7c4b636e3e70daa58fc');
    input[0] = 0;
    expect(image.base64, png);
    expect(() => image.bytes[0] = 0, throwsUnsupportedError);
  });
  for (final separator in ['\n', '\r\n', '\r']) {
    test('PostgreSQL 76-column base64 accepts ${separator.codeUnits}', () {
      final wrapped = _wrap76(png, separator);
      final original = wrapped;
      final image = CompanyUploadedSealPng.fromBase64(
        wrapped,
        expectedSha256:
            '30ca1a5ef40b92ff14e0d5f9b4a2a9930ae2013a6cd9d7c4b636e3e70daa58fc',
      );
      expect(wrapped, original);
      expect(image.base64, png);
      expect(image.width, 32);
      expect(image.height, 32);
      expect(image.bytes, base64Decode(png));
      expect(() => image.bytes[0] = 0, throwsUnsupportedError);
    });
  }
  test('only CR and LF are removed; other whitespace and alternate encodings fail', () {
    for (final invalid in [' ', '\t', '\u000b', '\u000c', '\u00a0', '%41', '-', '_']) {
      final value = '${png.substring(0, 20)}$invalid${png.substring(20)}';
      expect(
        () => CompanyUploadedSealPng.fromBase64(value),
        throwsFormatException,
        reason: invalid.codeUnits.toString(),
      );
    }
    expect(
      () => CompanyUploadedSealPng.fromBase64(
        png.replaceAll('+', '-').replaceAll('/', '_'),
      ),
      throwsFormatException,
    );
    for (final invalid in ['=$png', '$png=', '${png.substring(0, 20)}=${png.substring(20)}']) {
      expect(
        () => CompanyUploadedSealPng.fromBase64(_wrap76(invalid, '\r\n')),
        throwsFormatException,
      );
    }
  });
  test('wrapped data still rejects SHA mismatch and corrupt PNG CRC', () {
    expect(
      () => CompanyUploadedSealPng.fromBase64(
        _wrap76(png, '\r\n'),
        expectedSha256: 'wrong',
      ),
      throwsFormatException,
    );
    final corrupt = base64Decode(png);
    corrupt[50] ^= 1;
    expect(
      () => CompanyUploadedSealPng.fromBase64(
        _wrap76(base64Encode(corrupt), '\n'),
      ),
      throwsFormatException,
    );
  });
  test('a full 1 MiB PNG with 76-column CRLF reaches the exact raw bound', () {
    final input = _maximumPng(png);
    final encoded = base64Encode(input);
    final wrapped = _wrap76(encoded, '\r\n');
    expect(input.length, 1048576);
    expect(encoded.length, 1398104);
    expect(wrapped.length, 1434896);
    const hash = '5f92af7cdc287da4dda4728edb9910da2cbd16d1ed336d99e8532662c1f60f8b';
    final image = CompanyUploadedSealPng.fromBase64(
      wrapped,
      expectedSha256: hash,
    );
    expect(image.bytes, input);
    expect(image.sha256, hash);
    expect(image.base64, encoded);
    expect(wrapped.length, 1434896);
  });
  test('raw, normalized and decoded limits are independent', () {
    final tooLarge = isA<FormatException>().having(
      (error) => error.message,
      'size error',
      contains('1MB'),
    );
    expect(
      () => CompanyUploadedSealPng.fromBase64('\n' * 1434897),
      throwsA(tooLarge),
    );
    expect(
      () => CompanyUploadedSealPng.fromBase64('A' * 1398108),
      throwsA(tooLarge),
    );
    // One decoded byte over 1 MiB has the same encoded length as the maximum.
    final oneByteOver = base64Encode(Uint8List(1048577));
    expect(oneByteOver.length, 1398104);
    expect(
      () => CompanyUploadedSealPng.fromBase64(oneByteOver),
      throwsA(tooLarge),
    );
  });
  test('invalid image, truncated data, corrupt CRC, excessive bytes and hash mismatch fail', () {
    expect(() => CompanyUploadedSealPng.fromBytes(Uint8List(70)), throwsFormatException);
    expect(() => CompanyUploadedSealPng.fromBytes(base64Decode(png).sublist(0, 70)), throwsFormatException);
    final corrupt = base64Decode(png);
    corrupt[50] ^= 1;
    expect(() => CompanyUploadedSealPng.fromBytes(corrupt), throwsFormatException);
    expect(() => CompanyUploadedSealPng.fromBytes(Uint8List(CompanyUploadedSealPng.maxBytes + 1)), throwsFormatException);
    expect(() => CompanyUploadedSealPng.fromBase64(png, expectedSha256: 'wrong'), throwsFormatException);
  });
}

String _wrap76(String value, String separator) {
  final buffer = StringBuffer();
  for (var offset = 0; offset < value.length; offset += 76) {
    if (offset > 0) {
      buffer.write(separator);
    }
    final end = offset + 76 < value.length ? offset + 76 : value.length;
    buffer.write(value.substring(offset, end));
  }
  return buffer.toString();
}

Uint8List _maximumPng(String png) {
  final original = base64Decode(png);
  final result = Uint8List(1048576);
  final offset = original.length - 12;
  final paddingLength = result.length - original.length - 12;
  result.setRange(0, offset, original);
  final data = ByteData.sublistView(result);
  data.setUint32(offset, paddingLength);
  // Unknown ancillary vpAg chunk: zero payload, independent zlib CRC fixture.
  result.setRange(offset + 4, offset + 8, const [118, 112, 65, 103]);
  data.setUint32(offset + 8 + paddingLength, 0xe2d78d2b);
  result.setRange(result.length - 12, result.length, original.sublist(offset));
  return result;
}
