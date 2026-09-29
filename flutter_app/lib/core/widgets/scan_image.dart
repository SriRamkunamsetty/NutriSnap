import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_colors.dart';

/// Shows a photo stored in the app's private folder, with a neutral
/// placeholder when there is no photo (or it was purged).
class ScanImage extends StatelessWidget {
  const ScanImage({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.cacheWidth,
  });

  final String? path;
  final BoxFit fit;

  /// Decode at a reduced size to keep list scrolling smooth and memory low.
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    final p = path;
    if (p == null || p.isEmpty) return _placeholder();
    return Image.file(
      File(p),
      fit: fit,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }

  Widget _placeholder() => Container(
        color: AppColors.border.withValues(alpha: 0.4),
        alignment: Alignment.center,
        child: const Icon(LucideIcons.image, color: AppColors.textTertiary),
      );
}
