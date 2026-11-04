import 'package:flutter/material.dart';

import '../core/integrations.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import 'ui.dart';

/// The ship bar shown inside a project, above Files and Preview. It performs
/// the same real GitHub and Vercel calls as the settings screen, scoped to the
/// project that is open.
class ProjectActionsBar extends StatefulWidget {
  const ProjectActionsBar({super.key, required this.project});

  final Project project;

  @override
  State<ProjectActionsBar> createState() => _ProjectActionsBarState();
}

class _ProjectActionsBarState extends State<ProjectActionsBar> {
  bool _pushing = false;
  bool _deploying = false;

  String get _slug {
    final base = widget.project.name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return base.isEmpty ? 'devnest-project' : base;
  }

  Future<void> _push() async {
    if (_pushing) return;
    final state = AppScope.of(context);
    if (state.integrations.githubToken.isEmpty) {
      await _result(
        'GitHub token missing',
        'Add a token in Settings → Integrations, then push again.',
        null,
      );
      return;
    }
    final repo = TextEditingController(text: _slug);
    var private = true;
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Pal.surface,
          title: const Text('Push to GitHub'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: repo,
                autofocus: true,
                style: Txt.body,
                cursorColor: Pal.ember,
                decoration: appField('repo-name'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Expanded(
                    child: Text('Private repository', style: Txt.bodySoft),
                  ),
                  Switch(
                    value: private,
                    onChanged: (value) => setDialogState(() => private = value),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Push'),
            ),
          ],
        ),
      ),
    );
    final repoName = repo.text.trim();
    repo.dispose();
    if (go != true || !mounted) return;

    setState(() => _pushing = true);
    try {
      final result = await state.pushToGithub(
        widget.project,
        repo: repoName.isEmpty ? _slug : repoName,
        private: private,
      );
      if (!mounted) return;
      await _result('Pushed', result.message, result.url);
    } on IntegrationException catch (error) {
      if (mounted) await _result('Push failed', error.message, null);
    } catch (error) {
      if (mounted) await _result('Push failed', '$error', null);
    } finally {
      if (mounted) setState(() => _pushing = false);
    }
  }

  Future<void> _deploy() async {
    if (_deploying) return;
    final state = AppScope.of(context);
    if (state.integrations.vercelToken.isEmpty) {
      await _result(
        'Vercel token missing',
        'Add a token in Settings → Integrations, then deploy again.',
        null,
      );
      return;
    }
    final name = TextEditingController(text: _slug);
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Pal.surface,
        title: const Text('Deploy to Vercel'),
        content: TextField(
          controller: name,
          autofocus: true,
          style: Txt.body,
          cursorColor: Pal.ember,
          decoration: appField('project-name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Deploy'),
          ),
        ],
      ),
    );
    final projectName = name.text.trim();
    name.dispose();
    if (go != true || !mounted) return;

    setState(() => _deploying = true);
    try {
      final result = await state.deployToVercel(
        widget.project,
        name: projectName.isEmpty ? _slug : projectName,
      );
      if (!mounted) return;
      await _result('Deployed', result.message, result.url);
    } on IntegrationException catch (error) {
      if (mounted) await _result('Deploy failed', error.message, null);
    } catch (error) {
      if (mounted) await _result('Deploy failed', '$error', null);
    } finally {
      if (mounted) setState(() => _deploying = false);
    }
  }

  Future<void> _result(String title, String message, String? url) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Pal.surface,
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(message, style: Txt.bodySoft),
            if (url != null && url.isNotEmpty) ...[
              const SizedBox(height: 10),
              SelectableText(
                url,
                style: Txt.code.copyWith(color: Pal.ember, fontSize: 12),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x2, Sp.x2, Sp.x2),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Pal.line)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_upload_outlined, size: 14, color: Pal.textDim),
          const SizedBox(width: 7),
          const Expanded(
            child: Text(
              'Ship this project',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Txt.meta,
            ),
          ),
          GhostButton(
            label: _pushing ? 'Pushing…' : 'Push',
            icon: Icons.upload_rounded,
            onTap: _pushing || _deploying ? null : _push,
          ),
          const SizedBox(width: 8),
          GhostButton(
            label: _deploying ? 'Deploying…' : 'Deploy',
            icon: Icons.rocket_launch_outlined,
            onTap: _pushing || _deploying ? null : _deploy,
          ),
        ],
      ),
    );
  }
}
