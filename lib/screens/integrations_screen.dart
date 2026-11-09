import 'package:flutter/material.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/service_mark.dart';
import '../widgets/ui.dart';

class IntegrationsScreen extends StatefulWidget {
  const IntegrationsScreen({super.key});

  @override
  State<IntegrationsScreen> createState() => _IntegrationsScreenState();
}

class _IntegrationsScreenState extends State<IntegrationsScreen> {
  IntegrationKind? _busyKind;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final accounts = state.integrations.accounts;
    final connectedKinds = [
      for (final kind in IntegrationKind.values)
        if (state.integrations.ofKind(kind).isNotEmpty) kind,
    ];
    final availableKinds = [
      for (final kind in IntegrationKind.values)
        if (state.integrations.ofKind(kind).isEmpty) kind,
    ];
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
                  Text('Integrations', style: Txt.title),
                  const Spacer(),
                  IconAction(
                    icon: Icons.add_rounded,
                    tooltip: 'Add integration',
                    color: Pal.ember,
                    onTap: _busyKind == null ? _showCatalog : null,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Sp.page, 0, Sp.page, Sp.x10),
                children: [
                  const SizedBox(height: Sp.x2),
                  Panel(
                    color: Pal.raised,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GlyphBadge(
                          icon: Icons.hub_outlined,
                          color: Pal.ember,
                          size: 34,
                          iconSize: 17,
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                accounts.isEmpty
                                    ? 'Connect the tools you already use'
                                    : '${accounts.length} saved on this device',
                                style: Txt.title.copyWith(fontSize: 14),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Tokens stay in local storage. They are sent only '
                                'to the service they belong to.',
                                style: Txt.bodySoft.copyWith(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SectionLabel('CONNECTED'),
                  if (connectedKinds.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Sp.x2),
                      child: Panel(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Sp.x4,
                          vertical: Sp.x6,
                        ),
                        child: Column(
                          children: [
                            GlyphBadge(
                              icon: Icons.cable_rounded,
                              color: Pal.textDim,
                              size: 48,
                              iconSize: 23,
                            ),
                            const SizedBox(height: Sp.x3),
                            Text('Nothing connected yet',
                                style: Txt.title.copyWith(fontSize: 15)),
                            const SizedBox(height: 4),
                            Text(
                              'Add an account to sync repositories, deploy '
                              'sites, build apps, search the web or manage a '
                              'database.',
                              textAlign: TextAlign.center,
                              style: Txt.bodySoft.copyWith(fontSize: 12),
                            ),
                            const SizedBox(height: Sp.x4),
                            EmberButton(
                              label: 'Add integration',
                              icon: Icons.add_rounded,
                              compact: true,
                              onTap: _busyKind == null ? _showCatalog : null,
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    for (final kind in connectedKinds) ...[
                      _ConnectedService(
                        kind: kind,
                        accounts: state.integrations.ofKind(kind),
                        activeId: state.integrations.activeIdFor(kind),
                        busy: _busyKind == kind,
                        onAdd: () => _connect(kind),
                        onActivate: state.activateAccount,
                        onRemove: _remove,
                      ),
                      const SizedBox(height: 8),
                    ],
                  if (availableKinds.isNotEmpty) ...[
                    const SectionLabel('AVAILABLE'),
                    Panel(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var i = 0; i < availableKinds.length; i++) ...[
                            _AvailableService(
                              kind: availableKinds[i],
                              onTap: _busyKind == null
                                  ? () => _connect(availableKinds[i])
                                  : null,
                            ),
                            if (i != availableKinds.length - 1)
                              const Hairline(inset: Sp.x3),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SectionLabel('HOW IT WORKS'),
                  Text(
                    'Only the service you choose receives its token. GitHub and '
                    'Vercel are used by Push and Deploy; the others are stored '
                    'for prompts and future actions. Remove an account here and '
                    'its token is deleted immediately.',
                    style: Txt.bodySoft.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCatalog() async {
    final kind = await showModalBottomSheet<IntegrationKind>(
      context: context,
      useSafeArea: true,
      backgroundColor: Pal.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _CatalogSheet(
        onPick: (value) => Navigator.of(sheetContext).pop(value),
      ),
    );
    if (kind != null && mounted) await _connect(kind);
  }

  Future<void> _connect(IntegrationKind kind) async {
    if (_busyKind != null) return;
    final state = AppScope.of(context);
    final token = TextEditingController();
    final label = TextEditingController();
    final accountId = TextEditingController();
    void disposeFields() {
      token.dispose();
      label.dispose();
      accountId.dispose();
    }

    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Pal.surface,
        title: Row(
          children: [
            ServiceMark(kind, size: 30),
            const SizedBox(width: 9),
            Expanded(child: Text('Connect ${kind.label}')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _tokenHelp(kind),
                style: Txt.bodySoft.copyWith(fontSize: 12),
              ),
              const SizedBox(height: 12),
              if (kind == IntegrationKind.cloudflare) ...[
                TextField(
                  controller: accountId,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: Txt.code.copyWith(fontSize: 12),
                  cursorColor: Pal.ember,
                  decoration: appField(
                    '32-character account ID',
                    label: 'Cloudflare Account ID',
                  ),
                ),
                const SizedBox(height: 8),
              ],
              TextField(
                controller: token,
                autofocus: true,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                style: Txt.code.copyWith(fontSize: 12),
                cursorColor: Pal.ember,
                decoration: appField(kind.tokenHint),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: label,
                style: Txt.body.copyWith(fontSize: 13),
                cursorColor: Pal.ember,
                decoration:
                    appField('Optional label, e.g. work', label: 'Label'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
    if (!(submitted ?? false) || !mounted) {
      disposeFields();
      return;
    }
    setState(() => _busyKind = kind);
    try {
      final account = await state.addAccount(
        kind: kind,
        token: token.text,
        label: label.text,
        accountId: accountId.text,
      );
      if (!mounted) return;
      _showMessage('${kind.label} connected · ${account.displayName}');
    } catch (error) {
      if (!mounted) return;
      _showMessage('$error');
    } finally {
      disposeFields();
      if (mounted) setState(() => _busyKind = null);
    }
  }

  Future<void> _remove(IntegrationAccount account) async {
    final confirmed = await showPraxisConfirm(
      context,
      title: 'Remove ${account.displayName}?',
      body: 'The token is deleted from this device. Work already pushed or '
          'deployed is not affected.',
      confirmLabel: 'Remove account',
      destructive: true,
      icon: Icons.logout_rounded,
      details: [
        ConfirmDetail('Integration', account.kind.label),
        ConfirmDetail('Account', account.displayName),
      ],
    );
    if (confirmed && mounted) {
      await AppScope.of(context).removeAccount(account);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: Pal.surface,
        behavior: SnackBarBehavior.floating,
      ));
  }

  String _tokenHelp(IntegrationKind kind) => switch (kind) {
        IntegrationKind.github =>
          'Create a fine-grained token with Contents read and write. '
              'Praxis validates it against GitHub.',
        IntegrationKind.vercel =>
          'Create an access token from Vercel Account Settings → Tokens.',
        IntegrationKind.cloudflare =>
          'Copy the Account ID from the Cloudflare dashboard overview and '
              'create an API token with Cloudflare Pages: Edit permission. '
              'Both are checked against your Pages projects.',
        IntegrationKind.expo =>
          'Create an access token from expo.dev → Account Settings → '
              'Access tokens. It is stored locally for EAS builds.',
        IntegrationKind.tavily =>
          'Copy your API key from app.tavily.com. It is stored locally for '
              'web search.',
        IntegrationKind.supabase =>
          'Create a personal access token from Supabase Account → Access '
              'tokens. It is checked against the Management API.',
      };
}

class _ConnectedService extends StatelessWidget {
  const _ConnectedService({
    required this.kind,
    required this.accounts,
    required this.activeId,
    required this.busy,
    required this.onAdd,
    required this.onActivate,
    required this.onRemove,
  });

  final IntegrationKind kind;
  final List<IntegrationAccount> accounts;
  final String activeId;
  final bool busy;
  final VoidCallback onAdd;
  final Future<void> Function(IntegrationAccount) onActivate;
  final Future<void> Function(IntegrationAccount) onRemove;

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.fromLTRB(Sp.x3, Sp.x3, Sp.x3, Sp.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ServiceMark(kind, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(kind.label, style: Txt.title.copyWith(fontSize: 14)),
                    const SizedBox(height: 1),
                    Text(
                      kind.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Txt.meta.copyWith(fontSize: 9.5),
                    ),
                  ],
                ),
              ),
              StatusPill(
                'connected',
                color: Pal.mint,
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final account in accounts)
            GestureDetector(
              onTap: () => onActivate(account),
              behavior: HitTestBehavior.opaque,
              child: Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.fromLTRB(9, 8, 3, 8),
                decoration: BoxDecoration(
                  color: account.id == activeId ? Pal.raised : null,
                  borderRadius: Rd.sm,
                  border: Border.all(
                    color: account.id == activeId
                        ? Pal.lineStrong
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      account.id == activeId
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      size: 15,
                      color: account.id == activeId ? Pal.ember : Pal.textDim,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            account.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Txt.label.copyWith(
                              color: Pal.text,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (account.kind == IntegrationKind.cloudflare &&
                              account.accountId.isNotEmpty)
                            Text(
                              'Account ID ${account.accountId}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Txt.meta.copyWith(fontSize: 8.5),
                            ),
                        ],
                      ),
                    ),
                    IconAction(
                      icon: Icons.close_rounded,
                      tooltip: 'Remove account',
                      size: 15,
                      onTap: () => onRemove(account),
                    ),
                  ],
                ),
              ),
            ),
          GhostButton(
            label: busy ? 'Connecting…' : 'Add another account',
            icon: Icons.add_rounded,
            onTap: busy ? null : onAdd,
          ),
        ],
      ),
    );
  }
}

class _AvailableService extends StatelessWidget {
  const _AvailableService({required this.kind, required this.onTap});

  final IntegrationKind kind;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Sp.x3, vertical: 10),
        child: Row(
          children: [
            ServiceMark(kind, size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kind.label,
                    style: Txt.label.copyWith(
                      color: Pal.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    kind.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Txt.meta.copyWith(fontSize: 9.5),
                  ),
                ],
              ),
            ),
            Icon(Icons.add_rounded, size: 18, color: Pal.textDim),
          ],
        ),
      ),
    );
  }
}

class _CatalogSheet extends StatelessWidget {
  const _CatalogSheet({required this.onPick});

  final ValueChanged<IntegrationKind> onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetHandle(),
        Padding(
          padding: const EdgeInsets.fromLTRB(Sp.x5, 0, Sp.x5, 6),
          child: Row(
            children: [
              Text('Select a service', style: Txt.title),
              const Spacer(),
              Text('${IntegrationKind.values.length} available',
                  style: Txt.meta),
            ],
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(Sp.x3, 4, Sp.x3, Sp.x6),
            children: [
              for (final kind in IntegrationKind.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: GestureDetector(
                    onTap: () => onPick(kind),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          ServiceMark(kind, size: 38),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(kind.label,
                                    style: Txt.title.copyWith(fontSize: 15)),
                                const SizedBox(height: 1),
                                Text(kind.description,
                                    style: Txt.meta.copyWith(fontSize: 10)),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded,
                              size: 18, color: Pal.textDim),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
