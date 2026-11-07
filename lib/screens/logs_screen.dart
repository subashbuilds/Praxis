import 'package:flutter/material.dart';

import '../core/round_log.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  Future<List<AgentTask>>? _future;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _reload();
  }

  void _reload() {
    setState(() {
      _future = AppScope.of(context).loadAgentTasks();
    });
  }

  @override
  Widget build(BuildContext context) {
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
                  Text('Logs', style: Txt.title),
                  const Spacer(),
                  IconAction(
                    icon: Icons.refresh_rounded,
                    tooltip: 'Refresh',
                    onTap: _reload,
                  ),
                  const Wordmark(size: 13, showMark: false),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<AgentTask>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(Sp.page),
                      child: Text(
                        'Could not read the round log: ${snapshot.error}',
                        style: Txt.bodySoft.copyWith(color: Pal.rose),
                      ),
                    );
                  }
                  final tasks = snapshot.data ?? const <AgentTask>[];
                  if (tasks.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(Sp.page),
                      child: EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: 'No agent rounds yet',
                        body:
                            'Send a request to the agent. Each model request is '
                            'recorded here with its tool names, round type and '
                            'task outcome. Prompts, arguments and file contents '
                            'are never recorded.',
                      ),
                    );
                  }
                  return _LogList(tasks: tasks);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogList extends StatelessWidget {
  const _LogList({required this.tasks});

  final List<AgentTask> tasks;

  @override
  Widget build(BuildContext context) {
    final stats = AgentRoundStats(tasks);
    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.page, Sp.x4, Sp.page, Sp.x10),
      children: [
        Text(
          'One entry per model request. This view is local-only and contains '
          'no prompts, tool arguments, file contents or API keys.',
          style: Txt.bodySoft,
        ),
        const SectionLabel('AGGREGATE'),
        _AggregateCard(stats: stats),
        SectionLabel(
          'TASKS',
          trailing: Text('${tasks.length}', style: Txt.meta),
        ),
        for (final task in tasks)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: _TaskCard(task: task),
          ),
      ],
    );
  }
}

class _AggregateCard extends StatelessWidget {
  const _AggregateCard({required this.stats});

  final AgentRoundStats stats;

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.fromLTRB(Sp.x3, Sp.x3, Sp.x3, Sp.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlyphBadge(
                icon: Icons.route_rounded,
                color: Pal.ember,
                size: 34,
                iconSize: 17,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${stats.totalRounds} model request${stats.totalRounds == 1 ? '' : 's'}',
                      style: Txt.title.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${stats.totalTasks} task${stats.totalTasks == 1 ? '' : 's'} · '
                      '${stats.averageRounds.toStringAsFixed(1)} rounds per task',
                      style: Txt.meta.copyWith(fontSize: 9.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Sp.x3),
          const Hairline(),
          const SizedBox(height: Sp.x2),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final type in RoundType.values)
                if ((stats.byType[type] ?? 0) > 0)
                  MonoChip(
                    '${type.label} ${stats.byType[type]}',
                    tint: _typeColor(type),
                  ),
              MonoChip(
                'repeated ${stats.repeatedCalls}',
                tint: stats.repeatedCalls > 0 ? Pal.amber : Pal.textDim,
              ),
            ],
          ),
          const SizedBox(height: Sp.x2),
          Text(
            'First edit after ${stats.averageRoundsBeforeFirstEdit.toStringAsFixed(1)} '
            'rounds on average. Provider-reporting tokens: '
            '${stats.inputTokens} in / ${stats.outputTokens} out.',
            style: Txt.meta.copyWith(fontSize: 9.5, height: 1.5),
          ),
          const SizedBox(height: Sp.x2),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final entry in stats.outcomes.entries)
                MonoChip(
                  '${entry.key} ${entry.value}',
                  tint: _outcomeColor(entry.key),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task});

  final AgentTask task;

  @override
  Widget build(BuildContext context) {
    final outcome = task.outcome;
    final firstEdit = task.firstEditIndex;
    return Panel(
      padding: const EdgeInsets.fromLTRB(Sp.x3, Sp.x3, Sp.x3, Sp.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  task.taskId,
                  maxLines: 1,
                  style: Txt.code.copyWith(
                    fontSize: 10.5,
                    color: Pal.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(
                agentOutcomeLabel(outcome),
                color: _outcomeColor(agentOutcomeLabel(outcome)),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            '${task.totalRounds} request${task.totalRounds == 1 ? '' : 's'} · '
            '${task.repeatedCalls} repeated call${task.repeatedCalls == 1 ? '' : 's'} · '
            '${firstEdit == null ? 'no edit' : 'first edit after $firstEdit round${firstEdit == 1 ? '' : 's'}'}',
            style: Txt.bodySoft.copyWith(fontSize: 12),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final type in RoundType.values)
                if ((task.roundsByType[type] ?? 0) > 0)
                  MonoChip(
                    '${type.label} ${task.roundsByType[type]}',
                    tint: _typeColor(type),
                  ),
            ],
          ),
          const SizedBox(height: 9),
          for (final round in task.rounds)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      '${round.roundIndex}',
                      textAlign: TextAlign.right,
                      style: Txt.meta.copyWith(fontSize: 9),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${round.type.label} · ${round.toolNames.isEmpty ? 'no tools' : round.toolNames.join(', ')}'
                      '${round.repeatedCall ? ' · repeated' : ''}',
                      style: Txt.meta.copyWith(fontSize: 9.5),
                    ),
                  ),
                  if (round.inputTokens != null || round.outputTokens != null)
                    Text(
                      '${round.inputTokens ?? 0}/${round.outputTokens ?? 0}',
                      style: Txt.meta.copyWith(fontSize: 9),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

Color _typeColor(RoundType type) => switch (type) {
      RoundType.explore => Pal.sky,
      RoundType.edit => Pal.mint,
      RoundType.verify => Pal.amber,
      RoundType.retry => Pal.rose,
      RoundType.other => Pal.textDim,
    };

Color _outcomeColor(String outcome) => switch (outcome) {
      'completed' => Pal.mint,
      'cancelled' => Pal.amber,
      'quota error' => Pal.rose,
      'loop detected' => Pal.rose,
      'error' => Pal.rose,
      _ => Pal.textDim,
    };
