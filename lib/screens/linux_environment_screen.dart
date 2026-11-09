import 'dart:async';

import 'package:flutter/material.dart';

import '../core/linux_environment.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/ui.dart';

/// Operate-mode screen: dense, legible status and controls, no decoration that
/// competes with the environment itself.
class LinuxEnvironmentScreen extends StatefulWidget {
  const LinuxEnvironmentScreen({super.key, this.project});

  final Project? project;

  @override
  State<LinuxEnvironmentScreen> createState() => _LinuxEnvironmentScreenState();
}

class _LinuxEnvironmentScreenState extends State<LinuxEnvironmentScreen> {
  bool _started = false;
  LinuxEnvironment? _linux;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _linux = AppScope.of(context).linux;
    final linux = _linux;
    if (linux != null) {
      unawaited(linux.prepare());
    }
  }

  Future<void> _refresh(LinuxEnvironment linux) async {
    await linux.refresh(projectRoot: _projectRoot());
  }

  String? _projectRoot() {
    final state = AppScope.of(context);
    final project = widget.project;
    if (project == null) return null;
    return state.fsFor(project).rootPath;
  }

  Future<void> _install(LinuxEnvironment linux, LinuxRuntime runtime) async {
    await linux.install(runtime);
    if (!mounted) return;
    final status = linux.runtimes[runtime]!;
    if (status.error.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${runtime.label}: ${status.error}')),
      );
    }
  }

  Future<void> _reset(LinuxEnvironment linux) async {
    final confirmed = await showPraxisConfirm(
      context,
      title: 'Reset Linux environment?',
      body: 'The Alpine rootfs and installed runtimes are deleted and rebuilt. '
          'Your projects and source files are never touched.',
      confirmLabel: 'Reset environment',
      cancelLabel: 'Keep it',
      destructive: true,
      icon: Icons.restart_alt_rounded,
    );
    if (!confirmed) return;
    await linux.reset();
  }

  Future<void> _confirmClearCache(LinuxEnvironment linux) async {
    final size = humanBytes(linux.snapshot.cacheBytes);
    final confirmed = await showPraxisConfirm(
      context,
      title: 'Clear ${size == '0 B' ? 'package caches' : size}?',
      body: 'Removes $size of downloaded apk archives and package-manager '
          'caches only. Installed runtimes and project files remain.',
      confirmLabel: 'Clear cache',
      cancelLabel: 'Cancel',
      icon: Icons.cleaning_services_outlined,
      details: [
        ConfirmDetail('Cached downloads', size),
        const ConfirmDetail('Runtimes', 'Stay installed'),
      ],
    );
    if (confirmed) await linux.clearCache();
  }

  @override
  Widget build(BuildContext context) {
    final linux = _linux;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              onBack: () => Navigator.of(context).maybePop(),
              onRefresh: linux == null ? null : () => _refresh(linux),
            ),
            Expanded(
              child: linux == null
                  ? const _Unavailable()
                  : AnimatedBuilder(
                      animation: linux,
                      builder: (context, _) {
                        if (linux.state == LinuxState.error) {
                          return _ErrorState(
                            error: linux.error,
                            onRetry: () => linux.prepare(force: true),
                          );
                        }
                        if (linux.state == LinuxState.preparing) {
                          return _Preparing(linux: linux);
                        }
                        return _EnvironmentBody(
                          linux: linux,
                          onRefresh: () => _refresh(linux),
                          onInstall: (runtime) => _install(linux, runtime),
                          onClearCache: () => _confirmClearCache(linux),
                          onReset: () => _reset(linux),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack, this.onRefresh});

  final VoidCallback onBack;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.x2, Sp.x2, Sp.x2, Sp.x2),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Pal.line)),
      ),
      child: Row(
        children: [
          IconAction(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Back',
            onTap: onBack,
          ),
          const SizedBox(width: 4),
          Text('Linux environment', style: Txt.title),
          const Spacer(),
          if (onRefresh != null)
            IconAction(
              icon: Icons.refresh_rounded,
              tooltip: 'Refresh resources',
              onTap: onRefresh,
            ),
          const Wordmark(size: 13, showMark: false),
        ],
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(Sp.page),
      child: EmptyState(
        icon: Icons.terminal_rounded,
        title: 'Linux is not available',
        body: 'The Alpine environment is created on Android at first launch. '
            'This build could not access the app support folder.',
      ),
    );
  }
}

class _Preparing extends StatelessWidget {
  const _Preparing({required this.linux});

  final LinuxEnvironment linux;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Sp.page),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
            const SizedBox(height: Sp.x4),
            Text(
              linux.phase.isEmpty ? 'Preparing Alpine' : linux.phase,
              style: Txt.title,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'The minirootfs is unpacked on this device. This happens once.',
              style: Txt.bodySoft,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(Sp.page),
      children: [
        EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Alpine could not start',
          body: error.isEmpty
              ? 'The bundled rootfs or proot binary is unavailable.'
              : error,
        ),
        const SizedBox(height: Sp.x3),
        EmberButton(
          label: 'Try again',
          icon: Icons.restart_alt_rounded,
          onTap: onRetry,
        ),
      ],
    );
  }
}

class _EnvironmentBody extends StatelessWidget {
  const _EnvironmentBody({
    required this.linux,
    required this.onRefresh,
    required this.onInstall,
    required this.onClearCache,
    required this.onReset,
  });

  final LinuxEnvironment linux;
  final VoidCallback onRefresh;
  final ValueChanged<LinuxRuntime> onInstall;
  final VoidCallback onClearCache;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final snapshot = linux.snapshot;
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Sp.page, Sp.x4, Sp.page, Sp.x10),
        children: [
          _AlpineCard(linux: linux),
          const SectionLabel('RESOURCE USAGE'),
          _ResourceCard(snapshot: snapshot, ready: linux.ready),
          const SectionLabel('INSTALLED RUNTIMES'),
          for (final runtime in LinuxRuntime.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _RuntimeRow(
                linux: linux,
                runtime: runtime,
                onInstall: () => onInstall(runtime),
              ),
            ),
          const SectionLabel('MAINTENANCE'),
          _MaintenanceCard(
            linux: linux,
            onClearCache: onClearCache,
            onReset: onReset,
          ),
          const SizedBox(height: Sp.x4),
          Text(
            'Alpine ${LinuxEnvironment.version} runs under proot on this '
            'device. Package names are Alpine names; use apk, not apt.',
            style: Txt.meta.copyWith(fontSize: 9.5, height: 1.55),
          ),
        ],
      ),
    );
  }
}

class _AlpineCard extends StatelessWidget {
  const _AlpineCard({required this.linux});

  final LinuxEnvironment linux;

  @override
  Widget build(BuildContext context) {
    final snapshot = linux.snapshot;
    final rootfs = snapshot.diskBytes;
    final cache = snapshot.cacheBytes.clamp(0, rootfs);
    final system = (rootfs - cache).clamp(0, rootfs);
    final project = snapshot.projectBytes;
    final total = system + cache + project;
    const capacity = 512 * 1024 * 1024;
    return Panel(
      padding: const EdgeInsets.all(Sp.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlyphBadge(
                icon: Icons.terminal_rounded,
                color: Pal.ember,
                size: 48,
                iconSize: 23,
              ),
              const SizedBox(width: Sp.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Alpine', style: Txt.title.copyWith(fontSize: 20)),
                    const SizedBox(height: 3),
                    Text(
                      'Linux ${LinuxEnvironment.version}',
                      style: Txt.meta.copyWith(fontSize: 10.5),
                    ),
                  ],
                ),
              ),
              StatusPill(
                linux.ready ? 'Ready' : 'Starting',
                color: linux.ready ? Pal.mint : Pal.amber,
              ),
              const SizedBox(width: 2),
              IconAction(
                icon: Icons.info_outline_rounded,
                tooltip: 'About this environment',
                onTap: () => _showAlpineInfo(context),
              ),
            ],
          ),
          const SizedBox(height: Sp.x4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  'Disk usage${total <= 0 ? '' : ': ${humanBytes(total)}'}',
                  style: Txt.title.copyWith(fontSize: 14),
                ),
              ),
              Text(
                total <= 0 ? 'Not measured' : humanBytes(total),
                style: Txt.meta.copyWith(fontSize: 10.5),
              ),
            ],
          ),
          const SizedBox(height: Sp.x2),
          ClipRRect(
            borderRadius: Rd.pill,
            child: SizedBox(
              height: 8,
              child: total <= 0
                  ? ColoredBox(color: Pal.raised)
                  : Row(
                      children: [
                        Expanded(
                          flex: system.clamp(1, 100000),
                          child: ColoredBox(color: Pal.rose),
                        ),
                        Expanded(
                          flex: project.clamp(0, 100000) + 1,
                          child: ColoredBox(color: Pal.mint),
                        ),
                        Expanded(
                          flex: cache.clamp(0, 100000) + 1,
                          child: ColoredBox(color: Pal.amber),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'of ${humanBytes(capacity)} rootfs capacity',
            style: Txt.meta.copyWith(fontSize: 8.5),
          ),
          const SizedBox(height: Sp.x3),
          _Legend(
            color: Pal.rose,
            text: 'System + runtimes: ${humanBytes(system)}',
          ),
          const SizedBox(height: 5),
          _Legend(
            color: Pal.mint,
            text: '${project <= 0 ? 'Project' : '1 project'}: '
                '${project <= 0 ? 'outside rootfs' : humanBytes(project)}',
          ),
          const SizedBox(height: 5),
          _Legend(
            color: Pal.amber,
            text: 'Package caches: ${humanBytes(cache)}',
          ),
        ],
      ),
    );
  }

  void _showAlpineInfo(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Pal.surface,
      builder: (_) => const _Sheet(
        title: 'Alpine ${LinuxEnvironment.version}',
        body: 'A real Alpine Linux minirootfs runs under proot. The rootfs is '
            'shared by every project. Your project is bind-mounted at '
            '/workspace; resetting the environment never deletes project files.',
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(text, style: Txt.meta.copyWith(fontSize: 9.5)),
      ],
    );
  }
}

class _ResourceCard extends StatelessWidget {
  const _ResourceCard({required this.snapshot, required this.ready});

  final LinuxSnapshot snapshot;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final ram = snapshot.ramUsedBytes;
    final cpu = snapshot.cpuPercent;
    final count = snapshot.processes.length;
    final processes = [...snapshot.processes]
      ..sort((a, b) => b.rssKb.compareTo(a.rssKb));
    return Panel(
      padding: const EdgeInsets.all(Sp.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlyphBadge(
                icon: Icons.monitor_heart_outlined,
                color: Pal.ember,
                size: 42,
                iconSize: 21,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Linux Usage',
                        style: Txt.title.copyWith(fontSize: 17)),
                    const SizedBox(height: 2),
                    Text(
                      count == 0
                          ? 'Idle · run a command to wake the guest'
                          : '$count active guest processes',
                      style: Txt.meta.copyWith(fontSize: 9.5),
                    ),
                  ],
                ),
              ),
              StatusPill(
                ready ? 'LIVE' : 'OFFLINE',
                color: ready ? Pal.mint : Pal.textDim,
              ),
            ],
          ),
          const SizedBox(height: Sp.x3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Metric(
                  icon: Icons.memory_rounded,
                  label: 'RAM',
                  badge: 'RAM',
                  value: ram == null ? '—' : humanBytes(ram),
                  detail:
                      count == 0 ? 'No guest processes' : 'Processes: $count',
                  fraction: ram == null ? 0 : null,
                  color: Pal.ember,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Metric(
                  icon: Icons.speed_rounded,
                  label: 'CPU Load',
                  badge: 'GUEST',
                  value: cpu == null ? '—' : '${cpu.toStringAsFixed(1)}%',
                  detail:
                      count == 0 ? 'No guest load yet' : 'Guest process CPU',
                  fraction: cpu == null ? 0 : (cpu / 100).clamp(0.0, 1.0),
                  color: Pal.mint,
                ),
              ),
            ],
          ),
          const SizedBox(height: Sp.x3),
          const Hairline(),
          if (processes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Sp.x4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline_rounded,
                      size: 16, color: Pal.textDim),
                  const SizedBox(width: 7),
                  Text('Ready for a command', style: Txt.meta),
                ],
              ),
            )
          else ...[
            const SizedBox(height: Sp.x1),
            const Row(
              children: [
                _ProcessHeader('PID', width: 38),
                Expanded(child: _ProcessHeader('PROCESS')),
                _ProcessHeader('USER', width: 38),
                _ProcessHeader('CPU', width: 38, right: true),
                _ProcessHeader('MEM', width: 52, right: true),
              ],
            ),
            const SizedBox(height: 2),
            for (final process in processes.take(7))
              _ProcessRow(process: process),
            const SizedBox(height: Sp.x2),
            Text(
              'Live values from inside Alpine, not the phone.',
              style: Txt.meta.copyWith(fontSize: 8.5, color: Pal.textDim),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProcessHeader extends StatelessWidget {
  const _ProcessHeader(this.text, {this.width, this.right = false});
  final String text;
  final double? width;
  final bool right;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text,
      textAlign: right ? TextAlign.right : TextAlign.left,
      style: Txt.overline.copyWith(fontSize: 8),
    );
    return width == null ? label : SizedBox(width: width, child: label);
  }
}

class _ProcessRow extends StatelessWidget {
  const _ProcessRow({required this.process});
  final LinuxProcess process;

  IconData get _icon {
    final name = process.name.toLowerCase();
    if (name.contains('apk')) return Icons.widgets_outlined;
    if (name.contains('proot')) return Icons.cloud_outlined;
    if (name.contains('sh')) return Icons.terminal_rounded;
    return Icons.memory_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.5),
      child: Row(
        children: [
          SizedBox(
            width: 38,
            child: Text(process.pid,
                style: Txt.code.copyWith(fontSize: 9, color: Pal.textMuted)),
          ),
          Expanded(
            child: Row(
              children: [
                Icon(_icon, size: 12, color: Pal.ember),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    process.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Txt.code.copyWith(fontSize: 9.5),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 38,
            child: Text(process.user,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Txt.code.copyWith(fontSize: 8.5, color: Pal.textDim)),
          ),
          SizedBox(
            width: 38,
            child: Text(process.cpu,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: Txt.code.copyWith(fontSize: 8.5, color: Pal.textMuted)),
          ),
          SizedBox(
            width: 52,
            child: Text(process.memory,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: Txt.code.copyWith(fontSize: 8.5)),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.badge,
    required this.value,
    required this.detail,
    required this.fraction,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String badge;
  final String value;
  final String detail;
  final double? fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Sp.x3),
      decoration: BoxDecoration(
        color: Pal.raised,
        borderRadius: Rd.sm,
        border: Border.all(color: Pal.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label, style: Txt.meta.copyWith(fontSize: 9.5)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.14),
                  borderRadius: Rd.pill,
                ),
                child: Text(
                  badge,
                  style: Txt.overline.copyWith(
                    fontSize: 7.5,
                    color: color,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Txt.title.copyWith(fontSize: 24, letterSpacing: -0.8),
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: Rd.pill,
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 4,
              backgroundColor: Pal.line,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Txt.meta.copyWith(fontSize: 8.5, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _RuntimeRow extends StatelessWidget {
  const _RuntimeRow({
    required this.linux,
    required this.runtime,
    required this.onInstall,
  });

  final LinuxEnvironment linux;
  final LinuxRuntime runtime;
  final VoidCallback onInstall;

  IconData get _icon => switch (runtime) {
        LinuxRuntime.node => Icons.hexagon_outlined,
        LinuxRuntime.python => Icons.code_rounded,
        LinuxRuntime.php => Icons.web_rounded,
        LinuxRuntime.go => Icons.bolt_rounded,
      };

  Color get _color => switch (runtime) {
        LinuxRuntime.node => Pal.mint,
        LinuxRuntime.python => Pal.sky,
        LinuxRuntime.php => Pal.ember,
        LinuxRuntime.go => Pal.amber,
      };

  @override
  Widget build(BuildContext context) {
    final status = linux.runtimes[runtime]!;
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: Sp.x3, vertical: 11),
      child: Row(
        children: [
          GlyphBadge(icon: _icon, color: _color, size: 42, iconSize: 20),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(runtime.label, style: Txt.title.copyWith(fontSize: 15)),
                const SizedBox(height: 2),
                Text(
                  status.busy
                      ? 'Installing packages from apk…'
                      : status.installed
                          ? (status.version.isEmpty
                              ? 'Installed'
                              : status.version)
                          : 'Not installed · ${runtime.packages.length} packages',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Txt.meta.copyWith(fontSize: 9.5),
                ),
              ],
            ),
          ),
          if (status.busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (status.installed)
            StatusPill('Installed', color: Pal.mint)
          else
            GestureDetector(
              onTap: onInstall,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  borderRadius: Rd.sm,
                  border: Border.all(color: Pal.mint.withOpacity(0.45)),
                  color: Pal.mint.withOpacity(0.07),
                ),
                child: Row(
                  children: [
                    Icon(Icons.download_rounded, size: 14, color: Pal.mint),
                    const SizedBox(width: 5),
                    Text('Install',
                        style: Txt.label.copyWith(
                            color: Pal.mint, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          const SizedBox(width: 2),
          IconAction(
            icon: Icons.info_outline_rounded,
            tooltip: '${runtime.label} details',
            size: 18,
            onTap: () => _showRuntime(context, runtime, status),
          ),
        ],
      ),
    );
  }

  void _showRuntime(
    BuildContext context,
    LinuxRuntime runtime,
    LinuxRuntimeStatus status,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Pal.surface,
      builder: (_) => _RuntimeSheet(
        runtime: runtime,
        status: status,
        onInstall: () {
          Navigator.of(context).pop();
          onInstall();
        },
      ),
    );
  }
}

class _RuntimeSheet extends StatelessWidget {
  const _RuntimeSheet({
    required this.runtime,
    required this.status,
    required this.onInstall,
  });

  final LinuxRuntime runtime;
  final LinuxRuntimeStatus status;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.84;
    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              const SheetHandle(),
              Flexible(
                fit: FlexFit.loose,
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.fromLTRB(Sp.x4, Sp.x4, Sp.x4, Sp.x3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(runtime.label,
                              style: Txt.headline.copyWith(fontSize: 24)),
                          const Spacer(),
                          IconAction(
                            icon: Icons.close_rounded,
                            tooltip: 'Close',
                            onTap: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          StatusPill(
                            status.installed ? 'Installed' : 'Not installed',
                            color: status.installed ? Pal.mint : Pal.textDim,
                          ),
                          if (status.version.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                status.version,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Txt.meta.copyWith(fontSize: 10),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: Sp.x4),
                      if (status.error.isNotEmpty) ...[
                        Text(status.error,
                            style: Txt.bodySoft.copyWith(color: Pal.rose)),
                        const SizedBox(height: Sp.x3),
                      ],
                      SectionLabel('PACKAGES',
                          trailing: Text('${runtime.packages.length}',
                              style: Txt.meta)),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final package in runtime.packages)
                            MonoChip(package, tint: Pal.textMuted),
                        ],
                      ),
                      SectionLabel(
                        'USED BY TEMPLATES',
                        trailing: Text('${runtime.templates.length}',
                            style: Txt.meta),
                      ),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final template in runtime.templates)
                            MonoChip(template,
                                icon: Icons.code_rounded, tint: Pal.sky),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (!status.installed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Sp.x4,
                    Sp.x2,
                    Sp.x4,
                    Sp.x4,
                  ),
                  child: EmberButton(
                    label: 'Install',
                    icon: Icons.download_rounded,
                    onTap: status.busy ? null : onInstall,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MaintenanceCard extends StatelessWidget {
  const _MaintenanceCard({
    required this.linux,
    required this.onClearCache,
    required this.onReset,
  });

  final LinuxEnvironment linux;
  final VoidCallback onClearCache;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.fromLTRB(Sp.x3, Sp.x2, Sp.x3, Sp.x2),
      child: Column(
        children: [
          Row(
            children: [
              GlyphBadge(
                icon: Icons.bolt_rounded,
                color: Pal.amber,
                size: 34,
                iconSize: 17,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Package caching',
                        style: Txt.title.copyWith(fontSize: 14)),
                    const SizedBox(height: 2),
                    Text('Keep apk downloads between sessions',
                        style: Txt.meta.copyWith(fontSize: 9.5)),
                  ],
                ),
              ),
              IconAction(
                icon: Icons.info_outline_rounded,
                tooltip: 'How caching works',
                size: 17,
                onTap: () => _showCaching(context),
              ),
              Switch(
                value: linux.packageCaching,
                onChanged: linux.setPackageCaching,
              ),
            ],
          ),
          const Hairline(),
          _MaintenanceRow(
            icon: Icons.cleaning_services_outlined,
            title: 'Clear cache',
            body:
                '${humanBytes(linux.snapshot.cacheBytes)} cached · runtimes stay installed',
            onTap: onClearCache,
          ),
          const Hairline(),
          _MaintenanceRow(
            icon: Icons.restart_alt_rounded,
            title: 'Reset Linux environment',
            body: 'Full reinstall · your code is safe',
            destructive: true,
            onTap: onReset,
          ),
        ],
      ),
    );
  }

  void _showCaching(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Pal.surface,
      builder: (_) => const _CachingSheet(),
    );
  }
}

class _MaintenanceRow extends StatelessWidget {
  const _MaintenanceRow({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            GlyphBadge(
              icon: icon,
              color: destructive ? Pal.rose : Pal.textMuted,
              size: 34,
              iconSize: 17,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Txt.title.copyWith(
                      fontSize: 14,
                      color: destructive ? Pal.rose : Pal.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(body, style: Txt.meta.copyWith(fontSize: 9.5)),
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

class _CachingSheet extends StatelessWidget {
  const _CachingSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x4, Sp.x4, Sp.x5),
        children: [
          Row(
            children: [
              Text('How caching works',
                  style: Txt.headline.copyWith(fontSize: 22)),
              const Spacer(),
              IconAction(
                icon: Icons.close_rounded,
                tooltip: 'Close',
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: Sp.x3),
          Text(
            'The first project of each type installs the runtime it needs '
            '(for example Node.js) — this takes time and requires internet. '
            'After that it is cached on the device, and later projects of the '
            'same type start faster.',
            style: Txt.bodySoft.copyWith(height: 1.6),
          ),
          const SizedBox(height: Sp.x4),
          Text(
            'Package caching only controls downloaded apk archives and package '
            'manager downloads. Turning it off does not stop an active '
            'install; it clears those downloads the next time the environment '
            'starts. Installed runtimes and project files are never removed.',
            style: Txt.bodySoft.copyWith(height: 1.6),
          ),
          const SizedBox(height: Sp.x4),
          const _InfoLine(
            icon: Icons.bolt_rounded,
            title: 'Shared runtime cache',
            body: 'Installed Node.js, Python, PHP and Go runtimes persist.',
          ),
          const _InfoLine(
            icon: Icons.download_for_offline_outlined,
            title: 'Package downloads',
            body: 'apk archives speed up repeated installs.',
          ),
          const _InfoLine(
            icon: Icons.shield_outlined,
            title: 'Safe cleanup',
            body: 'Clearing cache only frees storage.',
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Pal.amber),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Txt.label.copyWith(fontSize: 12)),
                const SizedBox(height: 2),
                Text(body, style: Txt.meta.copyWith(fontSize: 9.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x4, Sp.x4, Sp.x5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title, style: Txt.headline.copyWith(fontSize: 22)),
                const Spacer(),
                IconAction(
                  icon: Icons.close_rounded,
                  tooltip: 'Close',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: Sp.x3),
            Text(body, style: Txt.bodySoft.copyWith(height: 1.6)),
          ],
        ),
      ),
    );
  }
}
