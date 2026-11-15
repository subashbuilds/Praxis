import 'package:flutter/material.dart';

import '../core/background_jobs.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

class JobsSheet extends StatelessWidget {
  const JobsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final jobs = state.backgroundJobs;
    final active = jobs.where((job) => job.running).length;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
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
                        Text('Background jobs', style: Txt.headline),
                        const SizedBox(height: 2),
                        Text(
                          active > 0
                              ? '$active running · progress is in your notifications'
                              : 'Recent agent tasks and deployments',
                          style: Txt.meta,
                        ),
                      ],
                    ),
                  ),
                  if (jobs.any((job) => !job.running))
                    IconAction(
                      icon: Icons.clear_all_rounded,
                      tooltip: 'Clear finished jobs',
                      onTap: state.clearFinishedBackgroundJobs,
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
            Expanded(
              child: jobs.isEmpty
                  ? const _EmptyJobs()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                          Sp.page, Sp.x3, Sp.page, Sp.x6),
                      itemCount: jobs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final job = jobs[index];
                        return _JobRow(
                          job: job,
                          canResume: job.kind == BackgroundJobKind.agent &&
                              job.status == BackgroundJobStatus.interrupted &&
                              state.hasResumableCheckpoint(job.projectId),
                          onResume: () {
                            Navigator.of(context).pop();
                            state.resumeTask(job.projectId);
                          },
                        );
                      },
                    ),
            ),
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(Sp.page, Sp.x2, Sp.page, Sp.x3),
              child: Text(
                'The foreground service keeps this process alive while you '
                'switch apps or lock the phone. If Android force-stops Praxis, '
                'the job is marked interrupted and a resumable checkpoint is '
                'kept where support exists.',
                style: Txt.meta.copyWith(fontSize: 10, height: 1.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JobRow extends StatelessWidget {
  const _JobRow({
    required this.job,
    required this.canResume,
    required this.onResume,
  });

  final BackgroundJobRecord job;
  final bool canResume;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final color = switch (job.status) {
      BackgroundJobStatus.running => Pal.amber,
      BackgroundJobStatus.completed => Pal.mint,
      BackgroundJobStatus.failed => Pal.rose,
      BackgroundJobStatus.interrupted => Pal.sky,
    };
    final icon = switch (job.kind) {
      BackgroundJobKind.agent => Icons.auto_awesome_rounded,
      BackgroundJobKind.deploy => Icons.rocket_launch_outlined,
    };
    return Panel(
      padding: const EdgeInsets.fromLTRB(Sp.x3, Sp.x3, Sp.x2, Sp.x3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: Rd.sm,
              border: Border.all(color: color.withOpacity(0.25)),
            ),
            child: job.running
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.7,
                      color: color,
                    ),
                  )
                : Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: Sp.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        job.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Txt.title.copyWith(fontSize: 13.5),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      job.status.label.toUpperCase(),
                      style: Txt.meta.copyWith(
                        fontSize: 8.5,
                        letterSpacing: 0.7,
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  job.projectName,
                  style: Txt.meta.copyWith(fontSize: 9.5),
                ),
                if (job.detail.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    job.detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Txt.bodySoft.copyWith(fontSize: 11.5),
                  ),
                ],
                const SizedBox(height: 5),
                Text(
                  '${relativeTime(job.startedAt)} · ${job.kind.name}',
                  style: Txt.meta.copyWith(fontSize: 9),
                ),
              ],
            ),
          ),
          if (canResume)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: TextButton(
                onPressed: onResume,
                style: TextButton.styleFrom(
                  foregroundColor: Pal.ember,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 34),
                  textStyle: Txt.label.copyWith(fontWeight: FontWeight.w700),
                ),
                child: const Text('Resume'),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyJobs extends StatelessWidget {
  const _EmptyJobs();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Sp.page),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.work_history_outlined, size: 34, color: Pal.textDim),
            const SizedBox(height: Sp.x3),
            Text('No background jobs yet', style: Txt.title),
            const SizedBox(height: 5),
            Text(
              'Agent tasks and deployments appear here once they start. '
              'Long jobs keep running when you leave the app.',
              textAlign: TextAlign.center,
              style: Txt.bodySoft.copyWith(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
