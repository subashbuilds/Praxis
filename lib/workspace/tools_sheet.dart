import 'package:flutter/material.dart';

import '../core/file_types.dart';
import '../core/project_env.dart';
import '../core/project_skills.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/ui.dart';

/// Shell tools: project environment values and installed project skills in one
/// sheet. Environment values are available to builds and shell commands; the
/// agent sees names and non-secret values, never secret values.
class ToolsSheet extends StatefulWidget {
  const ToolsSheet({super.key, required this.project});

  final Project project;

  @override
  State<ToolsSheet> createState() => _ToolsSheetState();
}

class _ToolsSheetState extends State<ToolsSheet> {
  List<ProjectEnvEntry> _env = const [];
  List<ProjectSkill> _skills = const [];
  bool _loaded = false;
  bool _loading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _reload();
  }

  Future<void> _reload() async {
    if (_loading) return;
    setState(() => _loading = true);
    final state = AppScope.of(context);
    final env = await state.environmentFor(widget.project);
    final skills = await state.installedSkillsFor(widget.project);
    if (!mounted) return;
    setState(() {
      _env = env;
      _skills = skills;
      _loading = false;
    });
  }

  Future<void> _editEnv([ProjectEnvEntry? entry]) async {
    final state = AppScope.of(context);
    final name = TextEditingController(text: entry?.name ?? '');
    final value = TextEditingController(text: entry?.value ?? '');
    var secret = entry?.secret ?? false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          backgroundColor: Pal.surface,
          title: Text(entry == null ? 'Add variable' : 'Edit variable'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: name,
                  autofocus: entry == null,
                  textCapitalization: TextCapitalization.characters,
                  style: Txt.code.copyWith(fontSize: 13),
                  cursorColor: Pal.ember,
                  decoration: appField('API_URL', label: 'Name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: value,
                  style: Txt.code.copyWith(fontSize: 13),
                  cursorColor: Pal.ember,
                  obscureText: secret,
                  decoration: appField('value', label: 'Value'),
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  value: secret,
                  contentPadding: EdgeInsets.zero,
                  activeColor: Pal.amber,
                  title: Text('Secret', style: Txt.body.copyWith(fontSize: 13)),
                  subtitle: Text(
                    'The agent sees the name but never the value.',
                    style: Txt.meta.copyWith(fontSize: 10),
                  ),
                  onChanged: (next) => setDialog(() => secret = next),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(name.text.trim().isNotEmpty),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final cleanName = name.text.trim();
    final cleanValue = value.text;
    name.dispose();
    value.dispose();
    if (saved != true || !mounted) return;
    if (!ProjectEnvEntry.isValidName(cleanName)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Use letters, numbers and underscores, starting with a letter or '
            'underscore.',
          ),
        ),
      );
      return;
    }
    final next = [
      for (final item in _env)
        if (item.name != entry?.name) item,
      ProjectEnvEntry(name: cleanName, value: cleanValue, secret: secret),
    ]..sort((a, b) => a.name.compareTo(b.name));
    await state.saveEnvironment(widget.project, next);
    if (mounted) setState(() => _env = next);
  }

  Future<void> _deleteEnv(ProjectEnvEntry entry) async {
    final state = AppScope.of(context);
    final confirmed = await showPraxisConfirm(
      context,
      title: 'Delete ${entry.name}?',
      body: 'The variable is removed from this project. Builds and the agent '
          'will no longer see it.',
      confirmLabel: 'Delete',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!confirmed || !mounted) return;
    final next = _env.where((item) => item.name != entry.name).toList();
    await state.saveEnvironment(widget.project, next);
    if (mounted) setState(() => _env = next);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DefaultTabController(
        length: 2,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.78,
          child: Column(
            children: [
              const SheetHandle(),
              Padding(
                padding: const EdgeInsets.fromLTRB(Sp.page, 0, Sp.x2, Sp.x2),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Tools', style: Txt.headline),
                          const SizedBox(height: 2),
                          Text(
                            'Environment values and project skills.',
                            style: Txt.meta,
                          ),
                        ],
                      ),
                    ),
                    IconAction(
                      icon: Icons.refresh_rounded,
                      tooltip: 'Reload tools',
                      onTap: _loading ? null : _reload,
                    ),
                    IconAction(
                      icon: Icons.close_rounded,
                      tooltip: 'Close',
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
              ),
              const Hairline(),
              TabBar(
                indicatorColor: Pal.ember,
                labelColor: Pal.text,
                unselectedLabelColor: Pal.textMuted,
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: 'Environment'),
                  Tab(text: 'Project skills'),
                ],
              ),
              const Hairline(),
              Expanded(
                child: TabBarView(
                  children: [
                    _EnvTab(
                      entries: _env,
                      loading: _loading,
                      onAdd: () => _editEnv(),
                      onEdit: _editEnv,
                      onDelete: _deleteEnv,
                    ),
                    _SkillsTab(skills: _skills),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EnvTab extends StatelessWidget {
  const _EnvTab({
    required this.entries,
    required this.loading,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final List<ProjectEnvEntry> entries;
  final bool loading;
  final VoidCallback onAdd;
  final ValueChanged<ProjectEnvEntry> onEdit;
  final ValueChanged<ProjectEnvEntry> onDelete;

  @override
  Widget build(BuildContext context) {
    if (loading && entries.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 1.8),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.page, Sp.x3, Sp.page, Sp.x6),
      children: [
        Text(
          'Available to npm scripts and shell commands in this project. '
          'Secret values stay on the device; the agent only sees their names.',
          style: Txt.bodySoft.copyWith(fontSize: 12, height: 1.5),
        ),
        const SizedBox(height: Sp.x4),
        if (entries.isEmpty)
          Text(
            'No variables yet. Add the values your build or dev server expects.',
            style: Txt.meta.copyWith(height: 1.5),
          )
        else
          for (final entry in entries)
            Container(
              margin: const EdgeInsets.only(bottom: 7),
              padding: const EdgeInsets.fromLTRB(11, 8, 4, 8),
              decoration: BoxDecoration(
                color: Pal.raised,
                borderRadius: Rd.sm,
                border: Border.all(color: Pal.line),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => onEdit(entry),
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  entry.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Txt.code.copyWith(fontSize: 12),
                                ),
                              ),
                              if (entry.secret) ...[
                                const SizedBox(width: 7),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Pal.amber.withOpacity(0.12),
                                    borderRadius: Rd.pill,
                                    border: Border.all(
                                      color: Pal.amber.withOpacity(0.4),
                                    ),
                                  ),
                                  child: Text(
                                    'SECRET',
                                    style: Txt.meta.copyWith(
                                      fontSize: 8,
                                      color: Pal.amber,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            entry.secret
                                ? '•••••• value hidden'
                                : entry.value.isEmpty
                                    ? '(empty)'
                                    : entry.value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Txt.code.copyWith(
                              fontSize: 10.5,
                              color: Pal.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconAction(
                    icon: Icons.edit_outlined,
                    tooltip: 'Edit ${entry.name}',
                    size: 15,
                    onTap: () => onEdit(entry),
                  ),
                  IconAction(
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'Delete ${entry.name}',
                    size: 15,
                    color: Pal.rose,
                    onTap: () => onDelete(entry),
                  ),
                ],
              ),
            ),
        const SizedBox(height: Sp.x3),
        GhostButton(
          label: 'Add variable',
          icon: Icons.add_rounded,
          onTap: onAdd,
        ),
      ],
    );
  }
}

class _SkillsTab extends StatelessWidget {
  const _SkillsTab({required this.skills});

  final List<ProjectSkill> skills;

  @override
  Widget build(BuildContext context) {
    if (skills.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(Sp.page, Sp.x3, Sp.page, Sp.x6),
        children: [
          Text(
            'No project skills yet. Ask the agent to install one, or add a '
            'SKILL.md under .praxis/skills/.',
            style: Txt.bodySoft.copyWith(fontSize: 12, height: 1.5),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.page, Sp.x3, Sp.page, Sp.x6),
      children: [
        Text(
          'Installed in .praxis/skills. These load into every conversation for '
          'this project and can be invoked with /name.',
          style: Txt.bodySoft.copyWith(fontSize: 12, height: 1.5),
        ),
        const SizedBox(height: Sp.x3),
        for (final skill in skills)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.extension_outlined, size: 16, color: Pal.mint),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(skill.name, style: Txt.label.copyWith(fontSize: 12)),
                      if (skill.description.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          skill.description,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Txt.meta.copyWith(height: 1.4),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  humanFileSize(skill.size),
                  style: Txt.meta.copyWith(fontSize: 9),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
