import 'package:flutter/material.dart';

import '../models/chat.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import 'composer.dart';

class AgentTab extends StatelessWidget {
  const AgentTab({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final items = state.threadOf(projectId);
    final extra = state.agentBusy ? 1 : 0;

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            reverse: true,
            padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x3, Sp.x4, Sp.x2),
            itemCount: items.length + extra,
            itemBuilder: (context, i) {
              if (state.agentBusy && i == 0) return const _Working();
              final item =
                  items.reversed.elementAt(state.agentBusy ? i - 1 : i);
              return Padding(
                padding: const EdgeInsets.only(bottom: Sp.x3 + 2),
                child: switch (item) {
                  final UserNote note => _UserBubble(text: note.text),
                  final AgentNote note => _AgentBlock(text: note.text),
                  final CommandRun run => _CommandCard(run: run),
                  final FileEdit edit => _EditCard(edit: edit),
                },
              );
            },
          ),
        ),
        Composer(projectId: projectId),
      ],
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
        decoration: const BoxDecoration(
          color: Pal.raised,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(5),
          ),
          border: Border.fromBorderSide(BorderSide(color: Pal.line)),
        ),
        child: Text(text, style: Txt.body.copyWith(fontSize: 13.5)),
      ),
    );
  }
}

class _AgentBlock extends StatelessWidget {
  const _AgentBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: BrandMark(size: 14),
        ),
        const SizedBox(width: Sp.x3 - 2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'POLYDEV',
                style: Txt.overline.copyWith(
                  color: Pal.ember,
                  fontSize: 9,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                text,
                style: Txt.body.copyWith(fontSize: 13.5, height: 1.5),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CommandCard extends StatelessWidget {
  const _CommandCard({required this.run});

  final CommandRun run;

  Color get _tint => switch (run.state) {
        ToolState.running => Pal.amber,
        ToolState.passed => Pal.mint,
        ToolState.failed => Pal.rose,
      };

  String get _label => switch (run.state) {
        ToolState.running => 'running',
        ToolState.passed => 'passed',
        ToolState.failed => 'failed',
      };

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.fromLTRB(Sp.x3 + 2, Sp.x3, Sp.x3 + 2, Sp.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.terminal_rounded, size: 13, color: Pal.textDim),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  run.command,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Txt.meta.copyWith(
                    fontSize: 11.5,
                    color: Pal.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: Sp.x2),
              StatusPill(_label, color: _tint),
            ],
          ),
          const SizedBox(height: Sp.x2 + 2),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Sp.x2 + 2),
            decoration: const BoxDecoration(
              color: Pal.terminal,
              borderRadius: Rd.sm,
              border: Border.fromBorderSide(BorderSide(color: Pal.line)),
            ),
            child: Text(
              run.output,
              style: Txt.code.copyWith(fontSize: 10.5, color: Pal.textDim),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditCard extends StatelessWidget {
  const _EditCard({required this.edit});

  final FileEdit edit;

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.fromLTRB(Sp.x3 + 2, Sp.x3, Sp.x3 + 2, Sp.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.description_outlined,
                size: 13,
                color: Pal.textDim,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  edit.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Txt.meta.copyWith(
                    fontSize: 11.5,
                    color: Pal.textMuted,
                  ),
                ),
              ),
              Text(
                '+${edit.added}',
                style: Txt.meta.copyWith(color: Pal.mint, fontSize: 10.5),
              ),
              const SizedBox(width: 6),
              Text(
                '−${edit.removed}',
                style: Txt.meta.copyWith(color: Pal.rose, fontSize: 10.5),
              ),
            ],
          ),
          const SizedBox(height: Sp.x2 + 2),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: const BoxDecoration(
              color: Pal.terminal,
              borderRadius: Rd.sm,
              border: Border.fromBorderSide(BorderSide(color: Pal.line)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in edit.diff)
                  Container(
                    width: double.infinity,
                    color: _lineTint(line),
                    padding: const EdgeInsets.symmetric(
                      horizontal: Sp.x3 - 2,
                      vertical: 1,
                    ),
                    child: Text(
                      line,
                      style: Txt.code.copyWith(
                        fontSize: 10.5,
                        height: 1.5,
                        color: _lineColor(line),
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

  Color? _lineTint(String line) {
    if (line.startsWith('+')) return Pal.mint.withOpacity(0.07);
    if (line.startsWith('-')) return Pal.rose.withOpacity(0.07);
    return null;
  }

  Color _lineColor(String line) {
    if (line.startsWith('+')) return Pal.mint;
    if (line.startsWith('-')) return Pal.rose;
    return Pal.textMuted;
  }
}

class _Working extends StatelessWidget {
  const _Working();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const BrandMark(size: 14),
        const SizedBox(width: Sp.x3 - 2),
        const _PulsingDots(),
        const SizedBox(width: Sp.x2 + 2),
        Text('Working', style: Txt.meta.copyWith(fontSize: 10.5)),
      ],
    );
  }
}

class _PulsingDots extends StatefulWidget {
  const _PulsingDots();

  @override
  State<_PulsingDots> createState() => _PulsingDotsState();
}

class _PulsingDotsState extends State<_PulsingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final t = (_controller.value + i * 0.18) % 1.0;
            final pulse = 1.0 - ((t - 0.5).abs() * 2).clamp(0.0, 1.0);
            return Container(
              width: 4,
              height: 4,
              margin: EdgeInsets.only(right: i == 2 ? 0 : 4),
              decoration: BoxDecoration(
                color: Pal.ember.withOpacity(0.25 + 0.7 * pulse),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}
