import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../ai/ai_models.dart';

/// Prepares a photo for on-device analysis and storage.
///
/// * fixes EXIF rotation (phones store portrait shots rotated),
/// * downsizes so the vision encoder and RAM aren't wasted on 12 MP originals,
/// * re-encodes as JPEG (drops metadata such as GPS location - a privacy win).
///
/// Heavy work runs in a background isolate so the UI never janks.
class ImagePreprocessor {
  const ImagePreprocessor._();

  static const int defaultMaxSide = 896;
  static const int defaultQuality = 85;

  static Future<Uint8List> prepare(
    Uint8List bytes, {
    int maxSide = defaultMaxSide,
    int quality = defaultQuality,
  }) async {
    final result = await Isolate.run(() => process(bytes, maxSide: maxSide, quality: quality));
    if (result == null) {
      throw AiException('That file could not be read as a photo. Please try another.');
    }
    return result;
  }

  /// Synchronous core (also used directly by tests). Null if not an image.
  static Uint8List? process(Uint8List bytes, {int maxSide = defaultMaxSide, int quality = defaultQuality}) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    var image = img.bakeOrientation(decoded);
    final longest = image.width > image.height ? image.width : image.height;
    if (longest > maxSide) {
      image = image.width >= image.height
          ? img.copyResize(image, width: maxSide, interpolation: img.Interpolation.average)
          : img.copyResize(image, height: maxSide, interpolation: img.Interpolation.average);
    }
    return Uint8List.fromList(img.encodeJpg(image, quality: quality));
  }
}
