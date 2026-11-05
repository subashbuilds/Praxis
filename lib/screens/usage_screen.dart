import 'package:flutter/material.dart';

import '../core/usage.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

class UsageScreen extends StatelessWidget {
  const UsageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final usage = state.usage;
    final week = usage.lastWeek();
    final providers = usage.byProvider();
    final weekTotal = week.fold(0, (sum, day) => sum + day.tokens);

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
                  Text('Usage', style: Txt.title),
                  const Spacer(),
                  const Wordmark(size: 13, showMark: false),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding:
                    const EdgeInsets.fromLTRB(Sp.page, Sp.x4, Sp.page, Sp.x10),
                children: [
                  Container(
                    padding:
                        const EdgeInsets.fromLTRB(Sp.x4, Sp.x4, Sp.x4, Sp.x4),
                    decoration: BoxDecoration(
                      color: Pal.surface,
                      borderRadius: Rd.lg,
                      border: Border.all(color: Pal.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('TOKENS USED, ALL TIME', style: Txt.overline),
                        const SizedBox(height: 8),
                        Text(
                          compactTokens(usage.totalTokens),
                          style: Txt.display.copyWith(
                            fontSize: 54,
                            height: 0.95,
                            letterSpacing: -2.2,
                            color:
                                usage.totalTokens == 0 ? Pal.textDim : Pal.text,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          usage.events.isEmpty
                              ? 'No model calls yet. Usage appears after the first reply.'
                              : '${usage.events.length} model call${usage.events.length == 1 ? '' : 's'} recorded on this device.',
                          style: Txt.meta.copyWith(fontSize: 10),
                        ),
                        const SizedBox(height: Sp.x4),
                        const Hairline(),
                        const SizedBox(height: Sp.x3),
                        Row(
                          children: [
                            _Metric(
                              label: 'TODAY',
                              value: compactTokens(usage.todayTokens),
                            ),
                            _Metric(
                              label: 'PROMPT',
                              value: compactTokens(usage.promptTokens),
                            ),
                            _Metric(
                              label: 'OUTPUT',
                              value: compactTokens(usage.completionTokens),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SectionLabel(
                    'LAST 7 DAYS',
                    trailing: Text(
                      '${compactTokens(weekTotal)} tokens',
                      style: Txt.meta,
                    ),
                  ),
                  _WeekGraph(days: week, peak: usage.weekPeak),
                  SectionLabel(
                    'BY PROVIDER',
                    trailing: Text('${providers.length}', style: Txt.meta),
                  ),
                  if (providers.isEmpty)
                    const Panel(
                      child: EmptyState(
                        icon: Icons.bar_chart_rounded,
                        title: 'Nothing measured yet',
                        body:
                            'Each completed model call records prompt and output '
                            'tokens here, grouped by provider and key.',
                      ),
                    )
                  else
                    for (final provider in providers)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: _ProviderUsage(provider: provider),
                      ),
                  const SizedBox(height: Sp.x3),
                  Text(
                    'Counts are reported by the provider with each reply. '
                    'Praxis never stores the key itself in usage history.',
                    style: Txt.meta.copyWith(height: 1.55),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Txt.overline.copyWith(fontSize: 8.5)),
          const SizedBox(height: 5),
          Text(
            value,
            style: Txt.title.copyWith(
              fontFamily: Txt.mono,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekGraph extends StatelessWidget {
  const _WeekGraph({required this.days, required this.peak});

  final List<UsageDay> days;
  final double peak;

  static const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return Panel(
      padding: const EdgeInsets.fromLTRB(Sp.x3, Sp.x4, Sp.x3, Sp.x2),
      child: SizedBox(
        height: 158,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var index = 0; index < days.length; index++)
              Expanded(
                child: _DayBar(
                  day: days[index],
                  fraction: days[index].tokens / peak,
                  isToday: days[index].day.year == today.year &&
                      days[index].day.month == today.month &&
                      days[index].day.day == today.day,
                  weekday: _weekdays[days[index].day.weekday - 1],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DayBar extends StatelessWidget {
  const _DayBar({
    required this.day,
    required this.fraction,
    required this.isToday,
    required this.weekday,
  });

  final UsageDay day;
  final double fraction;
  final bool isToday;
  final String weekday;

  @override
  Widget build(BuildContext context) {
    final hasUsage = day.tokens > 0;
    final barHeight = hasUsage ? 4 + (fraction.clamp(0.0, 1.0) * 100) : 3;
    return Tooltip(
      message:
          '${day.day.day}/${day.day.month} · ${compactTokens(day.tokens)} tokens',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            hasUsage ? compactTokens(day.tokens) : '',
            style: Txt.meta.copyWith(
              fontSize: 8,
              color: isToday ? Pal.ember : Pal.textDim,
            ),
          ),
          const SizedBox(height: 5),
          AnimatedContainer(
            duration: Motion.slow,
            width: 22,
            height: barHeight.toDouble(),
            decoration: BoxDecoration(
              color: hasUsage
                  ? (isToday ? Pal.ember : Pal.ember.withOpacity(0.36))
                  : Pal.line,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(5),
                bottom: Radius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            weekday,
            style: Txt.meta.copyWith(
              fontSize: 9,
              color: isToday ? Pal.ember : Pal.textDim,
              fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderUsage extends StatelessWidget {
  const _ProviderUsage({required this.provider});

  final UsageProvider provider;

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
                icon: Icons.memory_rounded,
                color: Pal.ember,
                size: 30,
                iconSize: 15,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  provider.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Txt.title.copyWith(fontSize: 14),
                ),
              ),
              Text(
                compactTokens(provider.tokens),
                style: Txt.title.copyWith(
                  fontFamily: Txt.mono,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          const Hairline(),
          const SizedBox(height: 9),
          for (final key in provider.keys)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Pal.mint,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(key.label, style: Txt.code.copyWith(fontSize: 11)),
                  const Spacer(),
                  Text(
                    compactTokens(key.tokens),
                    style: Txt.meta.copyWith(fontSize: 10),
                  ),
                ],
              ),
            ),
          if (provider.models.isNotEmpty) ...[
            const SizedBox(height: 3),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (final model in provider.models.take(3))
                  MonoChip(
                    '${model.name} · ${compactTokens(model.tokens)}',
                    icon: Icons.bolt_rounded,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
