import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/provider.dart';
import '../screens/provider_sheet.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

class Composer extends StatefulWidget {
  const Composer({super.key, required this.projectId});

  final String projectId;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _hasText = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) setState(() => _hasText = hasText);
    });
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send(AppState state) {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    state.sendPrompt(widget.projectId, text);
    _controller.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final enabled = _hasText && !state.agentBusy;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x2, Sp.x4, Sp.x3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: Motion.base,
            curve: Motion.ease,
            padding: const EdgeInsets.fromLTRB(
                Sp.x3, Sp.x1 + 2, Sp.x1 + 2, Sp.x1 + 2),
            decoration: BoxDecoration(
              color: Pal.surface,
              borderRadius: Rd.lg,
              border: Border.all(
                color: _focused ? Pal.lineStrong : Pal.line,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _controller,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 5,
                  keyboardType: TextInputType.multiline,
                  style: Txt.body.copyWith(fontSize: 13.5),
                  cursorColor: Pal.ember,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    hintText: 'Ask for a change, or describe a bug…',
                    hintStyle: Txt.bodySoft.copyWith(
                      fontSize: 13.5,
                      color: Pal.textDim,
                    ),
                  ),
                ),
                const SizedBox(height: Sp.x1),
                Row(
                  children: [
                    _ModelChip(
                      provider: state.provider,
                      onTap: () => showProviderSheet(context),
                    ),
                    const Spacer(),
                    IconAction(
                      icon: Icons.attach_file_rounded,
                      tooltip: 'Attach a file',
                      size: 18,
                      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:
                              Text('Attachments open the local file picker.'),
                        ),
                      ),
                    ),
                    const SizedBox(width: Sp.x1),
                    _SendButton(enabled: enabled, onTap: () => _send(state)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelChip extends StatelessWidget {
  const _ModelChip({required this.provider, required this.onTap});

  final AiProvider provider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 5, 9, 5),
        decoration: BoxDecoration(
          color: Pal.raised,
          borderRadius: Rd.pill,
          border: Border.all(color: Pal.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(provider.icon, width: 13, height: 13),
            const SizedBox(width: 6),
            Text(
              provider.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Txt.meta.copyWith(fontSize: 10.5, color: Pal.textMuted),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 14,
              color: Pal.textDim,
            ),
          ],
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Send',
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: Motion.fast,
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: enabled
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Pal.ember, Pal.emberDeep],
                  )
                : null,
            color: enabled ? null : Pal.overlay,
            borderRadius: const BorderRadius.all(Radius.circular(11)),
          ),
          child: Icon(
            Icons.arrow_upward_rounded,
            size: 19,
            color: enabled ? Pal.onEmber : Pal.textDim,
          ),
        ),
      ),
    );
  }
}
