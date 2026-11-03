import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/ember_button.dart';

class PreviewTab extends StatelessWidget {
  const PreviewTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x3, Sp.x4, Sp.x3),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: Sp.x3),
                  decoration: BoxDecoration(
                    color: Pal.surface,
                    borderRadius: Rd.sm,
                    border: Border.all(color: Pal.line),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.lock_outline_rounded,
                        size: 12,
                        color: Pal.textDim,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'localhost:5173',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Txt.meta.copyWith(
                            fontSize: 11,
                            color: Pal.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: Sp.x2),
              Container(
                height: 38,
                width: 38,
                decoration: BoxDecoration(
                  color: Pal.surface,
                  borderRadius: Rd.sm,
                  border: Border.all(color: Pal.line),
                ),
                child: IconAction(
                  icon: Icons.refresh_rounded,
                  tooltip: 'Reload preview',
                  size: 17,
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Preview reloaded · localhost:5173')),
                  ),
                ),
              ),
            ],
          ),
        ),
        const Expanded(
            child: Padding(
          padding: EdgeInsets.fromLTRB(Sp.x4, 0, Sp.x4, Sp.x3),
          child: _AppPreview(),
        )),
        _DeployBar(),
      ],
    );
  }
}

class _AppPreview extends StatelessWidget {
  const _AppPreview();

  static const _bars = [0.34, 0.55, 0.42, 0.7, 0.5, 0.88, 0.63];

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF0D0B0A),
        borderRadius: Rd.md,
        border: Border.all(color: Pal.line),
      ),
      child: Column(
        children: [
          Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: Sp.x3),
            decoration: const BoxDecoration(
              color: Pal.surface,
              border: Border(bottom: BorderSide(color: Pal.line)),
            ),
            child: Row(
              children: [
                for (final color in [Pal.rose, Pal.amber, Pal.mint])
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 5),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.7),
                      shape: BoxShape.circle,
                    ),
                  ),
                const SizedBox(width: Sp.x2),
                Text(
                  'ember · dashboard',
                  style: Txt.meta.copyWith(fontSize: 9.5),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding:
                  const EdgeInsets.fromLTRB(Sp.x4, Sp.x3 + 2, Sp.x4, Sp.x3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Ember',
                        style: Txt.title.copyWith(fontSize: 14),
                      ),
                      const Spacer(),
                      Text(
                        'OVERVIEW',
                        style: Txt.meta.copyWith(
                          fontSize: 8.5,
                          color: Pal.ember,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Sp.x4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '24,318',
                        style: Txt.headline.copyWith(
                          fontSize: 27,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(width: Sp.x2),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '+12.4%',
                          style: Txt.meta.copyWith(
                            fontSize: 9.5,
                            color: Pal.mint,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'requests this week',
                    style: Txt.meta.copyWith(fontSize: 9.5),
                  ),
                  const Spacer(),
                  SizedBox(
                    height: 74,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < _bars.length; i++) ...[
                          Expanded(
                            child: FractionallySizedBox(
                              heightFactor: _bars[i],
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: i == _bars.length - 2
                                        ? const [Pal.ember, Pal.emberDeep]
                                        : [
                                            Pal.lineStrong,
                                            Pal.line.withOpacity(0.6),
                                          ],
                                  ),
                                  borderRadius: const BorderRadius.all(
                                    Radius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (i != _bars.length - 1) const SizedBox(width: 6),
                        ],
                      ],
                    ),
                  ),
                  const Spacer(),
                  const Hairline(),
                  const SizedBox(height: Sp.x2 + 2),
                  Row(
                    children: [
                      Text(
                        'deploy · main',
                        style: Txt.meta.copyWith(fontSize: 9.5),
                      ),
                      const Spacer(),
                      const StatusPill('ready', color: Pal.mint),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeployBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x3, Sp.x4, Sp.x3),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Pal.line)),
      ),
      child: Row(
        children: [
          const Flexible(child: MonoChip('Vercel', tint: Pal.textMuted)),
          const SizedBox(width: Sp.x2),
          const Flexible(child: MonoChip('CF Pages', tint: Pal.textMuted)),
          const Spacer(),
          GhostButton(
            label: 'Deploy',
            icon: Icons.cloud_upload_outlined,
            tint: Pal.mint,
            dense: true,
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Deploying to Vercel · demo build')),
            ),
          ),
        ],
      ),
    );
  }
}
