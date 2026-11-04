import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/integrations.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';
import 'provider_form.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.project});

  final Project? project;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _githubBusy = false;
  bool _vercelBusy = false;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(Sp.x2, Sp.x2, Sp.x2, Sp.x2),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Pal.line)),
              ),
              child: Row(
                children: [
                  IconAction(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 4),
                  const Text('Settings', style: Txt.title),
                  const Spacer(),
                  const Wordmark(size: 13, showMark: false),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Sp.page, 0, Sp.page, Sp.x10),
                children: [
                  SectionLabel(
                    'MODEL',
                    trailing:
                        Text('${state.providers.length}', style: Txt.meta),
                  ),
                  const Text(
                    'Every provider uses your own key; add several so the agent '
                    'can move on when one runs out. Pick the active one with the '
                    'Providers pill inside a project. Ollama is the keyless '
                    'option on your own network.',
                    style: Txt.bodySoft,
                  ),
                  const SizedBox(height: Sp.x3),
                  for (final provider in state.providers)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ProviderRow(
                        provider: provider,
                        active: provider.id == state.activeProviderId,
                        onTap: () => _editProvider(provider),
                      ),
                    ),
                  const SizedBox(height: Sp.x2),
                  GhostButton(
                    label: 'Add custom endpoint',
                    icon: Icons.add_rounded,
                    onTap: () => _editProvider(state.newCustomProvider()),
                  ),
                  SectionLabel(
                    'SKILLS',
                    trailing: Text(
                        '${state.skills.where((s) => s.enabled).length} on',
                        style: Txt.meta),
                  ),
                  const Text(
                    'Skills are extra instructions added to every agent run. '
                    'They are local prompt fragments, not plugins.',
                    style: Txt.bodySoft,
                  ),
                  const SizedBox(height: Sp.x3),
                  for (final skill in state.skills)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Panel(
                        padding: const EdgeInsets.symmetric(
                            horizontal: Sp.x3, vertical: Sp.x2),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(skill.name,
                                      style: Txt.title.copyWith(fontSize: 14)),
                                  const SizedBox(height: 2),
                                  Text(
                                    skill.instructions,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Txt.meta.copyWith(height: 1.4),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: skill.enabled,
                              onChanged: (value) => state
                                  .saveSkill(skill.copyWith(enabled: value)),
                            ),
                            IconAction(
                              icon: Icons.edit_outlined,
                              tooltip: 'Edit skill',
                              size: 17,
                              onTap: () => _editSkill(skill),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      GhostButton(
                        label: 'Add skill',
                        icon: Icons.add_rounded,
                        onTap: () => _editSkill(state.newSkill()),
                      ),
                      const SizedBox(width: 8),
                      GhostButton(
                        label: 'Import .md / .txt',
                        icon: Icons.upload_file_rounded,
                        onTap: _importSkill,
                      ),
                    ],
                  ),
                  const SectionLabel('INTEGRATIONS'),
                  const Text(
                    'Tokens are stored on this device only and sent straight to '
                    'the provider you name.',
                    style: Txt.bodySoft,
                  ),
                  const SizedBox(height: Sp.x3),
                  _IntegrationPanel(
                    icon: Icons.code_rounded,
                    title: 'GitHub',
                    status: state.integrations.githubToken.isEmpty
                        ? 'No token'
                        : 'Token saved',
                    ready: state.integrations.githubToken.isNotEmpty,
                    description:
                        'Creates or updates a repo and commits every text file in this project.',
                    actions: [
                      GhostButton(
                        label: 'Token',
                        onTap: () => _editGithubToken(state),
                      ),
                      GhostButton(
                        label: _githubBusy ? 'Testing…' : 'Test',
                        onTap: _githubBusy ||
                                state.integrations.githubToken.isEmpty
                            ? null
                            : () => _testGithub(state),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _IntegrationPanel(
                    icon: Icons.change_history_rounded,
                    title: 'Vercel',
                    status: state.integrations.vercelToken.isEmpty
                        ? 'No token'
                        : 'Token saved',
                    ready: state.integrations.vercelToken.isNotEmpty,
                    description:
                        'Uploads the project’s text files as a static deployment and returns its URL.',
                    actions: [
                      GhostButton(
                        label: 'Token',
                        onTap: () => _editVercelToken(state),
                      ),
                      GhostButton(
                        label: _vercelBusy ? 'Testing…' : 'Test',
                        onTap: _vercelBusy ||
                                state.integrations.vercelToken.isEmpty
                            ? null
                            : () => _testVercel(state),
                      ),
                    ],
                  ),
                  const SectionLabel('CONTINUATION'),
                  const Text(
                    'What happens when a key or a provider runs out. With both '
                    'off, the agent stops and asks before switching.',
                    style: Txt.bodySoft,
                  ),
                  const SizedBox(height: Sp.x3),
                  Panel(
                    padding:
                        const EdgeInsets.fromLTRB(Sp.x3, Sp.x1, Sp.x3, Sp.x1),
                    child: Column(
                      children: [
                        _SwitchRow(
                          title: 'Use the next key',
                          body: 'When a key is rate-limited or out of credit, '
                              'move to the next saved key automatically.',
                          value: state.autoNextKey,
                          onChanged: state.setAutoNextKey,
                        ),
                        const Hairline(),
                        _SwitchRow(
                          title: 'Move to the next provider',
                          body: 'When every key for a provider is used up, '
                              'switch to another configured provider.',
                          value: state.autoNextProvider,
                          onChanged: state.setAutoNextProvider,
                        ),
                      ],
                    ),
                  ),
                  const SectionLabel('EDITOR'),
                  Panel(
                    padding: const EdgeInsets.symmetric(
                        horizontal: Sp.x3, vertical: Sp.x1),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Wrap long lines',
                                  style: Txt.title.copyWith(fontSize: 14)),
                              const SizedBox(height: 2),
                              const Text(
                                  'Softer reading for prose and markdown',
                                  style: Txt.meta),
                            ],
                          ),
                        ),
                        Switch(
                          value: state.wordWrap,
                          onChanged: state.setWordWrap,
                        ),
                      ],
                    ),
                  ),
                  const SectionLabel('DATA'),
                  Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Erase everything',
                            style: Txt.title.copyWith(fontSize: 14)),
                        const SizedBox(height: 4),
                        const Text(
                          'Deletes all projects, chats, keys and tokens from this '
                          'device and starts again with one empty web project.',
                          style: Txt.bodySoft,
                        ),
                        const SizedBox(height: Sp.x3),
                        GhostButton(
                          label: 'Reset DevNest',
                          icon: Icons.delete_forever_outlined,
                          onTap: () => _reset(state),
                        ),
                      ],
                    ),
                  ),
                  const SectionLabel('ABOUT'),
                  const Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            BrandMark(size: 22),
                            SizedBox(width: 9),
                            Text('DevNest', style: Txt.title),
                            Spacer(),
                            Text('1.1.0', style: Txt.meta),
                          ],
                        ),
                        SizedBox(height: 10),
                        Text(
                          'A local-first coding workbench for Android: real files, '
                          'a real project shell, a WebView preview, and an agent '
                          'that edits those files with your model key.',
                          style: Txt.bodySoft,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'No account, no telemetry. Files live in the app’s '
                          'documents directory.',
                          style: Txt.meta,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editProvider(ProviderConfig provider) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Pal.surface,
      builder: (_) => ProviderFormSheet(provider: provider),
    );
  }

  Future<void> _importSkill() async {
    final state = AppScope.of(context);
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['md', 'txt'],
        allowMultiple: true,
      );
    } catch (error) {
      if (!mounted) return;
      _showResult('Could not open the picker: $error');
      return;
    }
    if (result == null) return;
    var imported = 0;
    for (final file in result.files) {
      final path = file.path;
      if (path == null) continue;
      final skill = await state.importSkillFile(path);
      if (skill != null) imported++;
    }
    if (!mounted) return;
    _showResult(
      imported == 0
          ? 'No .md or .txt file was imported.'
          : 'Imported $imported skill${imported == 1 ? '' : 's'}.',
    );
  }

  Future<void> _editSkill(Skill skill) async {
    final state = AppScope.of(context);
    final name = TextEditingController(text: skill.name);
    final instructions = TextEditingController(text: skill.instructions);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Pal.surface,
        title: Text(skill.name.isEmpty ? 'New skill' : 'Edit skill'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              style: Txt.body,
              cursorColor: Pal.ember,
              decoration: appField('Name, e.g. “Terse diffs”'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: instructions,
              style: Txt.body,
              cursorColor: Pal.ember,
              minLines: 3,
              maxLines: 6,
              decoration: appField('Instructions added to the agent prompt'),
            ),
          ],
        ),
        actions: [
          if (skill.name.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              style: TextButton.styleFrom(foregroundColor: Pal.rose),
              child: const Text('Delete'),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == true) {
      await state.saveSkill(skill.copyWith(
        name: name.text.trim().isEmpty ? 'Skill' : name.text.trim(),
        instructions: instructions.text.trim(),
      ));
    } else if (saved == false) {
      await state.deleteSkill(skill);
    }
    name.dispose();
    instructions.dispose();
  }

  Future<String?> _askToken(String title, String current) {
    final controller = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Pal.surface,
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          style: Txt.body,
          cursorColor: Pal.ember,
          decoration: appField('Paste token'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _editGithubToken(AppState state) async {
    final token =
        await _askToken('GitHub token', state.integrations.githubToken);
    if (token == null) return;
    await state
        .saveIntegrations(state.integrations.copyWith(githubToken: token));
  }

  Future<void> _editVercelToken(AppState state) async {
    final token =
        await _askToken('Vercel token', state.integrations.vercelToken);
    if (token == null) return;
    await state
        .saveIntegrations(state.integrations.copyWith(vercelToken: token));
  }

  Future<void> _testGithub(AppState state) async {
    setState(() => _githubBusy = true);
    try {
      final login = await state.testGithub();
      _showResult('GitHub connected as $login');
    } on IntegrationException catch (error) {
      _showResult(error.message);
    } catch (error) {
      _showResult('$error');
    } finally {
      if (mounted) setState(() => _githubBusy = false);
    }
  }

  Future<void> _testVercel(AppState state) async {
    setState(() => _vercelBusy = true);
    try {
      final account = await state.testVercel();
      _showResult('Vercel connected as $account');
    } on IntegrationException catch (error) {
      _showResult(error.message);
    } catch (error) {
      _showResult('$error');
    } finally {
      if (mounted) setState(() => _vercelBusy = false);
    }
  }

  Future<void> _reset(AppState state) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Pal.surface,
        title: const Text('Erase all local data?'),
        content: const Text(
          'Projects, chats, provider keys and integration tokens are deleted from '
          'this device. This cannot be undone.',
          style: Txt.bodySoft,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Pal.rose),
            child: const Text('Erase'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await state.resetEverything();
      _showResult('DevNest was reset to a clean state.');
    }
  }

  void _showResult(String message, [String? url]) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Pal.surface,
        title: const Text('Result'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(message, style: Txt.bodySoft),
            if (url != null) ...[
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
}

class _ProviderRow extends StatelessWidget {
  const _ProviderRow({
    required this.provider,
    required this.active,
    required this.onTap,
  });

  final ProviderConfig provider;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Panel(
        padding:
            const EdgeInsets.symmetric(horizontal: Sp.x3, vertical: Sp.x2 + 2),
        borderColor: active ? Pal.ember.withOpacity(0.5) : Pal.line,
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: SvgPicture.asset(
                provider.icon,
                colorFilter: ColorFilter.mode(
                  provider.isConfigured ? Pal.text : Pal.textDim,
                  BlendMode.srcIn,
                ),
              ),
            ),
            const SizedBox(width: Sp.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          provider.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Txt.title.copyWith(fontSize: 14),
                        ),
                      ),
                      if (active) ...[
                        const SizedBox(width: 7),
                        const StatusPill('active', color: Pal.ember),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${provider.model.isEmpty ? 'No model set' : provider.model}'
                    ' · ${provider.keys.where((key) => key.trim().isNotEmpty).length} keys',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Txt.meta,
                  ),
                ],
              ),
            ),
            Icon(
              provider.ready
                  ? Icons.check_circle_rounded
                  : Icons.key_off_rounded,
              size: 16,
              color: provider.ready ? Pal.mint : Pal.amber,
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded,
                size: 17, color: Pal.textDim),
          ],
        ),
      ),
    );
  }
}

class _IntegrationPanel extends StatelessWidget {
  const _IntegrationPanel({
    required this.icon,
    required this.title,
    required this.status,
    required this.ready,
    required this.description,
    required this.actions,
  });

  final IconData icon;
  final String title;
  final String status;
  final bool ready;
  final String description;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlyphBadge(
                icon: icon,
                color: ready ? Pal.mint : Pal.textDim,
                size: 30,
                iconSize: 15,
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(title, style: Txt.title.copyWith(fontSize: 14))),
              StatusPill(status, color: ready ? Pal.mint : Pal.amber),
            ],
          ),
          const SizedBox(height: 8),
          Text(description, style: Txt.bodySoft.copyWith(fontSize: 12.5)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.body,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String body;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Txt.title.copyWith(fontSize: 14)),
              const SizedBox(height: 2),
              Text(body, style: Txt.meta.copyWith(height: 1.4)),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
