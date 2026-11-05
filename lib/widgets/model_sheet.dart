import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/model_info.dart';
import '../models.dart';
import '../screens/settings.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import 'ui.dart';

/// The model switcher behind the project header. It lists only the providers
/// the user has configured, and only the models they chose to keep.
Future<void> showModelSheet(BuildContext context) {
  final state = AppScope.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Pal.surface,
    builder: (sheetContext) => _ModelSheet(state: state),
  );
}

class _ModelSheet extends StatelessWidget {
  const _ModelSheet({required this.state});

  final AppState state;

  List<(ProviderConfig, String)> get _models {
    final result = <(ProviderConfig, String)>[];
    for (final provider in state.configuredProviders) {
      final models = provider.selectedModels.isEmpty
          ? [provider.model]
          : provider.selectedModels;
      for (final model in models) {
        if (model.trim().isEmpty) continue;
        result.add((provider, model));
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final models = _models;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.78,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.page, 0, Sp.page, Sp.x2),
              child: Row(
                children: [
                  Text('Models', style: Txt.headline.copyWith(fontSize: 22)),
                  const Spacer(),
                  Text(
                    '${models.length} selected',
                    style: Txt.meta.copyWith(fontSize: 10),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.page, 0, Sp.page, Sp.x3),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Only the models you kept in each provider are listed. '
                  'Context is the window, not the tokens used.',
                  style: Txt.bodySoft,
                ),
              ),
            ),
            if (models.isEmpty)
              Padding(
                padding: const EdgeInsets.all(Sp.page),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const EmptyState(
                      icon: Icons.bolt_outlined,
                      title: 'No model selected',
                      body:
                          'Add a provider key and choose at least one model in Settings.',
                    ),
                    const SizedBox(height: Sp.x4),
                    EmberButton(
                      label: 'Open providers',
                      icon: Icons.tune_rounded,
                      onTap: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const SettingsScreen()));
                      },
                    ),
                  ],
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: Sp.page),
                  itemCount: models.length,
                  separatorBuilder: (_, __) => const Hairline(),
                  itemBuilder: (context, index) {
                    final (provider, model) = models[index];
                    final active = provider.id == state.activeProviderId &&
                        provider.model == model;
                    final limit = contextWindowFor(model);
                    return InkWell(
                      onTap: () async {
                        await state.setActiveModel(provider.id, model);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 22,
                              height: 22,
                              child: SvgPicture.asset(
                                provider.icon,
                                colorFilter: ColorFilter.mode(
                                  provider.isConfigured
                                      ? Pal.text
                                      : Pal.textDim,
                                  BlendMode.srcIn,
                                ),
                              ),
                            ),
                            const SizedBox(width: Sp.x3),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    model,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Txt.code.copyWith(
                                      fontSize: 11.5,
                                      color: active ? Pal.ember : Pal.text,
                                      fontWeight: active
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${provider.name} · '
                                    '${limit == null ? 'context unknown' : '${compactContext(limit)} context'}',
                                    style: Txt.meta.copyWith(fontSize: 9.5),
                                  ),
                                ],
                              ),
                            ),
                            if (active)
                              StatusPill('using', color: Pal.ember)
                            else
                              Icon(Icons.chevron_right_rounded,
                                  size: 17, color: Pal.textDim),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(Sp.page, Sp.x3, Sp.page, Sp.x3),
              child: Row(
                children: [
                  GhostButton(
                    label: 'Providers & keys',
                    icon: Icons.tune_rounded,
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const SettingsScreen()));
                    },
                  ),
                  const Spacer(),
                  Text(
                    state.activeGithub == null ? '' : '',
                    style: Txt.meta,
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

String compactContext(int tokens) {
  if (tokens >= 1000000) {
    final value = tokens / 1000000;
    return '${value.toStringAsFixed(value >= 10 ? 0 : 1)}M';
  }
  return '${(tokens / 1000).round()}K';
}
