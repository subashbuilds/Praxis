import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/usage.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/ui.dart';
import 'about_screen.dart';
import 'provider_form.dart';
import 'usage_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.project});

  final Project? project;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _accountBusy = false;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final configured = state.configuredProviders;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(Sp.x2, Sp.x2, Sp.x2, Sp.x2),
              decoration: BoxDecoration(
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
                  Text('Settings', style: Txt.title),
                  const Spacer(),
                  const Wordmark(size: 13, showMark: false),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Sp.page, 0, Sp.page, Sp.x10),
                children: [
                  const SectionLabel('APPEARANCE'),
                  _ThemeChoices(
                    dark: state.darkMode,
                    onChanged: state.setDarkMode,
                  ),
                  const SectionLabel('USAGE'),
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const UsageScreen()),
                    ),
                    behavior: HitTestBehavior.opaque,
                    child: Panel(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Sp.x3, vertical: Sp.x3),
                      child: Row(
                        children: [
                          GlyphBadge(
                            icon: Icons.insights_rounded,
                            color: Pal.ember,
                            size: 34,
                            iconSize: 17,
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${compactTokens(state.usage.totalTokens)} tokens',
                                  style: Txt.title.copyWith(fontSize: 15),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  state.usage.events.isEmpty
                                      ? 'No model calls yet'
                                      : '${state.usage.events.length} calls · ${compactTokens(state.usage.todayTokens)} today',
                                  style: Txt.meta.copyWith(fontSize: 9.5),
                                ),
                              ],
                            ),
                          ),
                          Text('View',
                              style: Txt.meta.copyWith(color: Pal.ember)),
                          const SizedBox(width: 2),
                          Icon(Icons.chevron_right_rounded,
                              size: 17, color: Pal.textDim),
                        ],
                      ),
                    ),
                  ),
                  SectionLabel(
                    'PROVIDERS',
                    trailing: Text('${configured.length}', style: Txt.meta),
                  ),
                  Text(
                    'Only providers you have connected appear here. Add several '
                    'keys to one provider and Praxis can move through them when '
                    'a limit is reached.',
                    style: Txt.bodySoft,
                  ),
                  const SizedBox(height: Sp.x3),
                  if (configured.isEmpty)
                    Panel(
                      padding: const EdgeInsets.all(Sp.x3),
                      child: Row(
                        children: [
                          Icon(Icons.key_off_rounded,
                              size: 18, color: Pal.amber),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              'No provider connected yet. Add one to start '
                              'using the agent.',
                              style: Txt.bodySoft.copyWith(fontSize: 12.5),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    for (final provider in configured)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _ProviderRow(
                          provider: provider,
                          active: provider.id == state.activeProviderId,
                          onTap: () => _editProvider(provider),
                        ),
                      ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _addProvider(state),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: Rd.sm,
                        border: Border.all(color: Pal.ember.withOpacity(0.4)),
                        color: Pal.ember.withOpacity(0.06),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_rounded, size: 17, color: Pal.ember),
                          const SizedBox(width: 6),
                          Text(
                            'Add provider',
                            style: Txt.label.copyWith(
                              color: Pal.ember,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SectionLabel(
                    'SKILLS',
                    trailing: Text(
                      '${state.skills.where((skill) => skill.enabled).length} on',
                      style: Txt.meta,
                    ),
                  ),
                  Text(
                    'Skills are reusable instructions. Ask the agent to install '
                    'one and it writes .praxis/skills/<name>/SKILL.md inside the '
                    'project. Project skills load into every prompt, with any '
                    'provider or model, and sync through the project folder.',
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      GhostButton(
                        label: 'Add skill',
                        icon: Icons.add_rounded,
                        onTap: () => _editSkill(state.newSkill()),
                      ),
                      GhostButton(
                        label: 'Import .md / .txt',
                        icon: Icons.upload_file_rounded,
                        onTap: _importSkill,
                      ),
                    ],
                  ),
                  const SectionLabel('INTEGRATIONS'),
                  Text(
                    'Add as many accounts as you use. The active account is '
                    'offered first in Push and Deploy; you can switch it there '
                    'too. Tokens stay on this device.',
                    style: Txt.bodySoft,
                  ),
                  const SizedBox(height: Sp.x3),
                  _IntegrationCard(
                    kind: IntegrationKind.github,
                    accounts: state.integrations.ofKind(IntegrationKind.github),
                    activeId: state.activeGithub?.id ?? '',
                    busy: _accountBusy,
                    onAdd: () => _addAccount(IntegrationKind.github),
                    onActivate: state.activateAccount,
                    onRemove: _removeAccount,
                  ),
                  const SizedBox(height: 8),
                  _IntegrationCard(
                    kind: IntegrationKind.vercel,
                    accounts: state.integrations.ofKind(IntegrationKind.vercel),
                    activeId: state.activeVercel?.id ?? '',
                    busy: _accountBusy,
                    onAdd: () => _addAccount(IntegrationKind.vercel),
                    onActivate: state.activateAccount,
                    onRemove: _removeAccount,
                  ),
                  const SectionLabel('CONTINUATION'),
                  Text(
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
                              Text('Soft wrapping for prose and markdown',
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
                    borderColor: Pal.rose.withOpacity(0.55),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Erase everything',
                          style: Txt.title.copyWith(
                            fontSize: 14,
                            color: Pal.rose,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Deletes all projects, chats, keys and tokens from this '
                          'device and starts again with one empty project.',
                          style: Txt.bodySoft,
                        ),
                        const SizedBox(height: Sp.x3),
                        GhostButton(
                          label: 'Reset Praxis',
                          icon: Icons.delete_forever_outlined,
                          onTap: () => _reset(state),
                        ),
                      ],
                    ),
                  ),
                  const SectionLabel('ABOUT'),
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AboutScreen()),
                    ),
                    behavior: HitTestBehavior.opaque,
                    child: Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const BrandMark(size: 22),
                              const SizedBox(width: 9),
                              Text('Praxis', style: Txt.title),
                              const Spacer(),
                              Text('2.2.0', style: Txt.meta),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'A local-first coding workbench: real files, a real '
                            'shell, a live preview, and an agent that edits the '
                            'project with your key.',
                            style: Txt.bodySoft,
                          ),
                          const SizedBox(height: 9),
                          Row(
                            children: [
                              Text('Terms · Privacy · Licences',
                                  style: Txt.meta.copyWith(color: Pal.ember)),
                              const Spacer(),
                              Icon(Icons.chevron_right_rounded,
                                  size: 17, color: Pal.textDim),
                            ],
                          ),
                        ],
                      ),
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

  Future<void> _addProvider(AppState state) async {
    final selected = await showModalBottomSheet<ProviderConfig>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Pal.surface,
      builder: (_) => _ProviderPickerSheet(presets: state.availablePresets),
    );
    if (selected == null || !mounted) return;
    await _editProvider(selected);
  }

  Future<void> _editProvider(ProviderConfig provider) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Pal.surface,
      builder: (_) => ProviderFormSheet(provider: provider),
    );
  }

  Future<void> _addAccount(IntegrationKind kind) async {
    if (_accountBusy) return;
    final token = TextEditingController();
    final label = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Pal.surface,
        title: Text('Add ${kind.label} account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              kind == IntegrationKind.github
                  ? 'Create a fine-grained personal access token with Contents: '
                      'read and write access. It is validated against GitHub.'
                  : 'Create a Vercel access token from Account Settings → Tokens.',
              style: Txt.bodySoft.copyWith(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: token,
              autofocus: true,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              style: Txt.code.copyWith(fontSize: 12),
              cursorColor: Pal.ember,
              decoration: appField('Paste token'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: label,
              style: Txt.body.copyWith(fontSize: 13),
              cursorColor: Pal.ember,
              decoration: appField('Optional label, e.g. work', label: 'Label'),
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
            child: const Text('Add account'),
          ),
        ],
      ),
    );
    if (!(submitted ?? false) || !mounted) {
      token.dispose();
      label.dispose();
      return;
    }
    setState(() => _accountBusy = true);
    final state = AppScope.of(context);
    try {
      final account = await state.addAccount(
        kind: kind,
        token: token.text,
        label: label.text,
      );
      if (!mounted) return;
      _showResult('${kind.label} connected as @${account.username}');
    } catch (error) {
      if (!mounted) return;
      _showResult('$error');
    } finally {
      token.dispose();
      label.dispose();
      if (mounted) setState(() => _accountBusy = false);
    }
  }

  Future<void> _removeAccount(IntegrationAccount account) async {
    final confirmed = await showPraxisConfirm(
      context,
      title: 'Remove ${account.displayName}?',
      body: 'The token is deleted from this device. Projects and deployments '
          'already made are not affected.',
      confirmLabel: 'Remove account',
      destructive: true,
      icon: Icons.logout_rounded,
      details: [
        ConfirmDetail('Integration', account.kind.label),
        ConfirmDetail('Account', account.displayName),
      ],
    );
    if (confirmed && mounted) {
      await AppScope.of(context).removeAccount(account);
    }
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

  Future<void> _reset(AppState state) async {
    final confirmed = await showPraxisConfirm(
      context,
      title: 'Erase all local data?',
      body: 'Projects, chats, provider keys and integration tokens are deleted '
          'from this device. This cannot be undone.',
      confirmLabel: 'Erase everything',
      destructive: true,
      icon: Icons.delete_forever_rounded,
      note: 'GitHub repositories and deployed sites are not changed.',
    );
    if (confirmed) {
      await state.resetEverything();
      if (mounted) _showResult('Praxis was reset to a clean state.');
    }
  }

  void _showResult(String message) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Pal.surface,
        title: const Text('Result'),
        content: SelectableText(message, style: Txt.bodySoft),
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

class _ThemeChoices extends StatelessWidget {
  const _ThemeChoices({required this.dark, required this.onChanged});

  final bool dark;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ThemeCard(
            label: 'Light',
            icon: Icons.light_mode_outlined,
            active: !dark,
            preview: const Color(0xFFF7F3EC),
            onTap: () => onChanged(false),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: _ThemeCard(
            label: 'Dark',
            icon: Icons.dark_mode_outlined,
            active: dark,
            preview: const Color(0xFF12100E),
            onTap: () => onChanged(true),
          ),
        ),
      ],
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.label,
    required this.icon,
    required this.active,
    required this.preview,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final Color preview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: Motion.fast,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Pal.surface,
          borderRadius: Rd.md,
          border: Border.all(
            color: active ? Pal.ember : Pal.line,
            width: active ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: preview,
                borderRadius: const BorderRadius.all(Radius.circular(7)),
                border: Border.all(color: active ? Pal.ember : Pal.lineStrong),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                label,
                style: Txt.label.copyWith(
                  color: active ? Pal.text : Pal.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              active ? Icons.check_circle_rounded : icon,
              size: 16,
              color: active ? Pal.ember : Pal.textDim,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderPickerSheet extends StatelessWidget {
  const _ProviderPickerSheet({required this.presets});

  final List<ProviderConfig> presets;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.72,
      child: Column(
        children: [
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.page, 0, Sp.x3, Sp.x2),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Add provider', style: Txt.headline),
                      const SizedBox(height: 2),
                      Text(
                        'Choose one endpoint. You can add its keys and pick '
                        'models on the next screen.',
                        style: Txt.meta.copyWith(height: 1.4),
                      ),
                    ],
                  ),
                ),
                IconAction(
                  icon: Icons.close_rounded,
                  tooltip: 'Close',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Hairline(),
          Expanded(
            child: ListView(
              padding:
                  const EdgeInsets.fromLTRB(Sp.page, Sp.x2, Sp.page, Sp.x6),
              children: [
                for (final preset in presets)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(preset),
                      behavior: HitTestBehavior.opaque,
                      child: Panel(
                        padding: const EdgeInsets.symmetric(
                            horizontal: Sp.x3, vertical: 10),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: SvgPicture.asset(
                                preset.icon,
                                colorFilter: ColorFilter.mode(
                                  Pal.text,
                                  BlendMode.srcIn,
                                ),
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    preset.name,
                                    style: Txt.title.copyWith(fontSize: 14),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    preset.requiresKey
                                        ? preset.model
                                        : '${preset.model} · keyless',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Txt.meta.copyWith(fontSize: 9.5),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.add_rounded, size: 18, color: Pal.ember),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (presets.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Sp.x3),
                    child: Text(
                      'Every built-in provider is already connected. Use a '
                      'custom endpoint for anything else.',
                      style: Txt.bodySoft,
                    ),
                  ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(
                    ProviderConfig(
                      id: 'custom-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}',
                      name: 'Custom endpoint',
                      icon: 'assets/icons/opencode.svg',
                      baseUrl: 'https://',
                      model: '',
                      flavor: ApiFlavor.openai,
                      hint: 'Any OpenAI-compatible URL',
                      isCustom: true,
                    ),
                  ),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: Sp.x3, vertical: 13),
                    decoration: BoxDecoration(
                      borderRadius: Rd.sm,
                      border: Border.all(color: Pal.lineStrong),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.tune_rounded,
                            size: 18, color: Pal.textMuted),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Custom provider',
                                  style: Txt.label.copyWith(
                                    color: Pal.text,
                                    fontWeight: FontWeight.w600,
                                  )),
                              const SizedBox(height: 2),
                              Text(
                                'OpenAI-compatible or Anthropic-style endpoint',
                                style: Txt.meta.copyWith(fontSize: 9.5),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            size: 18, color: Pal.textDim),
                      ],
                    ),
                  ),
                ),
              ],
            ),
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
                        StatusPill('active', color: Pal.ember),
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
            Icon(Icons.chevron_right_rounded, size: 17, color: Pal.textDim),
          ],
        ),
      ),
    );
  }
}

class _IntegrationCard extends StatelessWidget {
  const _IntegrationCard({
    required this.kind,
    required this.accounts,
    required this.activeId,
    required this.busy,
    required this.onAdd,
    required this.onActivate,
    required this.onRemove,
  });

  final IntegrationKind kind;
  final List<IntegrationAccount> accounts;
  final String activeId;
  final bool busy;
  final VoidCallback onAdd;
  final Future<void> Function(IntegrationAccount) onActivate;
  final Future<void> Function(IntegrationAccount) onRemove;

  @override
  Widget build(BuildContext context) {
    final github = kind == IntegrationKind.github;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlyphBadge(
                icon:
                    github ? Icons.code_rounded : Icons.change_history_rounded,
                color: accounts.isEmpty ? Pal.textDim : Pal.mint,
                size: 30,
                iconSize: 15,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(kind.label, style: Txt.title.copyWith(fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(
                      github
                          ? 'Commit and push real branches'
                          : 'Static deployments',
                      style: Txt.meta.copyWith(fontSize: 9.5),
                    ),
                  ],
                ),
              ),
              StatusPill(
                accounts.isEmpty
                    ? 'not connected'
                    : '${accounts.length} account${accounts.length == 1 ? '' : 's'}',
                color: accounts.isEmpty ? Pal.textDim : Pal.mint,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            github
                ? 'A GitHub token with Contents read/write. Pushes are real git '
                    'commits built with the Git Data API.'
                : 'A Vercel token used to upload this project as a static '
                    'deployment.',
            style: Txt.bodySoft.copyWith(fontSize: 12),
          ),
          if (accounts.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final account in accounts)
              GestureDetector(
                onTap: () => onActivate(account),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(8, 7, 4, 7),
                    decoration: BoxDecoration(
                      color: account.id == activeId
                          ? Pal.raised
                          : Colors.transparent,
                      borderRadius: Rd.sm,
                      border: Border.all(
                        color: account.id == activeId
                            ? Pal.lineStrong
                            : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          account.id == activeId
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_off_rounded,
                          size: 15,
                          color:
                              account.id == activeId ? Pal.ember : Pal.textDim,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            account.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Txt.label.copyWith(
                              color: Pal.text,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (account.username.isNotEmpty)
                          Text(
                            '@${account.username}',
                            style: Txt.meta.copyWith(fontSize: 9),
                          ),
                        IconAction(
                          icon: Icons.close_rounded,
                          tooltip: 'Remove account',
                          size: 15,
                          onTap: () => onRemove(account),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 8),
          GhostButton(
            label: accounts.isEmpty ? 'Add account' : 'Add another account',
            icon: Icons.add_rounded,
            onTap: busy ? null : onAdd,
          ),
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
