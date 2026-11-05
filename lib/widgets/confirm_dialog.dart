import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'ui.dart';

class ConfirmDetail {
  const ConfirmDetail(this.label, this.value);
  final String label;
  final String value;
}

/// The single confirmation surface used by destructive actions, pushes and
/// pulls. It stays compact for one-line prompts and grows into a detail sheet
/// for destination checks without becoming a second screen.
Future<bool> showPraxisConfirm(
  BuildContext context, {
  required String title,
  required String body,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
  IconData icon = Icons.help_outline_rounded,
  List<ConfirmDetail> details = const [],
  String? note,
}) async {
  final color = destructive ? Pal.rose : Pal.ember;
  final confirmed = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.7),
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding:
            const EdgeInsets.symmetric(horizontal: Sp.x5, vertical: Sp.x5),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Container(
            decoration: BoxDecoration(
              color: Pal.surface,
              borderRadius: Rd.lg,
              border: Border.all(color: Pal.lineStrong),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(Sp.x5, Sp.x5, Sp.x5, Sp.x4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GlyphBadge(
                          icon: icon, color: color, size: 38, iconSize: 18),
                      const SizedBox(width: Sp.x3),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            title,
                            style: Txt.headline.copyWith(fontSize: 21),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Sp.x3),
                  Text(body, style: Txt.bodySoft.copyWith(height: 1.55)),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: Sp.x3 + 2),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(Sp.x3, 7, Sp.x3, 7),
                      decoration: BoxDecoration(
                        color: Pal.raised,
                        borderRadius: Rd.sm,
                        border: Border.all(color: Pal.line),
                      ),
                      child: Column(
                        children: [
                          for (var i = 0; i < details.length; i++) ...[
                            if (i > 0) const Hairline(),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 7),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 82,
                                    child: Text(
                                      details[i].label,
                                      style: Txt.meta.copyWith(fontSize: 9.5),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      details[i].value,
                                      style: Txt.code.copyWith(
                                        fontSize: 11.5,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  if (note != null && note.trim().isNotEmpty) ...[
                    const SizedBox(height: Sp.x3),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded,
                            size: 14, color: color),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            note,
                            style: Txt.meta.copyWith(
                              fontSize: 10,
                              height: 1.45,
                              color: Pal.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: Sp.x5),
                  Row(
                    children: [
                      Expanded(
                        child: GhostButton(
                          label: cancelLabel,
                          onTap: () => Navigator.of(dialogContext).pop(false),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: _ConfirmAction(
                          label: confirmLabel,
                          color: color,
                          onTap: () => Navigator.of(dialogContext).pop(true),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
  return confirmed ?? false;
}

class _ConfirmAction extends StatelessWidget {
  const _ConfirmAction({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            borderRadius: Rd.sm,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Txt.label.copyWith(
              color: Pal.isDark ? Pal.canvas : Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ),
      ),
    );
  }
}
