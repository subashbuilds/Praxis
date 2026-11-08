import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/tokens.dart';

/// Network image renderer for README previews. Shields badges are SVG and are
/// kept small; content images are bounded so a wide asset cannot push the
/// document sideways.
class ReadmeImage extends StatelessWidget {
  const ReadmeImage({
    super.key,
    required this.uri,
    this.alt,
    this.title,
  });

  final Uri uri;
  final String? alt;
  final String? title;

  bool get _isBadge =>
      uri.host.contains('shields.io') ||
      uri.host.contains('badge') ||
      (alt?.toLowerCase().contains('badge') ?? false);

  bool get _isSvg =>
      uri.path.toLowerCase().endsWith('.svg') ||
      uri.host.contains('shields.io');

  @override
  Widget build(BuildContext context) {
    final label = (alt == null || alt!.trim().isEmpty) ? 'README image' : alt!;
    if (_isSvg) {
      return Padding(
        padding: const EdgeInsets.only(right: 5, bottom: 3),
        child: SvgPicture.network(
          uri.toString(),
          height: _isBadge ? 20 : 160,
          fit: BoxFit.contain,
          placeholderBuilder: (_) => SizedBox(
            height: _isBadge ? 20 : 80,
            width: _isBadge ? 100 : 180,
            child: Center(
              child: SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: Pal.textDim,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Image.network(
        uri.toString(),
        height: _isBadge ? 20 : null,
        fit: BoxFit.contain,
        semanticLabel: label,
        errorBuilder: (_, __, ___) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined, size: 15, color: Pal.textDim),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  title?.isNotEmpty == true ? title! : label,
                  style: Txt.meta.copyWith(fontSize: 10),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
