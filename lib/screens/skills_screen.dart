import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/skill_discovery.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

class SkillsScreen extends StatefulWidget {
  const SkillsScreen({super.key});

  @override
  State<SkillsScreen> createState() => _SkillsScreenState();
}

class _SkillsScreenState extends State<SkillsScreen> {
  final _search = TextEditingController();
  List<SkillRepository> _repos = const [];
  bool _searching = false;
  bool _installing = false;
  int _page = 1;
  String? _error;
  String? _status;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
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
                  Text('Skills', style: Txt.title),
                  const Spacer(),
                  IconAction(
                    icon: Icons.add_rounded,
                    tooltip: 'Create skill',
                    color: Pal.ember,
                    onTap: () => _editSkill(state.newSkill()),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Sp.page, 0, Sp.page, Sp.x10),
                children: [
                  const SizedBox(height: Sp.x2),
                  Panel(
                    color: Pal.raised,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GlyphBadge(
                          icon: Icons.auto_awesome_outlined,
                          color: Pal.ember,
                          size: 34,
                          iconSize: 17,
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Reusable instructions',
                                  style: Txt.title.copyWith(fontSize: 14)),
                              const SizedBox(height: 3),
                              Text(
                                'Enabled skills are added to every prompt. '
                                'Write one yourself, import a file, or install '
                                'a public SKILL.md.',
                                style: Txt.bodySoft.copyWith(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SectionLabel(
                    'INSTALLED',
                    trailing: Text(
                      '${state.skills.where((skill) => skill.enabled).length} on',
                      style: Txt.meta,
                    ),
                  ),
                  if (state.skills.isEmpty)
                    const EmptyState(
                      icon: Icons.auto_awesome_outlined,
                      title: 'No skills yet',
                      body: 'Create a short instruction set for the way you '
                          'like the agent to work.',
                    )
                  else
                    for (final skill in state.skills)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _SkillCard(
                          skill: skill,
                          onToggle: (value) => state.saveSkill(
                            skill.copyWith(enabled: value),
                          ),
                          onEdit: () => _editSkill(skill),
                        ),
                      ),
                  const SizedBox(height: Sp.x2),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      GhostButton(
                        label: 'Create skill',
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
                  const SectionLabel('DISCOVER ONLINE'),
                  Text(
                    'Search public GitHub repositories for skills. Opening a '
                    'repository lists its SKILL.md files, and installing one '
                    'adds it to this device. GitHub’s free API allows a limited '
                    'number of anonymous requests per hour; add a GitHub token '
                    'in Integrations for more.',
                    style: Txt.bodySoft.copyWith(fontSize: 12),
                  ),
                  const SizedBox(height: Sp.x3),
                  TextField(
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _searchOnline(),
                    style: Txt.body.copyWith(fontSize: 13),
                    cursorColor: Pal.ember,
                    decoration: appField(
                      'e.g. react, testing, writing',
                      suffix: IconAction(
                        icon: Icons.search_rounded,
                        tooltip: 'Search skills',
                        color: Pal.ember,
                        onTap: _searching || _installing ? null : _searchOnline,
                      ),
                    ),
                  ),
                  const SizedBox(height: Sp.x3),
                  if (_searching)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: Sp.x3),
                      child: LinearProgressIndicator(
                        minHeight: 2,
                        color: Pal.ember,
                        backgroundColor: Pal.raised,
                      ),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Sp.x2),
                      child: Text(
                        _error!,
                        style: Txt.bodySoft.copyWith(color: Pal.rose),
                      ),
                    ),
                  if (_status != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Sp.x2),
                      child: Text(
                        _status!,
                        style: Txt.bodySoft.copyWith(color: Pal.mint),
                      ),
                    ),
                  if (!_searching && _repos.isEmpty && _error == null)
                    Text(
                      'Results from GitHub will appear here.',
                      style: Txt.meta.copyWith(fontSize: 10),
                    )
                  else ...[
                    for (final repo in _repos)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: _RepositoryCard(
                          repository: repo,
                          onTap: _installing ? null : () => _openRepo(repo),
                        ),
                      ),
                    if (_repos.length >= 12 && !_searching)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: GhostButton(
                          label: 'Load 12 more',
                          icon: Icons.expand_more_rounded,
                          onTap: () => _searchOnline(more: true),
                        ),
                      ),
                  ],
                  if (_installing)
                    Padding(
                      padding: const EdgeInsets.only(top: Sp.x2),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Pal.ember,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('Fetching SKILL.md…', style: Txt.meta),
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

  Future<void> _searchOnline({bool more = false}) async {
    if (_searching || _installing) return;
    final nextPage = more ? _page + 1 : 1;
    setState(() {
      _searching = true;
      _error = null;
      _status = null;
    });
    final state = AppScope.of(context);
    try {
      final repos = await SkillDiscovery(
        client: state.httpClient,
        token: state.activeGithub?.token ?? '',
      ).search(_search.text, page: nextPage);
      if (!mounted) return;
      setState(() {
        _page = nextPage;
        _repos = more ? [..._repos, ...repos] : repos;
        _status = repos.isEmpty
            ? 'No more repositories with a SKILL.md matched that search.'
            : null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        if (!more) _repos = const [];
      });
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _openRepo(SkillRepository repo) async {
    setState(() {
      _error = null;
      _status = null;
      _installing = true;
    });
    final state = AppScope.of(context);
    try {
      final skills = await SkillDiscovery(
        client: state.httpClient,
        token: state.activeGithub?.token ?? '',
      ).skillsIn(repo);
      if (!mounted) return;
      setState(() => _installing = false);
      if (skills.isEmpty) {
        setState(() => _status = 'No SKILL.md files in ${repo.fullName}.');
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        backgroundColor: Pal.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => _SkillPickerSheet(
          repo: repo,
          skills: skills,
          installed: {
            for (final skill in state.skills)
              if (skill.source.isNotEmpty) '${skill.source}|${skill.name}',
          },
          onInstall: _install,
          onPreview: (discovered) async {
            final skill = await SkillDiscovery(
              client: state.httpClient,
              token: state.activeGithub?.token ?? '',
            ).fetchSkill(discovered);
            return skill.instructions;
          },
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _installing = false;
        _error = '$error';
      });
    }
  }

  Future<bool> _install(DiscoveredSkill discovered) async {
    setState(() {
      _installing = true;
      _error = null;
      _status = null;
    });
    final state = AppScope.of(context);
    try {
      final skill = await SkillDiscovery(
        client: state.httpClient,
        token: state.activeGithub?.token ?? '',
      ).fetchSkill(discovered);
      await state.saveSkill(skill);
      if (!mounted) return false;
      setState(() => _status = 'Installed “${skill.name}”.');
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() => _error = '$error');
      return false;
    } finally {
      if (mounted) setState(() => _installing = false);
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
      setState(() => _error = 'Could not open the picker: $error');
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
    setState(() {
      _status = imported == 0
          ? 'No .md or .txt file was imported.'
          : 'Imported $imported skill${imported == 1 ? '' : 's'}.';
    });
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
        content: SingleChildScrollView(
          child: Column(
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
                minLines: 4,
                maxLines: 10,
                decoration: appField('Instructions added to the agent prompt'),
              ),
            ],
          ),
        ),
        actions: [
          if (skill.name.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              style: TextButton.styleFrom(foregroundColor: Pal.rose),
              child: const Text('Delete'),
            ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: name,
            builder: (_, nameValue, __) =>
                ValueListenableBuilder<TextEditingValue>(
              valueListenable: instructions,
              builder: (_, instructionsValue, __) => TextButton(
                onPressed: nameValue.text.trim().isNotEmpty &&
                        instructionsValue.text.trim().isNotEmpty
                    ? () => Navigator.of(dialogContext).pop(true)
                    : null,
                child: const Text('Save'),
              ),
            ),
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
}

class _SkillCard extends StatelessWidget {
  const _SkillCard({
    required this.skill,
    required this.onToggle,
    required this.onEdit,
  });

  final Skill skill;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: Sp.x3, vertical: Sp.x2),
      child: Row(
        children: [
          GlyphBadge(
            icon: Icons.auto_awesome_rounded,
            color: skill.enabled ? Pal.ember : Pal.textDim,
            size: 31,
            iconSize: 15,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(skill.name, style: Txt.title.copyWith(fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  skill.source.isNotEmpty
                      ? '${skill.source} · ${skill.instructions}'
                      : skill.instructions,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Txt.meta.copyWith(height: 1.4),
                ),
              ],
            ),
          ),
          Switch(
            value: skill.enabled,
            onChanged: onToggle,
          ),
          IconAction(
            icon: Icons.edit_outlined,
            tooltip: 'Edit skill',
            size: 17,
            onTap: onEdit,
          ),
        ],
      ),
    );
  }
}

class _RepositoryCard extends StatelessWidget {
  const _RepositoryCard({required this.repository, required this.onTap});

  final SkillRepository repository;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Panel(
        padding: const EdgeInsets.symmetric(
          horizontal: Sp.x3,
          vertical: Sp.x3,
        ),
        child: Row(
          children: [
            GlyphBadge(
              icon: Icons.folder_copy_outlined,
              color: Pal.textMuted,
              size: 32,
              iconSize: 15,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    repository.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Txt.label.copyWith(
                      color: Pal.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                  if (repository.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      repository.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Txt.meta.copyWith(fontSize: 9.5, height: 1.35),
                    ),
                  ],
                  const SizedBox(height: 3),
                  Text(
                    '★ ${repository.stars}  ·  browse SKILL.md',
                    style: Txt.meta.copyWith(fontSize: 9),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: Pal.textDim),
          ],
        ),
      ),
    );
  }
}

class _SkillPickerSheet extends StatefulWidget {
  const _SkillPickerSheet({
    required this.repo,
    required this.skills,
    required this.installed,
    required this.onInstall,
    required this.onPreview,
  });

  final SkillRepository repo;
  final List<DiscoveredSkill> skills;
  final Set<String> installed;
  final Future<bool> Function(DiscoveredSkill) onInstall;
  final Future<String> Function(DiscoveredSkill) onPreview;

  @override
  State<_SkillPickerSheet> createState() => _SkillPickerSheetState();
}

class _SkillPickerSheetState extends State<_SkillPickerSheet> {
  final Set<String> _justInstalled = {};
  String? _installing;

  String _key(DiscoveredSkill skill) =>
      '${skill.repository.fullName}|${skill.name}';

  bool _isInstalled(DiscoveredSkill skill) =>
      _justInstalled.contains(_key(skill)) ||
      widget.installed.contains(_key(skill));

  Future<void> _installSkill(DiscoveredSkill skill) async {
    if (_installing != null) return;
    setState(() => _installing = skill.path);
    final ok = await widget.onInstall(skill);
    if (!mounted) return;
    setState(() {
      _installing = null;
      if (ok) _justInstalled.add(_key(skill));
    });
  }

  Future<void> _showPreview(DiscoveredSkill skill) async {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Pal.surface,
        title: Text(skill.name),
        content: SizedBox(
          width: 460,
          child: FutureBuilder<String>(
            future: widget.onPreview(skill),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SizedBox(
                  height: 80,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return Text('${snapshot.error}', style: Txt.bodySoft);
              }
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${skill.repository.fullName} · ${skill.path}',
                      style: Txt.meta.copyWith(fontSize: 9.5),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.data ?? '',
                      style: Txt.body.copyWith(height: 1.5),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: _isInstalled(skill)
                ? null
                : () {
                    Navigator.of(dialogContext).pop();
                    _installSkill(skill);
                  },
            child: Text(_isInstalled(skill) ? 'Installed' : 'Install'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      builder: (context, scrollController) => Column(
        children: [
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.x5, 0, Sp.x5, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(widget.repo.fullName,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                Text('${widget.skills.length} skills', style: Txt.meta),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(Sp.x3, 0, Sp.x3, Sp.x6),
              itemCount: widget.skills.length,
              itemBuilder: (context, index) {
                final skill = widget.skills[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: GestureDetector(
                    onTap: () => _showPreview(skill),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 11,
                      ),
                      child: Row(
                        children: [
                          GlyphBadge(
                            icon: Icons.auto_awesome_outlined,
                            color: Pal.ember,
                            size: 30,
                            iconSize: 14,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(skill.name,
                                    style: Txt.label.copyWith(
                                      color: Pal.text,
                                      fontWeight: FontWeight.w600,
                                    )),
                                const SizedBox(height: 2),
                                Text(
                                  skill.path,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Txt.meta.copyWith(fontSize: 9),
                                ),
                              ],
                            ),
                          ),
                          if (_isInstalled(skill))
                            Icon(Icons.check_circle_rounded,
                                size: 18, color: Pal.mint)
                          else if (_installing == skill.path)
                            const SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            GestureDetector(
                              onTap: () => _installSkill(skill),
                              child: Icon(Icons.download_rounded,
                                  size: 18, color: Pal.ember),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
