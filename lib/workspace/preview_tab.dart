import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

class PreviewTab extends StatefulWidget {
  const PreviewTab({super.key, required this.project});

  final Project project;

  @override
  State<PreviewTab> createState() => _PreviewTabState();
}

class _PreviewTabState extends State<PreviewTab> {
  WebViewController? _controller;
  HttpServer? _server;
  String? _path;
  String? _root;
  int? _port;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _server?.close(force: true);
    super.dispose();
  }

  Future<void> _stopServer() async {
    await _server?.close(force: true);
    _server = null;
    _port = null;
  }

  String _rootFor(String filePath) {
    final normalized = filePath.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    return slash < 0 ? normalized : normalized.substring(0, slash);
  }

  Future<void> _load() async {
    final state = AppScope.of(context);
    try {
      await _stopServer();
      final path = await state.previewFile(widget.project);
      if (!mounted) return;
      if (path == null) {
        setState(() {
          _loading = false;
          _path = null;
          _controller = null;
          _error = null;
        });
        return;
      }
      final normalized = path.replaceAll('\\', '/');
      final entry = normalized.split('/').last;
      final root = _rootFor(path);
      HttpServer? server;
      try {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) => _serve(request, root, entry));
      } catch (_) {
        server = null;
      }
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Pal.terminal);
      if (server == null) {
        await controller.loadFile(path);
      } else {
        await controller.loadRequest(
          Uri.parse('http://127.0.0.1:${server.port}/'),
        );
      }
      if (!mounted) {
        await server?.close(force: true);
        return;
      }
      _server = server;
      setState(() {
        _controller = controller;
        _path = path;
        _root = root;
        _port = server?.port;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      await _stopServer();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _serve(HttpRequest request, String root, String entry) async {
    try {
      var path = Uri.decodeComponent(request.uri.path);
      if (path == '/' || path.isEmpty) path = '/$entry';
      final segments = path.split('/').where((part) => part.isNotEmpty);
      if (segments.any((part) => part == '..' || part == '.')) {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        return;
      }
      final candidate = File('$root/${segments.join('/')}');
      final fallback = File('$root/$entry');
      final file = await candidate.exists() ? candidate : fallback;
      if (!await file.exists()) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      request.response.headers.contentType = _contentType(file.path);
      request.response.headers.set('Cache-Control', 'no-store');
      await request.response.addStream(file.openRead());
      await request.response.close();
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  ContentType _contentType(String path) {
    final extension = path.toLowerCase().split('.').last;
    return switch (extension) {
      'html' || 'htm' => ContentType.html,
      'css' => ContentType('text', 'css', charset: 'utf-8'),
      'js' || 'mjs' => ContentType('text', 'javascript', charset: 'utf-8'),
      'json' => ContentType.json,
      'svg' => ContentType('image', 'svg+xml', charset: 'utf-8'),
      'png' => ContentType('image', 'png'),
      'jpg' || 'jpeg' => ContentType('image', 'jpeg'),
      'gif' => ContentType('image', 'gif'),
      'webp' => ContentType('image', 'webp'),
      'ico' => ContentType('image', 'x-icon'),
      'woff' => ContentType('font', 'woff'),
      'woff2' => ContentType('font', 'woff2'),
      'ttf' => ContentType('font', 'ttf'),
      'otf' => ContentType('font', 'otf'),
      'wasm' => ContentType('application', 'wasm'),
      'map' => ContentType.json,
      'txt' || 'md' => ContentType.text,
      _ => ContentType.binary,
    };
  }

  Future<void> _createIndex() async {
    await AppScope.of(context)
        .createFile(widget.project, 'index.html', content: kIndexHtml);
    await _load();
  }

  @override
  Widget build(BuildContext context) => _body();

  Widget _body() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final controller = _controller;
    if (controller == null) {
      return ListView(
        padding: const EdgeInsets.all(Sp.page),
        children: [
          EmptyState(
            icon: Icons.web_asset_off_rounded,
            title: _error == null ? 'No page to preview' : 'Preview failed',
            body: _error ??
                'The preview loads a local HTML file. Add an index.html (or any '
                    '.html file) to this project and it will render here. '
                    'Built output in dist/, build/, build/web/ and out/ is '
                    'detected automatically.',
          ),
          const SizedBox(height: Sp.x4),
          EmberButton(
            label: 'Create index.html',
            icon: Icons.add_rounded,
            onTap: _createIndex,
          ),
          const SizedBox(height: Sp.x3),
          Text(
            'Preview renders files from this device. Nothing is uploaded.',
            style: Txt.meta,
          ),
        ],
      );
    }

    final folder = _root?.replaceAll('\\', '/');
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x2, Sp.x2, Sp.x2),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Pal.line)),
          ),
          child: Row(
            children: [
              Icon(Icons.lock_outline_rounded, size: 13, color: Pal.mint),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _port == null
                      ? _path ?? ''
                      : 'localhost:$_port  ·  ${_shortRoot(folder)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Txt.meta.copyWith(fontSize: 10.5),
                ),
              ),
              IconAction(
                icon: Icons.refresh_rounded,
                tooltip: 'Reload preview',
                size: 18,
                onTap: _load,
              ),
            ],
          ),
        ),
        Expanded(child: WebViewWidget(controller: controller)),
      ],
    );
  }

  String _shortRoot(String? folder) {
    if (folder == null || folder.isEmpty) return '';
    final parts = folder.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.length <= 2) return folder;
    return '…/${parts.sublist(parts.length - 2).join('/')}';
  }
}
