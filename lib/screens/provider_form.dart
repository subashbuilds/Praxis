import 'package:flutter/material.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

class ProviderFormSheet extends StatefulWidget {
  const ProviderFormSheet({super.key, required this.provider});

  final ProviderConfig provider;

  @override
  State<ProviderFormSheet> createState() => _ProviderFormSheetState();
}

class _ProviderFormSheetState extends State<ProviderFormSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.provider.name);
  late final TextEditingController _model =
      TextEditingController(text: widget.provider.model);
  late final TextEditingController _baseUrl =
      TextEditingController(text: widget.provider.baseUrl);
  late final TextEditingController _apiKey =
      TextEditingController(text: widget.provider.apiKey);

  bool _obscure = true;
  bool _testing = false;
  bool _saving = false;
  String? _status;
  bool _statusError = false;

  @override
  void dispose() {
    _name.dispose();
    _model.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  ProviderConfig get _edited => widget.provider.copyWith(
        name: _name.text.trim().isEmpty
            ? widget.provider.name
            : _name.text.trim(),
        model: _model.text.trim(),
        baseUrl: _baseUrl.text.trim(),
        apiKey: _apiKey.text.trim(),
      );

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _status = null;
    });
    try {
      final result = await AppScope.of(context).testProvider(_edited);
      if (!mounted) return;
      setState(() {
        _status = result;
        _statusError = false;
      });
    } on AiProviderException catch (error) {
      if (!mounted) return;
      setState(() {
        _status = error.message;
        _statusError = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = '$error';
        _statusError = true;
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save({required bool activate}) async {
    if (_saving) return;
    setState(() => _saving = true);
    final state = AppScope.of(context);
    final navigator = Navigator.of(context);
    await state.saveProvider(_edited);
    if (activate) {
      await state.setActiveProvider(_edited.id);
    }
    if (!mounted) return;
    navigator.pop();
  }

  Future<void> _delete() async {
    final state = AppScope.of(context);
    final navigator = Navigator.of(context);
    await state.deleteProvider(widget.provider);
    if (!mounted) return;
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final provider = _edited;
    final isCustom = widget.provider.isCustom;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Sp.page, 0, Sp.page, Sp.x6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            Row(
              children: [
                Expanded(
                  child: Text(
                    isCustom ? 'Custom endpoint' : widget.provider.name,
                    style: Txt.headline.copyWith(fontSize: 22),
                  ),
                ),
                if (isCustom)
                  IconAction(
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'Delete provider',
                    color: Pal.rose,
                    onTap: _delete,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              widget.provider.hint.isEmpty
                  ? 'Keys are stored in app preferences on this device.'
                  : 'Key from ${widget.provider.hint}',
              style: Txt.meta,
            ),
            const SizedBox(height: Sp.x4),
            if (isCustom) ...[
              TextField(
                controller: _name,
                style: Txt.body,
                cursorColor: Pal.ember,
                decoration: appField('Display name', label: 'Name'),
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _baseUrl,
              style: Txt.code.copyWith(fontSize: 12),
              cursorColor: Pal.ember,
              autocorrect: false,
              enableSuggestions: false,
              decoration: appField(
                'https://api.example.com/v1',
                label: 'Base URL (OpenAI-compatible)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _model,
              style: Txt.code.copyWith(fontSize: 12),
              cursorColor: Pal.ember,
              autocorrect: false,
              enableSuggestions: false,
              decoration: appField('model-name', label: 'Model'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _apiKey,
              style: Txt.code.copyWith(fontSize: 12),
              cursorColor: Pal.ember,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: appField(
                widget.provider.requiresKey ? 'sk-…' : 'Not required',
                label: 'API key',
                suffix: IconAction(
                  icon: _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  tooltip: _obscure ? 'Show key' : 'Hide key',
                  size: 18,
                  onTap: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: Sp.x3),
            Row(
              children: [
                GhostButton(
                  label: _testing ? 'Testing…' : 'Test connection',
                  icon: Icons.wifi_tethering_rounded,
                  onTap: _testing || provider.model.isEmpty ? null : _test,
                ),
                const Spacer(),
                StatusPill(
                  provider.ready ? 'key set' : 'no key',
                  color: provider.ready ? Pal.mint : Pal.amber,
                ),
              ],
            ),
            if (_status != null) ...[
              const SizedBox(height: Sp.x3),
              Panel(
                borderColor:
                    (_statusError ? Pal.rose : Pal.mint).withOpacity(0.4),
                padding: const EdgeInsets.all(Sp.x3),
                child: Text(
                  _status!,
                  style: Txt.bodySoft.copyWith(
                    fontSize: 12,
                    color: _statusError ? Pal.rose : Pal.mint,
                  ),
                ),
              ),
            ],
            const SizedBox(height: Sp.x4),
            EmberButton(
              label: 'Use this model',
              icon: Icons.bolt_rounded,
              loading: _saving,
              onTap: _saving ? null : () => _save(activate: true),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: _saving ? null : () => _save(activate: false),
                child: const Text('Save without switching'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
