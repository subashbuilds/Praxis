import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/model_info.dart';
import '../models.dart';
import '../screens/settings.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import 'ui.dart';

/// Shown after the current provider has exhausted every saved key. It lists
/// every other configured provider with the models its owner kept, so the user
/// chooses where to continue instead of approving an opaque switch.
Future<ProviderChoice?> showProviderFallbackSheet(
  BuildContext context, {
  required ProviderConfig current,
  required List<ProviderConfig> providers,
}) {
  return showModalBottomSheet<ProviderChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Pal.surface,
    builder: (_) => _ProviderFallbackSheet(
      current: current,
      providers: providers,
    ),
  );
}

/// The model switcher behind the project header. It lists only the providers
/// the user has configured, and only the models they chose to keep.
Future<void> showModelSheet(BuildContext context) {
  final state = AppScope.of(context);
  // Model names alone cannot tell two context variants apart. Refresh the
  // provider's model list so the sheet can show the reported window.
  for (final provider in state.configuredProviders) {
    if (provider.contextLengths.isNotEmpty) continue;
    unawaited(state.refreshModelContexts(provider));
  }
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
                  'Request counts are local and reset at midnight. '
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
                    final limit = provider.contextLengths[model] ??
                        contextWindowFor(model);
                    final quota = state.quotaStatusFor(provider);
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
                                  if (quota.hasLimit) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      quota.label,
                                      style: Txt.meta.copyWith(
                                        fontSize: 9.5,
                                        color: quota.exhausted
                                            ? Pal.rose
                                            : quota.warning
                                                ? Pal.amber
                                                : Pal.mint,
                                      ),
                                    ),
                                  ],
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

class _ProviderFallbackSheet extends StatelessWidget {
  const _ProviderFallbackSheet({
    required this.current,
    required this.providers,
  });

  final ProviderConfig current;
  final List<ProviderConfig> providers;

  List<(ProviderConfig, String)> get _models {
    final result = <(ProviderConfig, String)>[];
    for (final provider in providers) {
      final models = <String>{
        ...provider.selectedModels,
        if (provider.selectedModels.isEmpty) ...provider.models,
        if (provider.model.trim().isNotEmpty) provider.model,
      };
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
              padding: const EdgeInsets.fromLTRB(Sp.page, 0, Sp.page, Sp.x3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choose another provider',
                    style: Txt.headline.copyWith(fontSize: 22),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${current.name} could not complete this request with any '
                    'saved key. Pick a provider and model to continue this task.',
                    style: Txt.bodySoft,
                  ),
                ],
              ),
            ),
            if (models.isEmpty)
              const Padding(
                padding: EdgeInsets.all(Sp.page),
                child: EmptyState(
                  icon: Icons.key_off_outlined,
                  title: 'No other model is ready',
                  body: 'Add another provider key in Settings, then retry.',
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
                    return InkWell(
                      onTap: () => Navigator.of(context)
                          .pop(ProviderChoice(provider, model)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: SvgPicture.asset(
                                provider.icon,
                                colorFilter: ColorFilter.mode(
                                  Pal.text,
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
                                    style: Txt.code.copyWith(fontSize: 11.5),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${provider.name} · '
                                    '${provider.keys.length} '
                                    '${provider.keys.length == 1 ? 'key' : 'keys'}',
                                    style: Txt.meta.copyWith(fontSize: 9.5),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 17,
                              color: Pal.textDim,
                            ),
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
              child: SizedBox(
                width: double.infinity,
                child: GhostButton(
                  label: 'Stop this task',
                  icon: Icons.stop_circle_outlined,
                  onTap: () => Navigator.of(context).pop(),
                ),
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
