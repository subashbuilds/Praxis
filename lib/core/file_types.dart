import 'dart:convert';

import 'package:crypto/crypto.dart';

/// What a project file actually is. Detection is extension-first because that
/// is cheap when walking a large repository, then falls back to the bytes for
/// files with unfamiliar names (keystores, assets without an extension and
/// binaries produced by new tools).
enum FileKind { text, image, svg, binary }

class FileTypeInfo {
  const FileTypeInfo({
    required this.kind,
    required this.extension,
    required this.label,
    required this.mime,
    required this.known,
  });

  final FileKind kind;
  final String extension;
  final String label;
  final String? mime;

  /// True when the extension (or a well-known filename) made the decision.
  /// Unknown files may still turn out to be text after [classifyFile] sniffs
  /// their bytes.
  final bool known;

  bool get isText => kind == FileKind.text || kind == FileKind.svg;
  bool get isImage => kind == FileKind.image || kind == FileKind.svg;
  bool get isSvg => kind == FileKind.svg;
  bool get isBinary => kind == FileKind.binary || kind == FileKind.image;
}

const _imageMime = <String, String>{
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'bmp': 'image/bmp',
  'ico': 'image/x-icon',
  'avif': 'image/avif',
  'heic': 'image/heic',
  'heif': 'image/heif',
  'tif': 'image/tiff',
  'tiff': 'image/tiff',
  'svg': 'image/svg+xml',
};

const _binaryMime = <String, String>{
  'pdf': 'application/pdf',
  'zip': 'application/zip',
  'gz': 'application/gzip',
  'tar': 'application/x-tar',
  'bz2': 'application/x-bzip2',
  'xz': 'application/x-xz',
  '7z': 'application/x-7z-compressed',
  'rar': 'application/vnd.rar',
  'apk': 'application/vnd.android.package-archive',
  'aab': 'application/octet-stream',
  'jar': 'application/java-archive',
  'dex': 'application/octet-stream',
  'class': 'application/java-vm',
  'so': 'application/octet-stream',
  'wasm': 'application/wasm',
  'mp3': 'audio/mpeg',
  'wav': 'audio/wav',
  'ogg': 'audio/ogg',
  'oga': 'audio/ogg',
  'opus': 'audio/opus',
  'flac': 'audio/flac',
  'm4a': 'audio/mp4',
  'aac': 'audio/aac',
  'mp4': 'video/mp4',
  'm4v': 'video/x-m4v',
  'mov': 'video/quicktime',
  'webm': 'video/webm',
  'mkv': 'video/x-matroska',
  'avi': 'video/x-msvideo',
  '3gp': 'video/3gpp',
  'ttf': 'font/ttf',
  'otf': 'font/otf',
  'woff': 'font/woff',
  'woff2': 'font/woff2',
  'eot': 'application/vnd.ms-fontobject',
  'keystore': 'application/octet-stream',
  'jks': 'application/octet-stream',
  'p12': 'application/x-pkcs12',
  'pfx': 'application/x-pkcs12',
  'der': 'application/x-x509-ca-cert',
  'sqlite': 'application/vnd.sqlite3',
  'sqlite3': 'application/vnd.sqlite3',
  'db': 'application/vnd.sqlite3',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx':
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'epub': 'application/epub+zip',
  'iso': 'application/x-iso9660-image',
  'dmg': 'application/x-apple-diskimage',
  'exe': 'application/vnd.microsoft.portable-executable',
  'dll': 'application/vnd.microsoft.portable-executable',
  'msi': 'application/x-msi',
  'o': 'application/octet-stream',
  'a': 'application/octet-stream',
  'pyc': 'application/x-python-code',
  'bin': 'application/octet-stream',
  'dat': 'application/octet-stream',
};

const _textExtensions = <String>{
  'md',
  'markdown',
  'mdown',
  'txt',
  'text',
  'dart',
  'py',
  'pyi',
  'js',
  'mjs',
  'cjs',
  'jsx',
  'ts',
  'tsx',
  'html',
  'htm',
  'xhtml',
  'css',
  'scss',
  'sass',
  'less',
  'json',
  'jsonc',
  'json5',
  'yaml',
  'yml',
  'toml',
  'ini',
  'cfg',
  'conf',
  'env',
  'properties',
  'sh',
  'bash',
  'zsh',
  'fish',
  'ps1',
  'bat',
  'cmd',
  'sql',
  'graphql',
  'gql',
  'kt',
  'kts',
  'java',
  'gradle',
  'xml',
  'plist',
  'csv',
  'tsv',
  'log',
  'lock',
  'gitignore',
  'gitattributes',
  'dockerignore',
  'editorconfig',
  'swift',
  'c',
  'h',
  'cc',
  'cpp',
  'cxx',
  'hpp',
  'hh',
  'cs',
  'go',
  'rs',
  'rb',
  'php',
  'lua',
  'r',
  'tex',
  'proto',
  'vue',
  'svelte',
  'astro',
  'ex',
  'exs',
  'erl',
  'hrl',
  'clj',
  'cljs',
  'scala',
  'groovy',
  'fs',
  'fsx',
  'vb',
  'asm',
  's',
  'cmake',
  'make',
  'mk',
  'diff',
  'patch',
  'pem',
  'crt',
  'cer',
  'key',
  'pubspec',
  'sum',
};

final _binaryExtensions = <String>{
  ..._imageMime.keys,
  ..._binaryMime.keys,
  'psd',
  'ai',
  'sketch',
  'fig',
  'blend',
  'fbx',
  'obj',
  'glb',
  'gltf',
  'tga',
  'raw',
  'cr2',
  'nef',
  'arw',
  'heics',
  'jfif',
  'cur',
  'icns',
  'otc',
  'ttc',
  'pak',
  'rlib',
  'dylib',
  'lib',
  'pdb',
  'node',
  'swo',
  'swp',
  'ds_store',
};

const _wellKnownTextNames = <String>{
  'readme',
  'license',
  'licence',
  'copying',
  'notice',
  'authors',
  'contributors',
  'changelog',
  'changes',
  'makefile',
  'dockerfile',
  'procfile',
  'gemfile',
  'rakefile',
  'podfile',
  'brewfile',
  'vagrantfile',
  'justfile',
  'taskfile',
  'jenkinsfile',
  'gradlew',
  'mvnw',
  'podspec',
};

String extensionOf(String path) {
  final name = path.split('/').last;
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}

String baseNameOf(String path) => path.split('/').last;

/// Classifies a file by name and, when supplied, its leading bytes. `svg` is
/// deliberately both image-like and editable text.
FileTypeInfo classifyFile(String path, {List<int>? bytes}) {
  final extension = extensionOf(path);
  final name = baseNameOf(path).toLowerCase();
  final stem =
      name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;

  if (extension == 'svg' || extension == 'svgz') {
    return FileTypeInfo(
      kind: FileKind.svg,
      extension: extension,
      label: 'SVG',
      mime: 'image/svg+xml',
      known: true,
    );
  }
  if (_imageMime.containsKey(extension)) {
    return FileTypeInfo(
      kind: FileKind.image,
      extension: extension,
      label: extension.toUpperCase(),
      mime: _imageMime[extension],
      known: true,
    );
  }
  if (_binaryExtensions.contains(extension)) {
    return FileTypeInfo(
      kind: FileKind.binary,
      extension: extension,
      label: extension.toUpperCase(),
      mime: _binaryMime[extension],
      known: true,
    );
  }
  if (_textExtensions.contains(extension) ||
      _wellKnownTextNames.contains(name) ||
      _wellKnownTextNames.contains(stem)) {
    return FileTypeInfo(
      kind: FileKind.text,
      extension: extension,
      label: _label(extension, name),
      mime: _mimeForText(extension),
      known: true,
    );
  }

  // An unfamiliar extension or no extension at all: inspect what is on disk.
  if (bytes != null) {
    final text = decodeUtf8(bytes, allowEmpty: true);
    if (text != null && !_containsNul(bytes)) {
      return FileTypeInfo(
        kind: FileKind.text,
        extension: extension,
        label: _label(extension, name),
        mime: _mimeForText(extension),
        known: false,
      );
    }
    return FileTypeInfo(
      kind: FileKind.binary,
      extension: extension,
      label: _label(extension, name),
      mime: _binaryMime[extension] ?? 'application/octet-stream',
      known: false,
    );
  }

  return FileTypeInfo(
    kind: FileKind.text,
    extension: extension,
    label: _label(extension, name),
    mime: _mimeForText(extension),
    known: false,
  );
}

String _label(String extension, String name) {
  if (extension.isNotEmpty) return extension.toUpperCase();
  if (name.isEmpty) return 'FILE';
  return name.length <= 8 ? name.toUpperCase() : 'FILE';
}

String? _mimeForText(String extension) => switch (extension) {
      'md' || 'markdown' || 'mdown' => 'text/markdown',
      'html' || 'htm' || 'xhtml' => 'text/html',
      'css' || 'scss' || 'sass' || 'less' => 'text/css',
      'json' || 'jsonc' || 'json5' => 'application/json',
      'xml' || 'plist' || 'svg' => 'application/xml',
      'yaml' || 'yml' => 'application/yaml',
      'csv' => 'text/csv',
      _ => 'text/plain',
    };

bool _containsNul(List<int> bytes) {
  final end = bytes.length > 8192 ? 8192 : bytes.length;
  for (var i = 0; i < end; i++) {
    if (bytes[i] == 0) return true;
  }
  return false;
}

/// Strict UTF-8 decode. Returns null for invalid bytes rather than replacing
/// them, so a binary file can never be silently corrupted by a text editor.
String? decodeUtf8(List<int> bytes, {bool allowEmpty = false}) {
  if (!allowEmpty && bytes.isEmpty) return '';
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return null;
  }
}

bool looksLikeBinary(List<int> bytes) {
  if (_containsNul(bytes)) return true;
  final sample = bytes.length > 8192 ? bytes.sublist(0, 8192) : bytes;
  return decodeUtf8(sample, allowEmpty: true) == null;
}

/// Git's object id for a file. It is SHA-1 over `blob <size>\0<bytes>`, which
/// lets a local file be compared with the `sha` GitHub returns in a tree
/// without downloading every remote blob.
String gitBlobSha(List<int> bytes) {
  final header = utf8.encode('blob ${bytes.length}\u0000');
  return sha1.convert(<int>[...header, ...bytes]).toString();
}

String humanFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(bytes < 10240 ? 1 : 0)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
