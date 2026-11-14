import 'dart:io';

import 'package:flutter/widgets.dart';

/// The only sanctioned way for themes to draw local media.
///
/// Decodes at exactly the rendered size (logical size × devicePixelRatio) via
/// [ResizeImage], so a 4K cover shown at 160dp costs ~0.4 MB instead of 33 MB.
/// Callers must pass the real on-screen [width]/[height].
class BudgetImage extends StatelessWidget {
  const BudgetImage.file(
    this.path, {
    super.key,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.filterQuality = FilterQuality.low,
  }) : assert(
         width > 0 && height > 0 && width < 4096 && height < 4096,
         'BudgetImage needs a real bounded size',
       );

  final String? path;
  final double width;
  final double height;
  final BoxFit fit;
  final Widget? placeholder;
  final FilterQuality filterQuality;

  /// Physical decode size for a logical extent.
  static int decodeExtent(double logical, double devicePixelRatio) =>
      (logical * devicePixelRatio).ceil().clamp(1, 4096);

  @override
  Widget build(BuildContext context) {
    final fallback = SizedBox(width: width, height: height, child: placeholder);
    final p = path;
    if (p == null || p.isEmpty) return fallback;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final ImageProvider provider = p.startsWith('assets/')
        ? AssetImage(p)
        : FileImage(File(p));
    return Image(
      image: ResizeImage(
        provider,
        width: decodeExtent(width, dpr),
        height: decodeExtent(height, dpr),
        policy: ResizeImagePolicy.fit,
        allowUpscaling: false,
      ),
      width: width,
      height: height,
      fit: fit,
      filterQuality: filterQuality,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}
