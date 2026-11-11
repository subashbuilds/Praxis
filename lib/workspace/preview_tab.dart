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
  static const _desktopUserAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0.0.0 Safari/537.36';
  static const _mobileUserAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  WebViewController? _controller;
  HttpServer? _server;
  String? _path;
  String? _root;
  int? _port;
  int? _devPort;
  bool _loading = true;
  bool _desktop = false;
  bool _switching = false;
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
      // A dev server, when one has been seen in the shell, is what the user
      // actually wants to preview. Otherwise the exported files are served.
      final devPort = state.devPortFor(widget.project);
      final path =
          devPort == null ? await state.previewFile(widget.project) : null;
      if (!mounted) return;
      if (path == null && devPort == null) {
        setState(() {
          _loading = false;
          _path = null;
          _controller = null;
          _devPort = null;
          _port = null;
          _error = null;
        });
        return;
      }
      final normalized = (path ?? '').replaceAll('\\', '/');
      final entry = normalized.split('/').last;
      final root = path == null ? '' : _rootFor(path);
      HttpServer? server;
      if (path != null) {
        try {
          server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          server.listen((request) => _serve(request, root, entry));
        } catch (_) {
          server = null;
        }
      }
      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setBackgroundColor(Pal.terminal);
      try {
        await controller.setUserAgent(
          _desktop ? _desktopUserAgent : _mobileUserAgent,
        );
      } catch (_) {
        // The default user agent is still usable.
      }
      await controller.setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => _applyDesktopViewport(controller),
      ));
      final target = devPort != null
          ? 'http://127.0.0.1:$devPort/'
          : (server != null ? 'http://127.0.0.1:${server.port}/' : null);
      // Load the page directly. Framing it inside a generated wrapper made
      // servers that send X-Frame-Options or a frame-ancestors policy fail with
      // ERR_BLOCKED_BY_RESPONSE, and Next's dev server saw a foreign origin for
      // its own HMR socket. The desktop layout comes from the user agent and a
      // 1280px viewport instead.
      if (target != null) {
        await controller.loadRequest(Uri.parse(target));
      } else {
        await controller.loadFile(path!);
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
        _devPort = devPort;
        _port = devPort ?? server?.port;
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

  Future<void> _editPort() async {
    final state = AppScope.of(context);
    final current = state.devPortFor(widget.project);
    final controller =
        TextEditingController(text: current?.toString() ?? '3000');
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Pal.surface,
        title: const Text('Preview a running server'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Start the dev server in the shell, then use the port it prints. '
              'Leave the port empty to preview the exported project files.',
              style: Txt.meta.copyWith(height: 1.45),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              style: Txt.code.copyWith(fontSize: 13),
              cursorColor: Pal.ember,
              decoration: appField('3000', label: 'Port'),
              onSubmitted: (value) =>
                  Navigator.of(dialogContext).pop(value.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('auto'),
            child: const Text('Use project files'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Use port'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (choice == null || !mounted) return;
    if (choice == 'auto' || choice.isEmpty) {
      await state.setDevPort(widget.project, null);
    } else {
      final port = int.tryParse(choice);
      if (port == null || port < 1 || port > 65535) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Enter a port between 1 and 65535.')),
          );
        }
        return;
      }
      await state.setDevPort(widget.project, port);
    }
    if (mounted) await _load();
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

  Future<void> _applyDesktopViewport(WebViewController controller) async {
    if (!mounted) return;
    try {
      // A viewport of 1280 CSS pixels gives the page a desktop layout width,
      // so media queries and width-dependent scripts choose desktop styles. The
      // WebView shrinks the wide page to fit the screen like a desktop site.
      await controller.runJavaScript('''
        (() => {
          let meta = document.querySelector('meta[name="viewport"]');
          if (!meta) {
            meta = document.createElement('meta');
            meta.name = 'viewport';
            document.head.appendChild(meta);
          }
          if (meta.dataset.praxisOriginal === undefined) {
            meta.dataset.praxisOriginal = meta.getAttribute('content') || '';
          }
          const desktop = ${_desktop ? 'true' : 'false'};
          if (desktop) {
            const width = 1280;
            // screen.width can be physical pixels on Android, which would
            // leave the wide page larger than the phone. The visual viewport
            // is the CSS width actually visible before the override.
            const deviceWidth =
              (window.visualViewport && window.visualViewport.width) ||
              window.innerWidth || width;
            const scale = Math.min(1, deviceWidth / width);
            meta.setAttribute(
              'content',
              'width=' + width + ', initial-scale=' + scale +
                ', minimum-scale=' + scale,
            );
          } else {
            meta.setAttribute('content', meta.dataset.praxisOriginal ||
              'width=device-width, initial-scale=1');
          }
          document.documentElement.style.width = '';
          document.documentElement.style.zoom = '';
          window.dispatchEvent(new Event('resize'));
          // Some frameworks only read the viewport once during hydration.
          window.setTimeout(
            () => window.dispatchEvent(new Event('resize')),
            120,
          );
        })();
      ''');
    } catch (_) {
      // A page without a writable head still renders in the selected width.
    }
  }

  Future<void> _togglePreviewMode() async {
    final controller = _controller;
    if (controller == null || _switching) return;
    final desktop = !_desktop;
    setState(() {
      _desktop = desktop;
      _switching = true;
      _error = null;
    });
    try {
      // A real reload is required: responsive sites decide their layout from
      // the user agent and the initial viewport width, not from a later resize.
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not switch preview mode: $error');
      }
    } finally {
      if (mounted) setState(() => _switching = false);
    }
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
          padding: const EdgeInsets.fromLTRB(Sp.x4, 3, Sp.x2, 3),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Pal.line)),
          ),
          child: Row(
            children: [
              Icon(Icons.lock_outline_rounded, size: 13, color: Pal.mint),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _devPort != null
                      ? 'localhost:$_devPort  ·  dev server'
                      : _port == null
                          ? _path ?? ''
                          : 'localhost:$_port  ·  ${_shortRoot(folder)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Txt.meta.copyWith(fontSize: 10.5),
                ),
              ),
              GestureDetector(
                onTap: _editPort,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  margin: const EdgeInsets.only(right: 2),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                  decoration: BoxDecoration(
                    color: _devPort == null
                        ? Pal.raised
                        : Pal.mint.withOpacity(0.12),
                    borderRadius: Rd.pill,
                    border: Border.all(
                      color: _devPort == null
                          ? Pal.lineStrong
                          : Pal.mint.withOpacity(0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lan_outlined,
                        size: 12,
                        color: _devPort == null ? Pal.textDim : Pal.mint,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _devPort == null ? 'Port' : ':$_devPort',
                        style: Txt.meta.copyWith(fontSize: 9.5),
                      ),
                    ],
                  ),
                ),
              ),
              IconAction(
                icon: _desktop
                    ? Icons.smartphone_rounded
                    : Icons.desktop_mac_rounded,
                tooltip: _desktop ? 'Mobile preview' : 'Desktop preview',
                size: 17,
                padding: const EdgeInsets.all(6),
                onTap: _switching ? null : _togglePreviewMode,
              ),
              IconAction(
                icon: Icons.refresh_rounded,
                tooltip: 'Reload preview',
                size: 17,
                padding: const EdgeInsets.all(6),
                onTap: _load,
              ),
            ],
          ),
        ),
        if (_switching)
          LinearProgressIndicator(
            minHeight: 1.5,
            color: Pal.ember,
            backgroundColor: Colors.transparent,
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
