import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/tokens.dart';

/// A compact file-tree glyph. It uses brand marks where a language has one and
/// falls back to a tinted initial so unfamiliar files still scan quickly.
class FileGlyph extends StatelessWidget {
  const FileGlyph({
    super.key,
    required this.name,
    this.isDir = false,
    this.expanded = false,
    this.size = 17,
  });

  final String name;
  final bool isDir;
  final bool expanded;
  final double size;

  static const _assets = 'assets/icons/files/';

  String get _lower => name.toLowerCase();
  String get _extension {
    final dot = _lower.lastIndexOf('.');
    if (dot <= 0 || dot == _lower.length - 1) return '';
    return _lower.substring(dot + 1);
  }

  String? get _asset {
    if (_lower == 'dockerfile' || _lower.startsWith('dockerfile.')) {
      return '${_assets}docker.svg';
    }
    if (_lower == 'package.json' || _lower == 'package-lock.json') {
      return '${_assets}nodejs.svg';
    }
    if (_lower == 'pubspec.yaml' || _lower == 'pubspec.lock') {
      return '${_assets}dart.svg';
    }
    if (_lower.endsWith('.gitignore') ||
        _lower.endsWith('.gitattributes') ||
        _lower.endsWith('.gitmodules') ||
        _lower == '.gitconfig') {
      return '${_assets}git.svg';
    }
    if (_lower.startsWith('readme')) return '${_assets}markdown.svg';
    if (_lower.startsWith('license') ||
        _lower.startsWith('licence') ||
        _lower.startsWith('copying')) {
      return null;
    }
    return switch (_extension) {
      'dart' => '${_assets}dart.svg',
      'py' || 'pyi' => '${_assets}python.svg',
      'js' || 'jsx' || 'mjs' || 'cjs' => '${_assets}javascript.svg',
      'ts' || 'tsx' || 'mts' || 'cts' => '${_assets}typescript.svg',
      'md' || 'markdown' || 'mdx' => '${_assets}markdown.svg',
      'yaml' || 'yml' => '${_assets}yaml.svg',
      'json' || 'jsonc' => '${_assets}json.svg',
      'html' || 'htm' || 'xhtml' => '${_assets}html5.svg',
      'css' || 'scss' || 'sass' || 'less' => '${_assets}css.svg',
      'php' => '${_assets}php.svg',
      'go' => '${_assets}go.svg',
      'rs' => '${_assets}rust.svg',
      'java' => '${_assets}java.svg',
      'kt' || 'kts' => '${_assets}kotlin.svg',
      'swift' => '${_assets}swift.svg',
      'rb' || 'erb' => '${_assets}ruby.svg',
      'c' || 'h' => '${_assets}c.svg',
      'cpp' || 'cc' || 'cxx' || 'hpp' => '${_assets}cplusplus.svg',
      'sh' || 'bash' || 'zsh' || 'fish' => '${_assets}gnubash.svg',
      'toml' || 'ini' || 'conf' || 'env' => null,
      _ => null,
    };
  }

  Color get _folderColor {
    if (_lower == '.github') return Pal.text;
    if (_lower == '.polydev' || _lower == '.praxis') return Pal.ember;
    if (_lower == 'test' ||
        _lower == 'tests' ||
        _lower == 'spec' ||
        _lower == '__tests__') {
      return Pal.mint;
    }
    if (_lower == 'lib' || _lower == 'src' || _lower == 'app') {
      return Pal.sky;
    }
    if (_lower == 'assets' ||
        _lower == 'public' ||
        _lower == 'static' ||
        _lower == 'images') {
      return const Color(0xFFB98AEA);
    }
    return Pal.amber;
  }

  IconData? get _fallbackIcon {
    if (_lower.startsWith('license') ||
        _lower.startsWith('licence') ||
        _lower.startsWith('copying')) {
      return Icons.balance_rounded;
    }
    if (_lower == '.env' || _lower == '.envrc' || _lower.startsWith('.env.')) {
      return Icons.terminal_rounded;
    }
    if (_lower.endsWith('.lock') ||
        _lower == 'pubspec.lock' ||
        _lower == 'yarn.lock') {
      return Icons.lock_outline_rounded;
    }
    if (_lower.endsWith('.png') ||
        _lower.endsWith('.jpg') ||
        _lower.endsWith('.jpeg') ||
        _lower.endsWith('.gif') ||
        _lower.endsWith('.webp') ||
        _lower.endsWith('.svg')) {
      return Icons.image_outlined;
    }
    if (_lower.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
    if (_lower.endsWith('.zip') ||
        _lower.endsWith('.gz') ||
        _lower.endsWith('.tar') ||
        _lower.endsWith('.7z')) {
      return Icons.folder_zip_outlined;
    }
    if (_lower.endsWith('.toml') ||
        _lower.endsWith('.ini') ||
        _lower.endsWith('.conf')) {
      return Icons.tune_rounded;
    }
    return null;
  }

  Color get _assetColor {
    if (_lower == 'dockerfile' || _lower.startsWith('dockerfile.')) {
      return const Color(0xFF2496ED);
    }
    return switch (_extension) {
      'dart' => const Color(0xFF40C4FF),
      'py' || 'pyi' => const Color(0xFFFFD54F),
      'js' || 'jsx' || 'mjs' || 'cjs' => const Color(0xFFF7DF1E),
      'ts' || 'tsx' || 'mts' || 'cts' => const Color(0xFF42A5F5),
      'md' || 'markdown' || 'mdx' => const Color(0xFF90CAF9),
      'yaml' || 'yml' => const Color(0xFFF06292),
      'json' || 'jsonc' => const Color(0xFFFFB74D),
      'html' || 'htm' || 'xhtml' => const Color(0xFFFF7043),
      'css' || 'scss' || 'sass' || 'less' => const Color(0xFF64B5F6),
      'php' => const Color(0xFF9575CD),
      'go' => const Color(0xFF4DD0E1),
      'rs' => const Color(0xFFFF8A65),
      'java' => const Color(0xFFEF9A9A),
      'kt' || 'kts' => const Color(0xFFBA68C8),
      'swift' => const Color(0xFFFFAB91),
      'rb' || 'erb' => const Color(0xFFE57373),
      'c' || 'h' => const Color(0xFF90A4AE),
      'cpp' || 'cc' || 'cxx' || 'hpp' => const Color(0xFF7986CB),
      'sh' || 'bash' || 'zsh' || 'fish' => const Color(0xFF81C784),
      _ => Pal.text,
    };
  }

  Color get _fallbackColor {
    if (_lower.startsWith('license') || _lower.startsWith('licence')) {
      return Pal.amber;
    }
    if (_lower.endsWith('.lock') || _lower == 'yarn.lock') return Pal.amber;
    if (_lower.startsWith('.env')) return Pal.mint;
    return Pal.textDim;
  }

  @override
  Widget build(BuildContext context) {
    if (isDir) {
      if (_lower == '.github') {
        return _assetTile('${_assets}github.svg', Pal.text, size);
      }
      return Container(
        width: size + 3,
        height: size + 3,
        decoration: BoxDecoration(
          color: _folderColor.withOpacity(0.12),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: _folderColor.withOpacity(0.24)),
        ),
        child: Icon(
          expanded ? Icons.folder_open_rounded : Icons.folder_rounded,
          size: size - 2,
          color: _folderColor,
        ),
      );
    }

    final asset = _asset;
    if (asset != null) return _assetTile(asset, _assetColor, size);
    final icon = _fallbackIcon;
    if (icon != null) {
      return Icon(icon, size: size, color: _fallbackColor);
    }
    final ext = _extension;
    if (ext.isNotEmpty) {
      return _initial(ext.length <= 3
          ? ext.toUpperCase()
          : ext.substring(0, 3).toUpperCase());
    }
    return Icon(Icons.insert_drive_file_outlined,
        size: size, color: Pal.textDim);
  }

  Widget _assetTile(String asset, Color color, double size) {
    return Container(
      width: size + 2,
      height: size + 2,
      padding: EdgeInsets.all(size * 0.10),
      decoration: BoxDecoration(
        color: Pal.raised,
        borderRadius: BorderRadius.circular(4),
      ),
      child: SvgPicture.asset(
        asset,
        fit: BoxFit.contain,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      ),
    );
  }

  Widget _initial(String text) {
    return Container(
      width: size + 2,
      height: size + 2,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Pal.raised,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Pal.line),
      ),
      child: Text(
        text,
        style: Txt.meta.copyWith(
          fontSize: size * 0.40,
          height: 1,
          color: Pal.textMuted,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
