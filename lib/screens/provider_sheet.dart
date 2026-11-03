import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/provider.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

Future<void> showProviderSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _ProviderSheet(),
  );
}

class _ProviderSheet extends StatefulWidget {
  const _ProviderSheet();

  @override
  State<_ProviderSheet> createState() => _ProviderSheetState();
}

class _ProviderSheetState extends State<_ProviderSheet> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() => _query = _controller.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<AiProvider> _filter(ProviderGroup group) => kProviders
      .where((p) =>
          p.group == group &&
          (_query.isEmpty ||
              p.name.toLowerCase().contains(_query) ||
              p.detail.toLowerCase().contains(_query)))
      .toList();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final builtin = _filter(ProviderGroup.builtin);
    final own = _filter(ProviderGroup.own);
    final local = _filter(ProviderGroup.local);
    final empty = builtin.isEmpty && own.isEmpty && local.isEmpty;

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.82,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.page),
            child: Row(
              children: [
                Text('AI provider', style: Txt.headline.copyWith(fontSize: 21)),
                const Spacer(),
                IconAction(
                  icon: Icons.close_rounded,
                  tooltip: 'Close',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.page),
            child: Text(
              'The built-in provider runs through the PolyDev proxy. '
              'Your own keys stay in encrypted local storage.',
              style: Txt.bodySoft.copyWith(fontSize: 12.5),
            ),
          ),
          const SizedBox(height: Sp.x4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.page),
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: Sp.x3),
              decoration: BoxDecoration(
                color: Pal.raised,
                borderRadius: Rd.sm,
                border: Border.all(color: Pal.line),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded,
                      size: 16, color: Pal.textDim),
                  const SizedBox(width: Sp.x2),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: Txt.body.copyWith(fontSize: 13),
                      cursorColor: Pal.ember,
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: 'Search 24 providers',
                        hintStyle: Txt.bodySoft.copyWith(
                          fontSize: 13,
                          color: Pal.textDim,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Sp.x2),
          Expanded(
            child: empty
                ? Center(
                    child: Text(
                      'No provider matches “$_query”',
                      style: Txt.bodySoft,
                    ),
                  )
                : ListView(
                    padding:
                        const EdgeInsets.fromLTRB(Sp.x3, Sp.x2, Sp.x3, Sp.x6),
                    children: [
                      ..._section('BUILT-IN', builtin, state),
                      ..._section('YOUR KEYS', own, state),
                      ..._section('ON DEVICE', local, state),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  List<Widget> _section(String title, List<AiProvider> items, AppState state) {
    if (items.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(Sp.x2, Sp.x4, Sp.x2, Sp.x2),
        child: Text(title, style: Txt.overline),
      ),
      for (final provider in items)
        _ProviderRow(
          provider: provider,
          active: state.provider.id == provider.id,
          onTap: () {
            state.setProvider(provider);
            Navigator.of(context).pop();
          },
        ),
    ];
  }
}

class _ProviderRow extends StatelessWidget {
  const _ProviderRow({
    required this.provider,
    required this.active,
    required this.onTap,
  });

  final AiProvider provider;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: Motion.fast,
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(
            horizontal: Sp.x2 + 2, vertical: Sp.x2 + 2),
        decoration: BoxDecoration(
          color: active ? Pal.ember.withOpacity(0.07) : Colors.transparent,
          borderRadius: Rd.sm,
          border: Border.all(
            color: active ? Pal.ember.withOpacity(0.30) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Pal.raised,
                borderRadius: const BorderRadius.all(Radius.circular(10)),
                border: Border.all(color: Pal.line),
              ),
              child: Center(
                child: SvgPicture.asset(provider.icon, width: 18, height: 18),
              ),
            ),
            const SizedBox(width: Sp.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    provider.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Txt.body.copyWith(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    provider.detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Txt.meta.copyWith(fontSize: 10.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Sp.x2),
            if (active)
              const Icon(
                Icons.check_circle_rounded,
                size: 18,
                color: Pal.ember,
              )
            else
              const Icon(
                Icons.radio_button_unchecked_rounded,
                size: 16,
                color: Pal.lineStrong,
              ),
          ],
        ),
      ),
    );
  }
}
