import 'package:flutter/material.dart';

import '../screens/code_screen.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';

class FilesTab extends StatefulWidget {
  const FilesTab({super.key, required this.projectId});

  final String projectId;

  @override
  State<FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends State<FilesTab> {
  final Set<String> _collapsed = <String>{};

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final paths = state.files.keys.toList()..sort();
    final rows = <Widget>[];
    _walk(_buildTree(paths), 0, rows, state);

    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.x2, Sp.x4, Sp.x2, Sp.x6),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.x3),
          child: Row(
            children: [
              const Text('EXPLORER', style: Txt.overline),
              const Spacer(),
              Text(
                '${paths.length} files · main',
                style: Txt.meta.copyWith(fontSize: 10),
              ),
            ],
          ),
        ),
        const SizedBox(height: Sp.x3),
        ...rows,
      ],
    );
  }

  void _walk(_Node node, int depth, List<Widget> out, AppState state) {
    final children = node.children.values.toList()
      ..sort((a, b) {
        if (a.isFile != b.isFile) return a.isFile ? 1 : -1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    for (final child in children) {
      final isOpen = !_collapsed.contains(child.path);
      out.add(
        _FileRow(
          node: child,
          depth: depth,
          open: isOpen,
          onTap: () {
            if (child.isFile) {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CodeScreen(
                    path: child.file!,
                    code: state.files[child.file!] ?? '',
                  ),
                ),
              );
            } else {
              setState(() {
                if (!_collapsed.remove(child.path)) _collapsed.add(child.path);
              });
            }
          },
        ),
      );
      if (!child.isFile && isOpen) {
        _walk(child, depth + 1, out, state);
      }
    }
  }

  _Node _buildTree(List<String> paths) {
    final root = _Node('');
    for (final path in paths) {
      final parts = path.split('/');
      var node = root;
      var acc = '';
      for (var i = 0; i < parts.length; i++) {
        acc = acc.isEmpty ? parts[i] : '$acc/${parts[i]}';
        final isLeaf = i == parts.length - 1;
        node = node.children.putIfAbsent(
          parts[i],
          () => _Node(
            parts[i],
            file: isLeaf ? path : null,
            path: acc,
          ),
        );
      }
    }
    return root;
  }
}

class _Node {
  _Node(this.name, {this.file, this.path = ''});

  final String name;
  final String? file;
  final String path;
  final Map<String, _Node> children = {};

  bool get isFile => file != null;
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.node,
    required this.depth,
    required this.open,
    required this.onTap,
  });

  final _Node node;
  final int depth;
  final bool open;
  final VoidCallback onTap;

  Color get _tint {
    final ext = node.name.split('.').last;
    return switch (ext) {
      'dart' => Pal.sky,
      'yaml' || 'yml' => Pal.amber,
      'md' => Pal.mint,
      'json' => Pal.mint,
      _ => Pal.textMuted,
    };
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.fromLTRB(Sp.x3 + depth * 14.0, 0, Sp.x3, 0),
        child: Container(
          height: 38,
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              if (!node.isFile)
                Icon(
                  open
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_right_rounded,
                  size: 16,
                  color: Pal.textDim,
                )
              else
                const SizedBox(width: 16),
              const SizedBox(width: 4),
              Icon(
                node.isFile
                    ? Icons.insert_drive_file_outlined
                    : Icons.folder_outlined,
                size: 15,
                color: node.isFile ? _tint : Pal.textMuted,
              ),
              const SizedBox(width: Sp.x2),
              Expanded(
                child: Text(
                  node.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: node.isFile
                      ? Txt.meta.copyWith(fontSize: 12, color: Pal.text)
                      : Txt.body.copyWith(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
