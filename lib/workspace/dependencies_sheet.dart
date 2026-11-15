import 'package:flutter/material.dart';

import '../core/dependencies.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/ui.dart';

class DependenciesSheet extends StatefulWidget {
  const DependenciesSheet({super.key, required this.project});

  final Project project;

  @override
  State<DependenciesSheet> createState() => _DependenciesSheetState();
}

class _DependenciesSheetState extends State<DependenciesSheet> {
  DependencyReport? _report;
  DependencyAudit? _audit;
  String _error = '';
  bool _loaded = false;
  bool _loading = false;
  bool _checking = false;
  bool _acting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _load();
  }

  Future<void> _load({bool registry = false}) async {
    if (_loading || _checking) return;
    setState(() {
      _loading = true;
      if (registry) _checking = true;
      _error = '';
    });
    final state = AppScope.of(context);
    try {
      final report = await state.dependencyReport(widget.project);
      DependencyAudit? audit;
      if (registry && report.ecosystem == DependencyEcosystem.node) {
        audit = await state.auditDependencies(widget.project);
      }
      if (!mounted) return;
      setState(() {
        _report = report;
        if (audit != null) _audit = audit;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _checking = false;
        });
      }
    }
  }

  Future<void> _checkRegistry() => _load(registry: true);

  Future<void> _repair() async {
    final report = _report;
    if (report == null || _acting) return;
    final approved = await showPraxisConfirm(
      context,
      title: 'Clean install dependencies?',
      body: 'Remove the current dependency folder and install from the '
          'lockfile. This is the safest repair for an incomplete install.',
      confirmLabel: 'Clean install',
      icon: Icons.build_circle_outlined,
      details: [
        ConfirmDetail('Manager', report.manager),
        ConfirmDetail('Command', report.repairCommand),
        if (report.installBytes > 0)
          ConfirmDetail('Current install', humanSize(report.installBytes)),
      ],
      note: 'Package downloads are kept in the shared cache. Source files are '
          'not changed.',
    );
    if (!approved || !mounted) return;
    setState(() => _acting = true);
    try {
      final message =
          await AppScope.of(context).repairDependencies(widget.project);
      if (!mounted) return;
      _snack(message);
      if (mounted) setState(() => _audit = null);
      await _load();
    } catch (error) {
      if (mounted) _snack('$error');
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _repairCache() async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      final message =
          await AppScope.of(context).repairDependencyCache(widget.project);
      if (!mounted) return;
      _snack(message);
      if (mounted) setState(() => _audit = null);
      await _load();
    } catch (error) {
      if (mounted) _snack('$error');
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _update(InstalledDependency package) async {
    if (_acting) return;
    final approved = await showPraxisConfirm(
      context,
      title: 'Update ${package.name}?',
      body: 'Install the newest published version and update the manifest.',
      confirmLabel: 'Update',
      icon: Icons.upgrade_rounded,
      details: [
        ConfirmDetail('Installed', package.version),
        if (_audit?.latest[package.name] != null)
          ConfirmDetail('Latest', _audit!.latest[package.name]!),
      ],
      note: 'Run the project checks after a major version update.',
    );
    if (!approved || !mounted) return;
    setState(() => _acting = true);
    try {
      final message = await AppScope.of(context)
          .updateDependency(widget.project, package.name);
      if (!mounted) return;
      _snack(message);
      if (mounted) setState(() => _audit = null);
      await _load();
    } catch (error) {
      if (mounted) _snack('$error');
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _remove(InstalledDependency package) async {
    if (_acting) return;
    final approved = await showPraxisConfirm(
      context,
      title: 'Remove ${package.name}?',
      body: 'Uninstall this package and remove it from the project manifest.',
      confirmLabel: 'Remove',
      destructive: true,
      icon: Icons.delete_outline_rounded,
      details: [ConfirmDetail('Installed', package.version)],
      note: 'Anything that imports this package will fail until the code is '
          'updated.',
    );
    if (!approved || !mounted) return;
    setState(() => _acting = true);
    try {
      final message = await AppScope.of(context)
          .removeDependency(widget.project, package.name);
      if (!mounted) return;
      _snack(message);
      if (mounted) setState(() => _audit = null);
      await _load();
    } catch (error) {
      if (mounted) _snack('$error');
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.9,
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
                        Text('Dependencies', style: Txt.headline),
                        const SizedBox(height: 2),
                        Text(
                          report?.summary ?? 'Reading package metadata…',
                          style: Txt.meta,
                        ),
                      ],
                    ),
                  ),
                  if (_loading || _acting)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 1.6),
                      ),
                    )
                  else
                    IconAction(
                      icon: Icons.refresh_rounded,
                      tooltip: 'Scan dependencies again',
                      onTap: _load,
                    ),
                  IconAction(
                    icon: Icons.close_rounded,
                    tooltip: 'Close',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
            if (report != null) _Header(report: report),
            if (report?.hasEcosystem ?? false)
              _Actions(
                report: report!,
                audit: _audit,
                checking: _checking,
                busy: _acting,
                onRepair: _repair,
                onCache: _repairCache,
                onCheck: _checkRegistry,
              ),
            const Hairline(),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(Sp.page),
                child: Panel(
                  borderColor: Pal.rose.withOpacity(0.4),
                  child: Text(_error,
                      style: Txt.bodySoft.copyWith(color: Pal.rose)),
                ),
              ),
            Expanded(
              child: report == null
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 1.8),
                      ),
                    )
                  : !report.hasEcosystem
                      ? const _EmptyDependencies()
                      : DefaultTabController(
                          length: 2,
                          child: Column(
                            children: [
                              TabBar(
                                indicatorColor: Pal.ember,
                                labelColor: Pal.text,
                                unselectedLabelColor: Pal.textMuted,
                                dividerColor: Colors.transparent,
                                tabs: [
                                  Tab(text: 'Health (${report.issues.length})'),
                                  Tab(
                                    text: 'Installed (${report.packageCount})',
                                  ),
                                ],
                              ),
                              const Hairline(),
                              Expanded(
                                child: TabBarView(
                                  children: [
                                    _HealthTab(
                                      report: report,
                                      onRepair: _repair,
                                      onCache: _repairCache,
                                    ),
                                    _InstalledTab(
                                      report: report,
                                      audit: _audit,
                                      busy: _acting,
                                      onUpdate: _update,
                                      onRemove: _remove,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.report});

  final DependencyReport report;

  @override
  Widget build(BuildContext context) {
    if (!report.hasEcosystem) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.page, 0, Sp.page, Sp.x2),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          MonoChip(
            report.manager,
            icon: Icons.inventory_2_outlined,
            tint: Pal.ember,
          ),
          if (report.lockfile.isNotEmpty)
            MonoChip(report.lockfile, icon: Icons.lock_outline_rounded),
          MonoChip(
            report.runtimeReady ? 'runtime ready' : 'runtime missing',
            icon: report.runtimeReady
                ? Icons.check_circle_outline_rounded
                : Icons.error_outline_rounded,
            tint: report.runtimeReady ? Pal.mint : Pal.rose,
          ),
          if (report.directCount > 0) MonoChip('${report.directCount} direct'),
          if (report.installBytes > 0)
            MonoChip(humanSize(report.installBytes),
                icon: Icons.storage_rounded),
          if (report.packageCount > 0)
            MonoChip('${report.packageCount} packages'),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.report,
    required this.audit,
    required this.checking,
    required this.busy,
    required this.onRepair,
    required this.onCache,
    required this.onCheck,
  });

  final DependencyReport report;
  final DependencyAudit? audit;
  final bool checking;
  final bool busy;
  final VoidCallback onRepair;
  final VoidCallback onCache;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.page, 0, Sp.page, Sp.x3),
      child: Row(
        children: [
          Expanded(
            child: _ActionButton(
              icon: Icons.build_circle_outlined,
              label: 'Clean install',
              onTap: busy ? null : onRepair,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _ActionButton(
              icon: Icons.cleaning_services_outlined,
              label: 'Caches',
              onTap: busy ? null : onCache,
            ),
          ),
          if (report.ecosystem == DependencyEcosystem.node) ...[
            const SizedBox(width: 6),
            Expanded(
              child: _ActionButton(
                icon: Icons.travel_explore_rounded,
                label: checking ? 'Checking…' : 'Registry',
                onTap: busy || checking ? null : onCheck,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 35,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Pal.raised,
          borderRadius: Rd.sm,
          border: Border.all(color: Pal.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: enabled ? Pal.textMuted : Pal.textDim),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Txt.label.copyWith(
                  fontSize: 10.5,
                  color: enabled ? Pal.text : Pal.textDim,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthTab extends StatelessWidget {
  const _HealthTab({
    required this.report,
    required this.onRepair,
    required this.onCache,
  });

  final DependencyReport report;
  final VoidCallback onRepair;
  final VoidCallback onCache;

  @override
  Widget build(BuildContext context) {
    if (report.issues.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(Sp.page, Sp.x6, Sp.page, Sp.x6),
        children: [
          Panel(
            borderColor: Pal.mint.withOpacity(0.35),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Pal.mint, size: 22),
                const SizedBox(width: Sp.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Nothing to fix', style: Txt.title),
                      const SizedBox(height: 3),
                      Text(
                        '${report.manager} metadata is consistent, the runtime '
                        'is available and the install looks complete.',
                        style: Txt.bodySoft.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Sp.x4),
          Text(
            'Registry checks are separate. Use Registry above to compare '
            'outdated versions and advisories without slowing down the '
            'offline diagnosis.',
            style: Txt.meta.copyWith(fontSize: 10, height: 1.45),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(Sp.page, Sp.x3, Sp.page, Sp.x6),
      itemCount: report.issues.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final issue = report.issues[index];
        final color = switch (issue.level) {
          DependencyIssueLevel.error => Pal.rose,
          DependencyIssueLevel.warning => Pal.amber,
          DependencyIssueLevel.info => Pal.sky,
        };
        final icon = switch (issue.level) {
          DependencyIssueLevel.error => Icons.error_outline_rounded,
          DependencyIssueLevel.warning => Icons.warning_amber_rounded,
          DependencyIssueLevel.info => Icons.info_outline_rounded,
        };
        return Panel(
          padding: const EdgeInsets.all(Sp.x3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: Sp.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(issue.title, style: Txt.title.copyWith(fontSize: 13)),
                    const SizedBox(height: 3),
                    Text(
                      issue.detail,
                      style: Txt.bodySoft.copyWith(fontSize: 11.5),
                    ),
                    if (issue.fix != DependencyFix.none) ...[
                      const SizedBox(height: 7),
                      GestureDetector(
                        onTap: issue.fix == DependencyFix.repairCache
                            ? onCache
                            : issue.fix == DependencyFix.cleanInstall
                                ? onRepair
                                : null,
                        behavior: HitTestBehavior.opaque,
                        child: Text(
                          issue.fix == DependencyFix.installRuntime
                              ? 'Install the runtime from the Linux tab'
                              : issue.fix == DependencyFix.repairCache
                                  ? 'Repair package cache'
                                  : 'Run a clean install',
                          style: Txt.label.copyWith(
                            color: Pal.ember,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InstalledTab extends StatelessWidget {
  const _InstalledTab({
    required this.report,
    required this.audit,
    required this.busy,
    required this.onUpdate,
    required this.onRemove,
  });

  final DependencyReport report;
  final DependencyAudit? audit;
  final bool busy;
  final ValueChanged<InstalledDependency> onUpdate;
  final ValueChanged<InstalledDependency> onRemove;

  @override
  Widget build(BuildContext context) {
    if (report.installed.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Sp.page),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inventory_2_outlined, size: 32, color: Pal.textDim),
              const SizedBox(height: Sp.x3),
              Text('No installed packages found', style: Txt.title),
              const SizedBox(height: 5),
              Text(
                report.ecosystem == DependencyEcosystem.node
                    ? 'Run a clean install, then scan again to see installed '
                        'versions and sizes.'
                    : 'Create the virtual environment and install the '
                        'requirements, then scan again.',
                textAlign: TextAlign.center,
                style: Txt.bodySoft.copyWith(fontSize: 12),
              ),
              const SizedBox(height: Sp.x4),
              Text(
                report.repairCommand,
                textAlign: TextAlign.center,
                style: Txt.code.copyWith(fontSize: 10.5, color: Pal.textMuted),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        if (audit != null) _AuditBanner(audit: audit!),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(Sp.page, Sp.x2, Sp.page, Sp.x6),
            itemCount: report.installed.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: Pal.line),
            itemBuilder: (context, index) {
              final package = report.installed[index];
              final latest = audit?.latest[package.name];
              final severity = audit?.severities[package.name];
              final outdated = latest != null && latest != package.version;
              return _PackageRow(
                package: package,
                latest: outdated ? latest : '',
                severity: severity ?? '',
                busy: busy,
                onUpdate: () => onUpdate(package),
                onRemove: () => onRemove(package),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AuditBanner extends StatelessWidget {
  const _AuditBanner({required this.audit});

  final DependencyAudit audit;

  @override
  Widget build(BuildContext context) {
    final hasVulns = audit.totalVulnerabilities > 0;
    final color = hasVulns ? Pal.rose : Pal.mint;
    return Container(
      margin: const EdgeInsets.fromLTRB(Sp.page, Sp.x2, Sp.page, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: Rd.sm,
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(
            hasVulns ? Icons.gpp_maybe_outlined : Icons.verified_outlined,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              audit.error.isNotEmpty
                  ? audit.error
                  : '${audit.outdatedCount} outdated · '
                      '${audit.totalVulnerabilities} '
                      '${audit.totalVulnerabilities == 1 ? 'advisory' : 'advisories'}',
              style: Txt.meta.copyWith(fontSize: 10, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _PackageRow extends StatelessWidget {
  const _PackageRow({
    required this.package,
    required this.latest,
    required this.severity,
    required this.busy,
    required this.onUpdate,
    required this.onRemove,
  });

  final InstalledDependency package;
  final String latest;
  final String severity;
  final bool busy;
  final VoidCallback onUpdate;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final vuln = severity.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        package.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Txt.code.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (package.direct) ...[
                      const SizedBox(width: 6),
                      MonoChip('direct', tint: Pal.ember, iconSize: 9),
                    ],
                    if (package.scope.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      MonoChip(package.scope),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(package.version,
                        style: Txt.meta.copyWith(fontSize: 9.5)),
                    if (latest.isNotEmpty) ...[
                      const SizedBox(width: 5),
                      Text('→ $latest',
                          style: Txt.meta.copyWith(
                            fontSize: 9.5,
                            color: Pal.amber,
                          )),
                    ],
                    if (vuln) ...[
                      const SizedBox(width: 7),
                      Text(
                        severity.toUpperCase(),
                        style: Txt.meta.copyWith(
                          fontSize: 8.5,
                          letterSpacing: 0.6,
                          fontWeight: FontWeight.w700,
                          color: Pal.rose,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (package.direct)
            PopupMenuButton<String>(
              enabled: !busy,
              tooltip: 'Package actions',
              color: Pal.overlay,
              icon: Icon(Icons.more_horiz_rounded,
                  size: 18, color: Pal.textMuted),
              onSelected: (value) {
                if (value == 'update') onUpdate();
                if (value == 'remove') onRemove();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'update',
                  child: Text('Update to latest',
                      style: Txt.body.copyWith(fontSize: 13)),
                ),
                PopupMenuItem(
                  value: 'remove',
                  child: Text('Uninstall',
                      style: Txt.body.copyWith(fontSize: 13, color: Pal.rose)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _EmptyDependencies extends StatelessWidget {
  const _EmptyDependencies();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Sp.page),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 34, color: Pal.textDim),
            const SizedBox(height: Sp.x3),
            Text('No dependency manifest', style: Txt.title),
            const SizedBox(height: 5),
            Text(
              'Add a package.json, requirements.txt or pyproject.toml to use '
              'the dependency doctor. Flutter packages are managed by '
              'pubspec.yaml in the Shell.',
              textAlign: TextAlign.center,
              style: Txt.bodySoft.copyWith(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
