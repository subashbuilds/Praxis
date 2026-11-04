import 'package:flutter/material.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/code_editor.dart';
import '../widgets/ui.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.project, required this.path});

  final Project project;
  final String path;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final CodeController _controller =
      CodeController(language: languageForPath(widget.path));
  bool _loading = true;
  bool _dirty = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final content =
          await AppScope.of(context).readFile(widget.project, widget.path);
      if (!mounted) return;
      setState(() {
        _controller.text = content;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await AppScope.of(context)
          .writeFile(widget.project, widget.path, _controller.text);
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _saving = false;
      });
      messenger.showSnackBar(SnackBar(content: Text('Saved ${widget.path}')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save: $error')),
      );
    }
  }

  Future<void> _confirmLeave() async {
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Pal.surface,
        title: const Text('Discard changes?'),
        content: Text('${widget.path} has unsaved edits.', style: Txt.bodySoft),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Pal.rose),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if ((leave ?? false) && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final language = languageForPath(widget.path);
    final lines = _controller.text.split('\n').length;

    return Scaffold(
      backgroundColor: Pal.ghBg,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: Pal.ghPanel,
              padding: const EdgeInsets.fromLTRB(Sp.x2, Sp.x2, Sp.x2, Sp.x2),
              child: Row(
                children: [
                  IconAction(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back',
                    onTap: _confirmLeave,
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.path.split('/').last,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Txt.title.copyWith(fontSize: 14),
                              ),
                            ),
                            const SizedBox(width: 8),
                            MonoChip(language.label),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _dirty
                              ? 'unsaved changes · $lines lines'
                              : 'saved on device · $lines lines',
                          style: Txt.meta.copyWith(
                            fontSize: 10,
                            color: _dirty ? Pal.amber : Pal.textDim,
                          ),
                        ),
                      ],
                    ),
                  ),
                  EmberButton(
                    label: _saving ? 'Saving' : 'Save',
                    compact: true,
                    loading: _saving,
                    onTap: _save,
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(Sp.page),
                          child: Text(
                            _error!,
                            style: Txt.bodySoft.copyWith(color: Pal.rose),
                          ),
                        )
                      : CodeEditor(
                          controller: _controller,
                          language: language,
                          wrap: state.wordWrap,
                          onChanged: (_) {
                            if (!_dirty) setState(() => _dirty = true);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
