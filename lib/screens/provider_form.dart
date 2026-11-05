import 'package:flutter/material.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/ui.dart';

class ProviderFormSheet extends StatefulWidget {
  const ProviderFormSheet({super.key, required this.provider});

  final ProviderConfig provider;

  @override
  State<ProviderFormSheet> createState() => _ProviderFormSheetState();
}

class _ProviderFormSheetState extends State<ProviderFormSheet> {
  late final TextEditingController _name;
  late final TextEditingController _model;
  late final TextEditingController _baseUrl;
  late final TextEditingController _search;
  late final List<TextEditingController> _keys;
  late final List<bool> _reveal;
  late final List<String> _models;
  late final Set<String> _selected;
  int _keyIndex = 0;

  bool _testing = false;
  bool _saving = false;
  bool _fetching = false;
  String? _status;
  bool _statusError = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.provider.name);
    _model = TextEditingController(text: widget.provider.model);
    _baseUrl = TextEditingController(text: widget.provider.baseUrl);
    _search = TextEditingController();
    final stored =
        widget.provider.keys.where((key) => key.trim().isNotEmpty).toList();
    _keys = (stored.isEmpty ? [''] : stored)
        .map((key) => TextEditingController(text: key))
        .toList();
    _reveal = List<bool>.filled(_keys.length, false);
    _models = List<String>.from(widget.provider.models);
    _selected = Set<String>.from(widget.provider.selectedModels);
    _keyIndex = stored.isEmpty
        ? 0
        : widget.provider.keyIndex.clamp(0, stored.length - 1);
  }

  @override
  void dispose() {
    _name.dispose();
    _model.dispose();
    _baseUrl.dispose();
    _search.dispose();
    for (final controller in _keys) {
      controller.dispose();
    }
    super.dispose();
  }

  List<String> get _liveKeys => _keys
      .map((controller) => controller.text.trim())
      .where((key) => key.isNotEmpty)
      .toList();

  int get _activeIndex =>
      _liveKeys.isEmpty ? 0 : _keyIndex.clamp(0, _liveKeys.length - 1);

  ProviderConfig get _edited => widget.provider.copyWith(
        name: _name.text.trim().isEmpty
            ? widget.provider.name
            : _name.text.trim(),
        model: _model.text.trim(),
        baseUrl: _baseUrl.text.trim(),
        keys: _liveKeys,
        keyIndex: _activeIndex,
        models: _models,
        selectedModels: _selected.toList()..sort(),
      );

  void _addKey() {
    FocusScope.of(context).unfocus();
    setState(() {
      _keys.add(TextEditingController());
      _reveal.add(false);
    });
  }

  List<String> get _filteredModels {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return _models;
    return _models
        .where((model) => model.toLowerCase().contains(query))
        .toList();
  }

  Future<void> _removeKey(int index) async {
    final confirmed = await showPraxisConfirm(
      context,
      title: 'Delete key ${index + 1}?',
      body: 'The key is removed from this device. This cannot be undone.',
      confirmLabel: 'Delete key',
      destructive: true,
      icon: Icons.key_off_outlined,
      details: [ConfirmDetail('Provider', widget.provider.name)],
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _keys.removeAt(index).dispose();
      _reveal.removeAt(index);
      if (_keyIndex >= _keys.length) {
        _keyIndex = _keys.isEmpty ? 0 : _keys.length - 1;
      }
    });
  }

  Future<void> _test() async {
    final state = AppScope.of(context);
    setState(() {
      _testing = true;
      _status = null;
    });
    try {
      final result = await state.testProvider(_edited);
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

  Future<void> _fetchModels() async {
    if (_fetching) return;
    final state = AppScope.of(context);
    FocusScope.of(context).unfocus();
    setState(() {
      _fetching = true;
      _status = null;
    });
    try {
      final models = await state.fetchModels(_edited);
      if (!mounted) return;
      setState(() {
        _models
          ..clear()
          ..addAll(models);
        _selected.removeWhere((model) => !models.contains(model));
        _status =
            '${models.length} models fetched. Tick the ones you want to keep.';
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
      if (mounted) setState(() => _fetching = false);
    }
  }

  bool get _allSelected => _models.isNotEmpty && _selected.containsAll(_models);

  void _toggleAll() {
    setState(() {
      if (_allSelected) {
        _selected.clear();
      } else {
        _selected.addAll(_models);
      }
    });
  }

  void _useModel(String model) {
    setState(() {
      _model.text = model;
      _selected.add(model);
    });
  }

  Future<void> _save({required bool activate}) async {
    if (_saving) return;
    final keys = _liveKeys;
    if (widget.provider.requiresKey && keys.isEmpty) {
      setState(() {
        _status = 'Add at least one key before saving this provider.';
        _statusError = true;
      });
      return;
    }
    setState(() => _saving = true);
    final state = AppScope.of(context);
    final navigator = Navigator.of(context);
    final provider = widget.provider.copyWith(
      name:
          _name.text.trim().isEmpty ? widget.provider.name : _name.text.trim(),
      model: _model.text.trim().isEmpty && _selected.isNotEmpty
          ? _selected.first
          : _model.text.trim(),
      baseUrl: _baseUrl.text.trim(),
      keys: keys,
      keyIndex: keys.isEmpty ? 0 : _keyIndex.clamp(0, keys.length - 1),
      models: _models,
      selectedModels: _selected.toList()..sort(),
    );
    await state.saveProvider(provider);
    if (activate) await state.setActiveProvider(provider.id);
    if (!mounted) return;
    navigator.pop();
  }

  Future<void> _delete() async {
    final state = AppScope.of(context);
    final navigator = Navigator.of(context);
    final confirmed = await showPraxisConfirm(
      context,
      title: 'Delete ${widget.provider.name}?',
      body: 'The provider, its keys and saved model choices are removed from '
          'this device. This cannot be undone.',
      confirmLabel: 'Delete provider',
      destructive: true,
      icon: Icons.delete_outline_rounded,
      details: [ConfirmDetail('Provider', widget.provider.name)],
    );
    if (!confirmed || !mounted) return;
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
                  : 'Key from ${widget.provider.hint}. Keys are tried in order.',
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
            const SizedBox(height: 16),
            Row(
              children: [
                Text('KEYS', style: Txt.overline.copyWith(fontSize: 9.5)),
                const Spacer(),
                TextButton(
                  onPressed: _addKey,
                  child: const Text('+ Add key'),
                ),
              ],
            ),
            for (var i = 0; i < _keys.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _keys[i],
                        style: Txt.code.copyWith(fontSize: 12),
                        cursorColor: Pal.ember,
                        obscureText: !_reveal[i],
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: appField(
                          widget.provider.requiresKey ? 'sk-…' : 'Not required',
                          label: 'Key ${i + 1}',
                          suffix: IconAction(
                            icon: _reveal[i]
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            tooltip: _reveal[i] ? 'Hide key' : 'Show key',
                            size: 18,
                            onTap: () =>
                                setState(() => _reveal[i] = !_reveal[i]),
                          ),
                        ),
                      ),
                    ),
                    if (_keys.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, left: 2),
                        child: IconAction(
                          icon: Icons.remove_circle_outline_rounded,
                          tooltip: 'Remove key',
                          size: 18,
                          color: Pal.rose,
                          onTap: () => _removeKey(i),
                        ),
                      ),
                  ],
                ),
              ),
            if (_liveKeys.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (var i = 0; i < _liveKeys.length; i++)
                      GestureDetector(
                        onTap: () => setState(() => _keyIndex = i),
                        behavior: HitTestBehavior.opaque,
                        child: StatusPill(
                          'Key ${i + 1}',
                          color: i == _activeIndex ? Pal.ember : Pal.textDim,
                        ),
                      ),
                  ],
                ),
              ),
            Text(
              'The active key is used first. When it hits its limit the agent '
              'moves down this list — asking first unless automatic key '
              'switching is on in Settings.',
              style: Txt.meta.copyWith(height: 1.5),
            ),
            const SizedBox(height: 16),
            Text('MODEL', style: Txt.overline.copyWith(fontSize: 9.5)),
            const SizedBox(height: 8),
            TextField(
              controller: _model,
              style: Txt.code.copyWith(fontSize: 12),
              cursorColor: Pal.ember,
              autocorrect: false,
              enableSuggestions: false,
              decoration: appField('model-name', label: 'Active model'),
            ),
            if (_selected.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final model in (_selected.toList()..sort()))
                    GestureDetector(
                      onTap: () => _useModel(model),
                      child: StatusPill(
                        model,
                        color: _model.text.trim() == model
                            ? Pal.ember
                            : Pal.textDim,
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                GhostButton(
                  label: _fetching ? 'Fetching…' : 'Fetch models',
                  icon: Icons.download_rounded,
                  onTap: _fetching ? null : _fetchModels,
                ),
                const Spacer(),
                if (_models.isNotEmpty)
                  TextButton(
                    onPressed: _toggleAll,
                    child: Text(_allSelected ? 'Deselect all' : 'Select all'),
                  ),
              ],
            ),
            if (_models.isNotEmpty) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _search,
                style: Txt.body.copyWith(fontSize: 12),
                cursorColor: Pal.ember,
                onChanged: (_) => setState(() {}),
                decoration: appField(
                  'Search ${_models.length} models',
                  suffix: _search.text.isEmpty
                      ? const Icon(Icons.search_rounded, size: 17)
                      : IconAction(
                          icon: Icons.close_rounded,
                          tooltip: 'Clear search',
                          size: 16,
                          onTap: () {
                            _search.clear();
                            setState(() {});
                          },
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                height: 240,
                decoration: BoxDecoration(
                  color: Pal.raised,
                  borderRadius: Rd.sm,
                  border: Border.all(color: Pal.line),
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: _filteredModels.length,
                  itemBuilder: (context, index) {
                    final model = _filteredModels[index];
                    final checked = _selected.contains(model);
                    final active = _model.text.trim() == model;
                    return InkWell(
                      onTap: () => setState(() {
                        if (checked) {
                          _selected.remove(model);
                        } else {
                          _selected.add(model);
                        }
                      }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        child: Row(
                          children: [
                            Checkbox(
                              value: checked,
                              activeColor: Pal.ember,
                              checkColor: Pal.onEmber,
                              onChanged: (value) => setState(() {
                                if (value ?? false) {
                                  _selected.add(model);
                                } else {
                                  _selected.remove(model);
                                }
                              }),
                            ),
                            Expanded(
                              child: Text(
                                model,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Txt.code.copyWith(fontSize: 11),
                              ),
                            ),
                            if (active)
                              StatusPill('active', color: Pal.mint)
                            else
                              TextButton(
                                onPressed: () => _useModel(model),
                                child: const Text('Use'),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
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
