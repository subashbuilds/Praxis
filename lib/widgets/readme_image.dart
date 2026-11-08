import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/tokens.dart';

typedef ReadmeLocalImageLoader = Future<Uint8List?> Function(Uri uri);

/// Network or project-local image renderer for README previews. Shields and
/// workflow badges are kept small; content images are bounded so a wide asset
/// cannot push the document sideways.
class ReadmeImage extends StatefulWidget {
  const ReadmeImage({
    super.key,
    required this.uri,
    this.alt,
    this.title,
    this.loadLocal,
  });

  final Uri uri;
  final String? alt;
  final String? title;

  /// Loads a relative image from the project. Returns null when it is missing.
  final ReadmeLocalImageLoader? loadLocal;

  @override
  State<ReadmeImage> createState() => _ReadmeImageState();
}

class _ReadmeImageState extends State<ReadmeImage> {
  Future<Uint8List?>? _localBytes;

  bool get _isLocal => widget.uri.scheme.isEmpty && !widget.uri.hasAuthority;

  bool get _isBadge =>
      widget.uri.host.contains('shields.io') ||
      widget.uri.host.contains('badge') ||
      widget.uri.path.toLowerCase().endsWith('badge.svg') ||
      (widget.alt?.toLowerCase().contains('badge') ?? false);

  bool get _isSvg =>
      widget.uri.path.toLowerCase().endsWith('.svg') ||
      widget.uri.host.contains('shields.io');

  String get _label => (widget.alt == null || widget.alt!.trim().isEmpty)
      ? 'README image'
      : widget.alt!;

  @override
  void initState() {
    super.initState();
    _resolveLocal();
  }

  @override
  void didUpdateWidget(covariant ReadmeImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri) _resolveLocal();
  }

  void _resolveLocal() {
    final loader = widget.loadLocal;
    if (!_isLocal || loader == null) {
      _localBytes = null;
      return;
    }
    _localBytes = loader(widget.uri).catchError((Object _) => null);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLocal && _localBytes != null) {
      return FutureBuilder<Uint8List?>(
        future: _localBytes,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _loading();
          }
          final bytes = snapshot.data;
          if (bytes == null || bytes.isEmpty) return _error();
          if (_isSvg && _looksLikeSvg(bytes)) {
            return Padding(
              padding: const EdgeInsets.only(right: 5, bottom: 3),
              child: SvgPicture.memory(
                bytes,
                height: _isBadge ? 20 : 160,
                fit: BoxFit.contain,
              ),
            );
          }
          return ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Image.memory(
              bytes,
              height: _isBadge ? 20 : null,
              fit: BoxFit.contain,
              semanticLabel: _label,
              errorBuilder: (_, __, ___) => _error(),
            ),
          );
        },
      );
    }

    if (_isSvg) {
      return Padding(
        padding: const EdgeInsets.only(right: 5, bottom: 3),
        child: SvgPicture.network(
          widget.uri.toString(),
          height: _isBadge ? 20 : 160,
          fit: BoxFit.contain,
          placeholderBuilder: (_) => _loading(),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Image.network(
        widget.uri.toString(),
        height: _isBadge ? 20 : null,
        fit: BoxFit.contain,
        semanticLabel: _label,
        errorBuilder: (_, __, ___) => _error(),
      ),
    );
  }

  Widget _loading() {
    return Padding(
      padding: const EdgeInsets.only(right: 5, bottom: 3),
      child: SizedBox(
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
    );
  }

  Widget _error() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, size: 15, color: Pal.textDim),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              widget.title?.isNotEmpty == true ? widget.title! : _label,
              style: Txt.meta.copyWith(fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

bool _looksLikeSvg(Uint8List bytes) {
  try {
    final head = utf8.decode(bytes.take(1024).toList(), allowMalformed: true);
    return head.toLowerCase().contains('<svg');
  } catch (_) {
    return false;
  }
}
