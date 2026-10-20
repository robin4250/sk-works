import 'dart:math' as math;
import 'dart:typed_data';

/// Session-local working copy. Editing never mutates the input image.
class SealRgbaImage {
  SealRgbaImage({required this.width, required this.height, required Uint8List pixels})
      : _pixels = Uint8List.fromList(pixels) {
    if (width < 1 || height < 1 || width > maxDimension || height > maxDimension ||
        width * height > maxPixels || pixels.length != width * height * 4) {
      throw const FormatException('画像の大きさを確認できません。');
    }
  }
  static const maxDimension = 2048;
  static const maxPixels = 2048 * 2048;
  final int width, height;
  final Uint8List _pixels;
  Uint8List get pixels => _pixels.asUnmodifiableView();
}

class SealPixelCrop {
  const SealPixelCrop(this.left, this.top, this.right, this.bottom);
  final int left, top, right, bottom;
  int get width => right - left;
  int get height => bottom - top;
  factory SealPixelCrop.full(SealRgbaImage image) => SealPixelCrop(0, 0, image.width, image.height);
  void validate(SealRgbaImage image) {
    if (left < 0 || top < 0 || right > image.width || bottom > image.height || width < 2 || height < 2) {
      throw const FormatException('印影を囲む範囲を選択してください。');
    }
  }
}

class SealImageOptions {
  const SealImageOptions({this.removeWhite = true, this.whiteFloor = 245,
    this.preservePaleRed = true, this.trimTransparent = true});
  final bool removeWhite, preservePaleRed, trimTransparent;
  final int whiteFloor;
}

/// Crops user-selected pixels, removes paper white by alpha matting, and pads
/// proportionally to one fixed 1024px square. Document pt/mm boxes are unchanged.
/// Pale red is never threshold-deleted by default; area resampling preserves
/// subpixel ink coverage instead of selecting a single source pixel.
SealRgbaImage prepareCompanySealImage(SealRgbaImage image, SealPixelCrop crop,
    {SealImageOptions options = const SealImageOptions()}) {
  crop.validate(image);
  if (options.whiteFloor < 180 || options.whiteFloor > 255) {
    throw const FormatException('背景の調整値を確認してください。');
  }
  final original = image.pixels;
  final pixels = Uint8List(crop.width * crop.height * 4);
  var left = crop.width, top = crop.height, right = 0, bottom = 0;
  for (var y = 0; y < crop.height; y++) {
    for (var x = 0; x < crop.width; x++) {
      final source = ((y + crop.top) * image.width + x + crop.left) * 4;
      final target = (y * crop.width + x) * 4;
      final r = original[source], g = original[source + 1], b = original[source + 2];
      var alpha = original[source + 3];
      if (!options.removeWhite) {
        pixels[target] = r; pixels[target + 1] = g; pixels[target + 2] = b;
      } else {
        final low = math.min(r, math.min(g, b));
        final high = math.max(r, math.max(g, b));
        final paleRed = options.preservePaleRed && r > g && r > b;
        if (low >= options.whiteFloor && high - low <= 12 && !paleRed || low == 255) {
          alpha = 0;
        } else {
          final coverage = 255 - low;
          alpha = alpha == 0 ? 0 : math.max(1, (alpha * coverage / 255).round());
          pixels[target] = ((r - low) * 255 / coverage).round().clamp(0, 255).toInt();
          pixels[target + 1] = ((g - low) * 255 / coverage).round().clamp(0, 255).toInt();
          pixels[target + 2] = ((b - low) * 255 / coverage).round().clamp(0, 255).toInt();
        }
      }
      pixels[target + 3] = alpha;
      if (alpha > 0) {
        left = math.min(left, x); top = math.min(top, y);
        right = math.max(right, x + 1); bottom = math.max(bottom, y + 1);
      }
    }
  }
  if (right <= left || bottom <= top) { throw const FormatException('印影が見つかりません。範囲や背景の調整を戻してください。'); }
  if (!options.trimTransparent) { left = 0; top = 0; right = crop.width; bottom = crop.height; }
  final width = right - left, height = bottom - top;
  const size = 1024, content = 960;
  final ratio = content / math.max(width, height);
  final outWidth = math.max(1, (width * ratio).round());
  final outHeight = math.max(1, (height * ratio).round());
  final offsetX = (size - outWidth) ~/ 2, offsetY = (size - outHeight) ~/ 2;
  final output = Uint8List(size * size * 4);
  for (var oy = 0; oy < outHeight; oy++) {
    final sy0 = top + oy * height / outHeight, sy1 = top + (oy + 1) * height / outHeight;
    for (var ox = 0; ox < outWidth; ox++) {
      final sx0 = left + ox * width / outWidth, sx1 = left + (ox + 1) * width / outWidth;
      var coverage = 0.0, red = 0.0, green = 0.0, blue = 0.0;
      for (var sy = sy0.floor(); sy < math.min(bottom, sy1.ceil()); sy++) {
        final wy = math.min(sy1, sy + 1) - math.max(sy0, sy);
        for (var sx = sx0.floor(); sx < math.min(right, sx1.ceil()); sx++) {
          final wx = math.min(sx1, sx + 1) - math.max(sx0, sx);
          final source = (sy * crop.width + sx) * 4;
          final weight = pixels[source + 3] * wx * wy;
          coverage += weight;
          red += pixels[source] * weight; green += pixels[source + 1] * weight; blue += pixels[source + 2] * weight;
        }
      }
      if (coverage > 0) {
        final target = ((oy + offsetY) * size + ox + offsetX) * 4;
        output[target] = (red / coverage).round().clamp(0, 255).toInt();
        output[target + 1] = (green / coverage).round().clamp(0, 255).toInt();
        output[target + 2] = (blue / coverage).round().clamp(0, 255).toInt();
        output[target + 3] = math.max(1, (coverage / ((sx1 - sx0) * (sy1 - sy0))).round()).clamp(0, 255).toInt();
      }
    }
  }
  return SealRgbaImage(width: size, height: size, pixels: output);
}

SealRgbaImage rotateCompanySealImage(SealRgbaImage image, int quarterTurns) {
  final turns = quarterTurns % 4;
  if (turns == 0) { return image; }
  final width = turns.isOdd ? image.height : image.width;
  final height = turns.isOdd ? image.width : image.height;
  final original = image.pixels;
  final pixels = Uint8List(width * height * 4);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final tx = turns == 1 ? image.height - 1 - y : turns == 2 ? image.width - 1 - x : y;
      final ty = turns == 1 ? x : turns == 2 ? image.height - 1 - y : image.width - 1 - x;
      final source = (y * image.width + x) * 4, target = (ty * width + tx) * 4;
      pixels.setRange(target, target + 4, original, source);
    }
  }
  return SealRgbaImage(width: width, height: height, pixels: pixels);
}
