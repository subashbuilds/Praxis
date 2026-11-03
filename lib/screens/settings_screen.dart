import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/ember_button.dart';
import 'legal_screen.dart';
import 'provider_sheet.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  List<Widget> _dividers(List<Widget> rows) {
    final out = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) out.add(const Hairline(inset: Sp.x3 + 2));
      out.add(rows[i]);
    }
    return out;
  }

  Widget _group(List<Widget> rows) => Panel(
        padding: EdgeInsets.zero,
        child: Column(children: _dividers(rows)),
      );

  void _confirmClear(BuildContext context, AppState state) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Pal.surface,
        title: const Text('Clear local data?', style: Txt.title),
        content: const Text(
          'Chat history and shell output are removed. Projects, keys and '
          'integrations stay untouched.',
          style: Txt.bodySoft,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              state.clearLocalData();
              Navigator.of(dialogContext).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Local chat and shell data cleared')),
              );
            },
            child: const Text('Clear', style: TextStyle(color: Pal.rose)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconAction(
          icon: Icons.arrow_back_ios_new_rounded,
          tooltip: 'Back',
          size: 17,
          color: Pal.text,
          onTap: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: Text('Settings', style: Txt.title.copyWith(fontSize: 17)),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Hairline(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Sp.page, Sp.x2, Sp.page, Sp.x10),
        children: [
          const SectionLabel('ACCOUNT'),
          _group([
            _SettingsRow(
              leading: Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Pal.ember, Pal.emberDeep],
                  ),
                ),
                child: const Center(
                  child: Text(
                    'XA',
                    style: TextStyle(
                      fontFamily: Txt.ui,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Pal.onEmber,
                    ),
                  ),
                ),
              ),
              title: 'sam@polydev.app',
              subtitle: 'Signed in with Google',
              trailing: const StatusPill('PRO', color: Pal.ember),
            ),
            _SettingsRow(
              leading: const Icon(
                Icons.devices_rounded,
                size: 18,
                color: Pal.textMuted,
              ),
              title: '${state.devicesUsed} of ${state.devicesMax} devices',
              subtitle: 'One install slot left on this plan',
              trailing: Text(
                'Manage',
                style: Txt.label.copyWith(color: Pal.ember),
              ),
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Opens the device list on the web')),
              ),
            ),
          ]),
          const SizedBox(height: Sp.x3),
          _PlanCard(),
          const SectionLabel('AI PROVIDER'),
          _group([
            _SettingsRow(
              leading:
                  SvgPicture.asset(state.provider.icon, width: 20, height: 20),
              title: state.provider.name,
              subtitle: state.provider.detail,
              onTap: () => showProviderSheet(context),
            ),
          ]),
          const SectionLabel('INTEGRATIONS'),
          _group([
            _SettingsRow(
              leading: const Icon(Icons.code_rounded,
                  size: 18, color: Pal.textMuted),
              title: 'GitHub',
              subtitle: 'Push commits from the agent',
              trailing: const StatusPill('connected', color: Pal.mint),
              onTap: () => _integrationToast(context, 'GitHub'),
            ),
            _SettingsRow(
              leading: const Icon(
                Icons.change_history_rounded,
                size: 18,
                color: Pal.textMuted,
              ),
              title: 'Vercel',
              subtitle: 'Deploy previews and production',
              trailing:
                  Text('Connect', style: Txt.label.copyWith(color: Pal.ember)),
              onTap: () => _integrationToast(context, 'Vercel'),
            ),
            _SettingsRow(
              leading: const Icon(
                Icons.cloud_outlined,
                size: 18,
                color: Pal.textMuted,
              ),
              title: 'Cloudflare Pages',
              subtitle: 'Static hosting and functions',
              trailing:
                  Text('Connect', style: Txt.label.copyWith(color: Pal.ember)),
              onTap: () => _integrationToast(context, 'Cloudflare Pages'),
            ),
          ]),
          const SectionLabel('PREFERENCES'),
          _group([
            _SwitchRow(
              title: 'Usage statistics',
              subtitle: 'Anonymous events only — never code or prompts',
              value: state.usageStats,
              onChanged: state.setUsageStats,
            ),
            _SwitchRow(
              title: 'News notifications',
              subtitle: 'Release notes from the PolyDev topic',
              value: state.pushNews,
              onChanged: state.setPushNews,
            ),
            _SwitchRow(
              title: 'Wrap long lines',
              subtitle: 'Editor and file viewer',
              value: state.wordWrap,
              onChanged: state.setWordWrap,
            ),
            _SettingsRow(
              leading: const Icon(
                Icons.format_size_rounded,
                size: 18,
                color: Pal.textMuted,
              ),
              title: 'Text size',
              subtitle: 'Code, shell and diffs',
              trailing: _Segmented(
                index: state.codeScale,
                labels: const ['S', 'M', 'L'],
                onChanged: state.setCodeScale,
              ),
            ),
          ]),
          const SectionLabel('DATA'),
          _group([
            _SettingsRow(
              leading: const Icon(
                Icons.delete_sweep_outlined,
                size: 18,
                color: Pal.rose,
              ),
              title: 'Clear local data',
              titleTint: Pal.rose,
              subtitle: 'Chats and shell output on this device',
              onTap: () => _confirmClear(context, state),
            ),
          ]),
          const SectionLabel('LEGAL'),
          _group([
            _SettingsRow(
              leading: const Icon(
                Icons.shield_outlined,
                size: 18,
                color: Pal.textMuted,
              ),
              title: 'Privacy policy',
              subtitle: 'What leaves the device, and what does not',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LegalScreen(doc: LegalDoc.privacy),
                ),
              ),
            ),
            _SettingsRow(
              leading: const Icon(
                Icons.gavel_rounded,
                size: 18,
                color: Pal.textMuted,
              ),
              title: 'Terms of use',
              subtitle: 'Plans, billing and responsibilities',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LegalScreen(doc: LegalDoc.terms),
                ),
              ),
            ),
          ]),
          const SectionLabel('ABOUT'),
          _group([
            const _SettingsRow(
              leading: Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: Pal.textMuted,
              ),
              title: 'PolyDev 1.0.0 · build 13',
              subtitle: 'com.xapi.polydev · minSdk 24 · targetSdk 36',
            ),
          ]),
          const SizedBox(height: Sp.x6),
          Text(
            'Interface reconstructed from the shipped Android build. '
            'Agent responses and shell output are simulated locally.',
            style: Txt.meta.copyWith(fontSize: 10, color: Pal.textDim),
          ),
        ],
      ),
    );
  }

  void _integrationToast(BuildContext context, String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('$name tokens are stored in encrypted local storage')),
    );
  }
}

class _PlanCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Sp.x4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF221409), Pal.surface],
        ),
        borderRadius: Rd.md,
        border: Border.all(color: Pal.ember.withOpacity(0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('PRO PLAN', style: Txt.overline.copyWith(color: Pal.ember)),
              const Spacer(),
              const StatusPill('active', color: Pal.mint),
            ],
          ),
          const SizedBox(height: Sp.x2 + 2),
          Text('The whole workbench', style: Txt.title.copyWith(fontSize: 18)),
          const SizedBox(height: 4),
          Text(
            'Agent, shell, previews and deploys. Renews 12 Nov.',
            style: Txt.bodySoft.copyWith(fontSize: 12.5),
          ),
          const SizedBox(height: Sp.x3 + 2),
          GhostButton(
            label: 'Manage subscription',
            expand: true,
            dense: true,
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Subscriptions are managed by Google Play')),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.titleTint,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? titleTint;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Sp.x3 + 2, Sp.x3, Sp.x3, Sp.x3),
        child: Row(
          children: [
            SizedBox(width: 24, child: Center(child: leading)),
            const SizedBox(width: Sp.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Txt.body.copyWith(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: titleTint ?? Pal.text,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Txt.meta.copyWith(fontSize: 10.5),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: Sp.x2),
              trailing!,
            ] else if (onTap != null)
              const Padding(
                padding: EdgeInsets.only(left: Sp.x2),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: Pal.textDim,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SettingsRow(
      leading: Icon(
        value ? Icons.check_circle_outline_rounded : Icons.circle_outlined,
        size: 18,
        color: value ? Pal.mint : Pal.textDim,
      ),
      title: title,
      subtitle: subtitle,
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.index,
    required this.labels,
    required this.onChanged,
  });

  final int index;
  final List<String> labels;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Pal.raised,
        borderRadius: Rd.pill,
        border: Border.all(color: Pal.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < labels.length; i++)
            GestureDetector(
              onTap: () => onChanged(i),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: Motion.fast,
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: index == i ? Pal.ember : Colors.transparent,
                  borderRadius: Rd.pill,
                ),
                child: Text(
                  labels[i],
                  style: Txt.meta.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: index == i ? Pal.onEmber : Pal.textDim,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
