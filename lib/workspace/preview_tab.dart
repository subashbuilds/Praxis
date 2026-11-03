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
  String? _path;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = AppScope.of(context);
    try {
      final path = await state.previewFile(widget.project);
      if (!mounted) return;
      if (path == null) {
        setState(() {
          _loading = false;
          _path = null;
        });
        return;
      }
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Pal.terminal);
      await controller.loadFile(path);
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _path = path;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _createIndex() async {
    await AppScope.of(context)
        .createFile(widget.project, 'index.html', content: kIndexHtml);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
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
                    '.html file) to this project and it will render here.',
          ),
          const SizedBox(height: Sp.x4),
          EmberButton(
            label: 'Create index.html',
            icon: Icons.add_rounded,
            onTap: _createIndex,
          ),
          const SizedBox(height: Sp.x3),
          const Text(
            'Preview renders files from this device. Nothing is uploaded.',
            style: Txt.meta,
          ),
        ],
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x2, Sp.x2, Sp.x2),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Pal.line)),
          ),
          child: Row(
            children: [
              const Icon(Icons.lock_outline_rounded, size: 13, color: Pal.mint),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _path ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Txt.meta.copyWith(fontSize: 10.5),
                ),
              ),
              IconAction(
                icon: Icons.refresh_rounded,
                tooltip: 'Reload preview',
                size: 18,
                onTap: () async {
                  await _load();
                },
              ),
            ],
          ),
        ),
        Expanded(child: WebViewWidget(controller: controller)),
      ],
    );
  }
}
