import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/agent.dart';
import '../core/ai.dart';
import '../core/diff.dart';
import '../core/integrations.dart';
import '../core/model_info.dart';
import '../core/push_state.dart';
import '../core/repo_clone.dart';
import '../core/shell.dart';
import '../core/store.dart';
import '../core/system_shell.dart';
import '../core/usage.dart';
import '../core/vfs.dart';
import '../models.dart';

/// The UI supplies this so the agent can ask before moving to another key or
/// provider. With the automatic switches on, the same code path runs silently.
typedef LimitPrompt = Future<bool> Function(
  String title,
  String body,
  String acceptLabel,
);

class AppState extends ChangeNotifier {
  AppState({
    required this.root,
    required this.store,
    http.Client? httpClient,
    this.seedWelcome = true,
  }) : httpClient = httpClient ?? http.Client();

  static const _kProviders = 'praxis.providers';
  static const _kSkills = 'praxis.skills';
  static const _kIntegrations = 'praxis.integrations';
  static const _kActiveProvider = 'praxis.activeProvider';
  static const _kWordWrap = 'praxis.wrap';
  static const _kAutoNextKey = 'praxis.autoNextKey';
  static const _kAutoNextProvider = 'praxis.autoNextProvider';
  static const _kDarkMode = 'praxis.darkMode';
  static const _kUsage = 'praxis.usage';
  static const _kChatPrefix = 'praxis.chat.';

  final Directory root;
  final KVStore store;
  final http.Client httpClient;
  final bool seedWelcome;

  late final AiClient ai = AiClient(client: httpClient);
  late final RepoCloneService repoClone = RepoCloneService(client: httpClient);

  final List<Project> projects = [];
  final List<ProviderConfig> providers = [];
  final List<Skill> skills = [];
  final List<UsageEvent> usageEvents = [];

  Integrations integrations = const Integrations();
  String activeProviderId = '';
  bool busy = false;
  bool wordWrap = false;
  bool autoNextKey = false;
  bool autoNextProvider = false;
  bool darkMode = true;

  /// Live stream while the agent is answering. Cleared when a final transcript
  /// entry lands or the run ends.
  String liveText = '';
  String liveThinking = '';
  final List<ToolDraft> liveTools = [];

  /// Set by the agent tab while it is on screen. Without it a limit stops the
  /// run instead of guessing.
  LimitPrompt? limitPrompt;

  bool _cancelled = false;
  int _entrySeq = 0;
  UsageEvent? _lastUsage;

  final Map<String, List<ChatEntry>> _threads = {};
  final Map<String, ProjectFs> _fs = {};
  final Map<String, Shell> _shells = {};
  final Map<String, SystemShell> _systemShells = {};
  final Map<String, PushState> _pushStates = {};

  bool _ready = false;
  bool get ready => _ready;

  List<ProviderConfig> get configuredProviders =>
      providers.where((provider) => provider.isConfigured).toList();

  UsageStats get usage => UsageStats(usageEvents);
  UsageEvent? get lastUsage => _lastUsage;
  IntegrationAccount? get activeGithub =>
      integrations.activeFor(IntegrationKind.github);
  IntegrationAccount? get activeVercel =>
      integrations.activeFor(IntegrationKind.vercel);

  bool get hasLiveReply =>
      liveText.isNotEmpty || liveThinking.isNotEmpty || liveTools.isNotEmpty;

  static Future<AppState> bootstrap() async {
    final directory = await getApplicationDocumentsDirectory();
    final root = Directory('${directory.path}/praxis');
    final prefs = await SharedPreferences.getInstance();
    final state = AppState(root: root, store: PrefsStore(prefs));
    await state.init();
    return state;
  }

  Future<void> init() async {
    await root.create(recursive: true);
    final projectsDir = Directory('${root.path}/projects');
    await projectsDir.create(recursive: true);

    projects.clear();
    await for (final entity in projectsDir.list()) {
      if (entity is! Directory) continue;
      final meta = File('${entity.path}/.project.json');
      if (!await meta.exists()) continue;
      try {
        final json = jsonDecode(await meta.readAsString());
        projects.add(Project.fromJson((json as Map).cast<String, dynamic>()));
      } catch (_) {
        // A broken meta file should not hide the rest of the projects.
      }
    }
    projects.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    _loadProviders();
    _loadSkills();
    _loadIntegrations();
    _loadUsage();
    wordWrap = store.read(_kWordWrap) == 'true';
    autoNextKey = store.read(_kAutoNextKey) == 'true';
    autoNextProvider = store.read(_kAutoNextProvider) == 'true';
    darkMode = store.read(_kDarkMode) != 'false';

    if (projects.isEmpty && seedWelcome) {
      await createProject('hello-praxis', ProjectKind.web, persistChat: false);
    }
    _ready = true;
    notifyListeners();
  }

  // ---------------------------------------------------------------- projects

  Project projectById(String id) => projects.firstWhere(
        (project) => project.id == id,
        orElse: () => projects.first,
      );

  ProjectFs fsFor(Project project) => _fs.putIfAbsent(
        project.id,
        () => ProjectFs(Directory('${root.path}/projects/${project.id}')),
      );

  Shell shellFor(Project project) =>
      _shells.putIfAbsent(project.id, () => Shell(fsFor(project)));

  SystemShell systemShellFor(Project project) => _systemShells.putIfAbsent(
        project.id,
        () => SystemShell(fsFor(project)),
      );

  Future<Project> createProject(
    String name,
    ProjectKind kind, {
    bool persistChat = true,
    String repo = '',
    String branch = 'main',
  }) async {
    final slug = _slug(name);
    final id =
        '$slug-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    final dir = Directory('${root.path}/projects/$id');
    await dir.create(recursive: true);
    final project = Project(
      id: id,
      name: name.trim().isEmpty ? slug : name.trim(),
      kind: kind,
      createdAt: DateTime.now(),
      repo: repo,
      branch: branch,
    );
    final fs = ProjectFs(dir);
    for (final file in kind.scaffold) {
      await fs.write(file.key, file.value);
    }
    await _writeProjectMeta(dir, project);
    projects.insert(0, project);
    if (persistChat) await _persistChat(project.id);
    notifyListeners();
    return project;
  }

  /// Downloads a GitHub branch archive, writes it into a real project folder
  /// and records the repo/branch metadata. No git binary is needed.
  Future<Project> cloneProject({
    required String name,
    required String repoUrl,
    required String branch,
    String token = '',
  }) async {
    final ref = RepoRef.parse(repoUrl);
    if (ref == null) {
      throw RepoCloneException(
          'Use a GitHub repository such as owner/repo or https://github.com/owner/repo.');
    }
    final cloned = await repoClone.clone(
      repo: ref,
      branch: branch,
      token: token,
    );
    final slug = _slug(name.trim().isEmpty ? ref.name : name);
    final id =
        '$slug-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    final dir = Directory('${root.path}/projects/$id');
    await dir.create(recursive: true);
    final fs = ProjectFs(dir);
    try {
      for (final entry in cloned.files.entries) {
        await fs.writeBytes(entry.key, entry.value);
      }
      ProjectKind kind = ProjectKind.blank;
      if (await fs.exists('pubspec.yaml')) {
        kind = ProjectKind.flutter;
      } else if (await fs.exists('index.html') ||
          cloned.files.keys.any((path) => path.endsWith('.html'))) {
        kind = ProjectKind.web;
      } else if (cloned.files.keys.any((path) => path.endsWith('.py'))) {
        kind = ProjectKind.python;
      }
      final project = Project(
        id: id,
        name: name.trim().isEmpty ? ref.name : name.trim(),
        kind: kind,
        createdAt: DateTime.now(),
        repo: ref.slug,
        branch: cloned.branch,
      );
      await _writeProjectMeta(dir, project);
      projects.insert(0, project);
      notifyListeners();
      return project;
    } catch (error) {
      if (await dir.exists()) await dir.delete(recursive: true);
      if (error is RepoCloneException) rethrow;
      throw RepoCloneException('Could not create the project: $error');
    }
  }

  Future<void> _writeProjectMeta(Directory dir, Project project) =>
      File('${dir.path}/.project.json')
          .writeAsString(jsonEncode(project.toJson()));

  Future<void> deleteProject(Project project) async {
    final dir = Directory('${root.path}/projects/${project.id}');
    if (await dir.exists()) await dir.delete(recursive: true);
    projects.removeWhere((item) => item.id == project.id);
    _threads.remove(project.id);
    _fs.remove(project.id);
    _shells.remove(project.id);
    _systemShells.remove(project.id);
    _pushStates.remove(project.id);
    await store.remove('$_kChatPrefix${project.id}');
    notifyListeners();
  }

  /// Updates the branch/repo recorded in project metadata.
  Future<Project> updateProjectGit(
    Project project, {
    String? repo,
    String? branch,
  }) async {
    final next = project.copyWith(repo: repo, branch: branch);
    final index = projects.indexWhere((item) => item.id == project.id);
    if (index >= 0) projects[index] = next;
    await _writeProjectMeta(
        Directory('${root.path}/projects/${project.id}'), next);
    notifyListeners();
    return next;
  }

  Future<List<FileEntry>> filesOf(Project project) => fsFor(project).list();

  Future<String> readFile(Project project, String path) =>
      fsFor(project).read(path);

  Future<void> writeFile(Project project, String path, String content) async {
    await fsFor(project).write(path, content);
    notifyListeners();
  }

  Future<void> deletePath(Project project, String path) async {
    await fsFor(project).delete(path);
    notifyListeners();
  }

  Future<void> createFile(Project project, String path,
      {String content = ''}) async {
    await fsFor(project).write(path, content);
    notifyListeners();
  }

  Future<void> createFolder(Project project, String path) async {
    await fsFor(project).createDir(path);
    notifyListeners();
  }

  Future<String?> previewFile(Project project) async {
    final fs = fsFor(project);
    if (await fs.exists('index.html')) return fs.absolute('index.html');
    final entries = await fs.list();
    for (final entry in entries) {
      if (!entry.isDir && entry.path.endsWith('.html')) {
        return fs.absolute(entry.path);
      }
    }
    return null;
  }

  Future<Uint8List> exportZip(Project project) => fsFor(project).zipBytes();

  static String _slug(String name) {
    final base = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return base.isEmpty ? 'project' : base;
  }

  // ------------------------------------------------------------- attachments

  Future<List<String>> attachFiles(Project project, List<String> paths) async {
    final fs = fsFor(project);
    final saved = <String>[];
    for (final path in paths) {
      final source = File(path);
      if (!await source.exists()) continue;
      final rawName = source.uri.pathSegments.last;
      final safe = rawName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      var name = safe.isEmpty ? 'attachment' : safe;
      if (await fs.exists('attachments/$name')) {
        final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
        name = '$stamp-$name';
      }
      await fs.copyFromOutside(source, 'attachments/$name');
      saved.add('attachments/$name');
    }
    if (saved.isNotEmpty) notifyListeners();
    return saved;
  }

  String attachmentPath(Project project, String relative) =>
      fsFor(project).absolute(relative);

  // ------------------------------------------------------------------- chat

  List<ChatEntry> threadOf(String projectId) {
    final cached = _threads[projectId];
    if (cached != null) return cached;
    final thread = <ChatEntry>[];
    final raw = store.read('$_kChatPrefix$projectId');
    if (raw != null) {
      try {
        for (final item in jsonDecode(raw) as List) {
          thread.add(ChatEntry.fromJson((item as Map).cast<String, dynamic>()));
        }
      } catch (_) {
        // ignore a corrupt transcript
      }
    }
    return _threads[projectId] = thread;
  }

  Future<void> _persistChat(String projectId) async {
    final thread = _threads[projectId];
    if (thread == null) return;
    final trimmed =
        thread.length > 140 ? thread.sublist(thread.length - 140) : thread;
    await store.write(
      '$_kChatPrefix$projectId',
      jsonEncode(trimmed.map((entry) => entry.toJson()).toList()),
    );
  }

  String _nextId() =>
      'e${DateTime.now().microsecondsSinceEpoch}-${_entrySeq++}';

  ChatEntry _entry({
    required ChatRole role,
    String text = '',
    String tool = '',
    String detail = '',
    String thinking = '',
    String patch = '',
    int added = 0,
    int removed = 0,
    List<String> attachments = const [],
    bool ok = true,
  }) =>
      ChatEntry(
        id: _nextId(),
        role: role,
        text: text,
        tool: tool,
        detail: detail,
        thinking: thinking,
        patch: patch,
        added: added,
        removed: removed,
        attachments: attachments,
        ok: ok,
        at: DateTime.now(),
      );

  void _addNote(String text) {
    final projectId = _activeProjectId;
    if (projectId == null) return;
    threadOf(projectId).add(_entry(role: ChatRole.note, text: text));
    notifyListeners();
  }

  String? _activeProjectId;

  void _clearLive() {
    liveText = '';
    liveThinking = '';
    liveTools.clear();
  }

  Future<void> send(
    String projectId,
    String raw, {
    List<String> attachments = const [],
  }) async {
    final prompt = raw.trim();
    if ((prompt.isEmpty && attachments.isEmpty) || busy) return;
    final project = projectById(projectId);
    var provider = activeProvider;
    final thread = threadOf(projectId);
    final started = DateTime.now();
    _activeProjectId = projectId;

    final stored = attachments.isEmpty
        ? const <String>[]
        : await attachFiles(project, attachments);

    final history = <AiTurn>[];
    for (final entry in thread) {
      if (entry.role == ChatRole.user) {
        history.add(AiTurn.user(entry.text));
      } else if (entry.role == ChatRole.assistant &&
          entry.text.trim().isNotEmpty) {
        history.add(AiTurn.assistant(entry.text, const []));
      }
    }

    thread.add(_entry(
      role: ChatRole.user,
      text: prompt.isEmpty ? 'Look at the attached files.' : prompt,
      attachments: stored,
    ));
    _clearLive();
    notifyListeners();
    await _persistChat(projectId);

    if (!provider.isConfigured) {
      thread.add(_entry(
        role: ChatRole.error,
        text: provider.requiresKey
            ? 'No provider is ready. Open Settings → Providers and add an API key.'
            : 'Finish configuring ${provider.name} in Settings → Providers.',
      ));
      notifyListeners();
      await _persistChat(projectId);
      return;
    }

    busy = true;
    _cancelled = false;
    notifyListeners();

    final agent = Agent(
      client: ai,
      provider: provider,
      fs: fsFor(project),
      shell: shellFor(project),
      skills: skills,
      onProviderLimit: _handleProviderLimit,
      onTextDelta: (delta) {
        liveText += delta;
        notifyListeners();
      },
      onThinkingDelta: (delta) {
        liveThinking += delta;
        notifyListeners();
      },
      onToolStart: (call) {
        liveTools.add(ToolDraft(
          id: '${DateTime.now().microsecondsSinceEpoch}',
          tool: call.name,
          detail: _toolDetail(call),
        ));
        notifyListeners();
      },
      onReply: (reply, usedProvider) {
        final tokens = reply.usage;
        if (tokens == null) return;
        _recordUsage(usedProvider, tokens);
      },
      onEvent: (event) {
        if (event.kind == AgentEventKind.text) {
          _clearLive();
          thread.add(_entry(
            role: ChatRole.assistant,
            text: event.text,
            thinking: event.thinking,
          ));
        } else if (event.kind == AgentEventKind.tool) {
          if (liveTools.isNotEmpty) {
            final index = liveTools.indexWhere((draft) =>
                draft.tool == event.tool && draft.detail == event.detail);
            if (index >= 0) {
              liveTools.removeAt(index);
            } else {
              liveTools.removeAt(0);
            }
          }
          thread.add(_entry(
            role: ChatRole.tool,
            text: event.text,
            tool: event.tool,
            detail: event.detail,
            thinking: event.thinking,
            patch: event.patch,
            added: event.added,
            removed: event.removed,
            ok: event.ok,
          ));
        } else {
          _clearLive();
          thread.add(_entry(
            role: ChatRole.error,
            text: event.text,
            ok: false,
          ));
        }
        notifyListeners();
      },
    );

    final modelPrompt = stored.isEmpty
        ? prompt
        : '$prompt\n\nFiles the user attached (already inside the project):\n'
            '${stored.map((path) => '- $path').join('\n')}';

    try {
      await agent.run(
        history: history.length > 14
            ? history.sublist(history.length - 14)
            : history,
        prompt: modelPrompt,
        isCancelled: () => _cancelled,
      );
    } on AiProviderException catch (error) {
      _clearLive();
      thread.add(_entry(role: ChatRole.error, text: error.message, ok: false));
    } catch (error) {
      _clearLive();
      thread.add(_entry(
        role: ChatRole.error,
        text: 'Unexpected error: $error',
        ok: false,
      ));
    } finally {
      _clearLive();
      final elapsed = DateTime.now().difference(started);
      thread.add(_entry(
        role: ChatRole.note,
        text:
            '${_cancelled ? 'Stopped' : 'Ran'} for ${formatDuration(elapsed)}',
      ));
      busy = false;
      _activeProjectId = null;
      notifyListeners();
      await _persistChat(projectId);
    }
  }

  Future<void> _recordUsage(ProviderConfig provider, AiUsage tokens) async {
    final event = UsageEvent(
      at: DateTime.now(),
      providerId: provider.id,
      providerName: provider.name,
      keyIndex: provider.keyIndex,
      model: provider.model,
      promptTokens: tokens.promptTokens,
      completionTokens: tokens.completionTokens,
    );
    _lastUsage = event;
    usageEvents.add(event);
    if (usageEvents.length > 4000) {
      usageEvents.removeRange(0, usageEvents.length - 4000);
    }
    notifyListeners();
    await _persistUsage();
  }

  String _toolDetail(AiToolCall call) {
    final args = call.arguments;
    return switch (call.name) {
      'write_file' || 'read_file' => '${args['path'] ?? '?'}',
      'run_command' => '${args['command'] ?? '?'}',
      'list_files' =>
        (args['path'] as String? ?? '').isEmpty ? '.' : '${args['path']}',
      _ => '',
    };
  }

  Future<ProviderConfig?> _handleProviderLimit(
    ProviderConfig current,
    AiProviderException error,
  ) async {
    final index = providers.indexWhere((item) => item.id == current.id);
    if (index >= 0) providers[index] = current;

    if (current.hasMoreKeys) {
      var nextIndex = -1;
      for (var i = current.keyIndex + 1; i < current.keys.length; i++) {
        if (current.keys[i].trim().isNotEmpty) {
          nextIndex = i;
          break;
        }
      }
      if (nextIndex >= 0) {
        final allowed = autoNextKey ||
            await (limitPrompt?.call(
                  'Key limit reached',
                  '${current.name} (key ${current.keyIndex + 1}) reports this key is rate-limited or out of credit.\n\n'
                      'Use key ${nextIndex + 1} of ${current.keys.length}?',
                  'Use key ${nextIndex + 1}',
                ) ??
                Future.value(false));
        if (!allowed) return null;
        final next = current.copyWith(keyIndex: nextIndex);
        _replaceProvider(next);
        _clearLive();
        _addNote(
          '${current.name} (key ${current.keyIndex + 1}) reached its limit. Using key ${nextIndex + 1}.',
        );
        await _persistProviders();
        notifyListeners();
        return next;
      }
    }

    ProviderConfig? candidate;
    for (final provider in providers) {
      if (provider.id == current.id) continue;
      if (provider.isConfigured) {
        candidate = provider;
        break;
      }
    }
    if (candidate == null) return null;

    final allowed = autoNextProvider ||
        await (limitPrompt?.call(
              'Provider limit reached',
              '${current.name} has no usable keys left.\n\n'
                  'Continue with ${candidate.name} (${candidate.model})?',
              'Use ${candidate.name}',
            ) ??
            Future.value(false));
    if (!allowed) return null;
    activeProviderId = candidate.id;
    _clearLive();
    _addNote(
      '${current.name}${current.keys.length > 1 ? ' (all keys)' : ''} reached its limit. Switched to ${candidate.name} (key ${candidate.keyIndex + 1}).',
    );
    await store.write(_kActiveProvider, candidate.id);
    notifyListeners();
    return candidate;
  }

  void stop() {
    _cancelled = true;
    notifyListeners();
  }

  void clearLive() {
    _clearLive();
    notifyListeners();
  }

  Future<void> clearChat(String projectId) async {
    _threads[projectId] = [];
    _clearLive();
    await store.remove('$_kChatPrefix$projectId');
    notifyListeners();
  }

  // -------------------------------------------------------------- providers

  ProviderConfig get activeProvider => providers.firstWhere(
        (provider) => provider.id == activeProviderId,
        orElse: () =>
            providers.isNotEmpty ? providers.first : kProviderPresets.first,
      );

  List<ProviderConfig> get availablePresets => kProviderPresets
      .where((preset) => !providers.any((item) => item.id == preset.id))
      .toList();

  bool isPresetAdded(String id) =>
      providers.any((provider) => provider.id == id);

  void _loadProviders() {
    providers.clear();
    final raw = store.read(_kProviders);
    if (raw != null) {
      try {
        for (final item in jsonDecode(raw) as List) {
          providers.add(
              ProviderConfig.fromJson((item as Map).cast<String, dynamic>()));
        }
      } catch (_) {
        providers.clear();
      }
    }
    // Older builds stored every preset, configured or not. The new provider
    // picker shows only providers that actually have a key or are keyless.
    providers.removeWhere((provider) => !provider.isConfigured);
    activeProviderId = store.read(_kActiveProvider) ?? '';
    if (!providers.any((provider) => provider.id == activeProviderId)) {
      activeProviderId = providers.isEmpty ? '' : providers.first.id;
    }
  }

  Future<void> saveProvider(ProviderConfig provider) async {
    _replaceProvider(provider);
    if (activeProviderId.isEmpty) activeProviderId = provider.id;
    await _persistProviders();
    notifyListeners();
  }

  void _replaceProvider(ProviderConfig provider) {
    final index = providers.indexWhere((item) => item.id == provider.id);
    if (index >= 0) {
      providers[index] = provider;
    } else {
      providers.add(provider);
    }
  }

  Future<List<String>> fetchModels(ProviderConfig provider) async {
    final models = await ai.listModels(provider);
    final index = providers.indexWhere((item) => item.id == provider.id);
    if (index >= 0) {
      providers[index] = providers[index].copyWith(models: models);
      await _persistProviders();
      notifyListeners();
    }
    return models;
  }

  ProviderConfig newCustomProvider() => ProviderConfig(
        id: 'custom-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}',
        name: 'Custom endpoint',
        icon: 'assets/icons/opencode.svg',
        baseUrl: 'https://',
        model: '',
        flavor: ApiFlavor.openai,
        requiresKey: true,
        isCustom: true,
        hint: 'Any OpenAI-compatible URL',
      );

  Future<void> deleteProvider(ProviderConfig provider) async {
    if (!provider.isCustom) return;
    providers.removeWhere((item) => item.id == provider.id);
    if (activeProviderId == provider.id) {
      activeProviderId = providers.isEmpty ? '' : providers.first.id;
      await store.write(_kActiveProvider, activeProviderId);
    }
    await _persistProviders();
    notifyListeners();
  }

  Future<void> setActiveProvider(String id) async {
    activeProviderId = id;
    await store.write(_kActiveProvider, id);
    notifyListeners();
  }

  /// Switches to a specific provider/model without mutating its saved model.
  Future<void> setActiveModel(String providerId, String model) async {
    final index = providers.indexWhere((provider) => provider.id == providerId);
    if (index < 0) return;
    providers[index] = providers[index].copyWith(model: model);
    activeProviderId = providerId;
    await _persistProviders();
    await store.write(_kActiveProvider, providerId);
    notifyListeners();
  }

  Future<String> testProvider(ProviderConfig provider) async {
    final reply = await ai.complete(
      provider: provider,
      system: 'You are a connection test. Reply with the single word: ok',
      turns: const [AiTurn.user('ping')],
      tools: const [],
      maxTokens: 24,
    );
    final text = reply.text.trim();
    return text.isEmpty
        ? 'Connected, but the model returned no text.'
        : 'Connected: $text';
  }

  Future<void> _persistProviders() => store.write(
        _kProviders,
        jsonEncode(providers.map((provider) => provider.toJson()).toList()),
      );

  // ----------------------------------------------------------------- skills

  void _loadSkills() {
    skills.clear();
    final raw = store.read(_kSkills);
    if (raw != null) {
      try {
        for (final item in jsonDecode(raw) as List) {
          skills.add(Skill.fromJson((item as Map).cast<String, dynamic>()));
        }
      } catch (_) {
        skills.clear();
      }
    }
    if (skills.isEmpty) {
      skills.add(const Skill(
        id: 'concise',
        name: 'Concise replies',
        instructions:
            'Keep replies short and always name the files you changed.',
      ));
    }
  }

  Future<void> saveSkill(Skill skill) async {
    final index = skills.indexWhere((item) => item.id == skill.id);
    if (index >= 0) {
      skills[index] = skill;
    } else {
      skills.add(skill);
    }
    await store.write(
        _kSkills, jsonEncode(skills.map((item) => item.toJson()).toList()));
    notifyListeners();
  }

  Future<void> deleteSkill(Skill skill) async {
    skills.removeWhere((item) => item.id == skill.id);
    await store.write(
        _kSkills, jsonEncode(skills.map((item) => item.toJson()).toList()));
    notifyListeners();
  }

  Future<Skill?> importSkillFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    final name = file.uri.pathSegments.last;
    final lower = name.toLowerCase();
    if (!lower.endsWith('.md') && !lower.endsWith('.txt')) return null;
    final content = await file.readAsString();
    if (content.length > 200000) return null;
    final title = name.substring(0, name.lastIndexOf('.')).replaceAll(
          RegExp(r'[-_]+'),
          ' ',
        );
    final skill = Skill(
      id: 'skill-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}',
      name: title.trim().isEmpty ? 'Imported skill' : title.trim(),
      instructions: content.trim(),
    );
    await saveSkill(skill);
    return skill;
  }

  Skill newSkill() => Skill(
        id: 'skill-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}',
        name: '',
        instructions: '',
      );

  // ----------------------------------------------------------- integrations

  void _loadIntegrations() {
    final raw = store.read(_kIntegrations);
    if (raw == null) return;
    try {
      integrations = Integrations.fromJson(
          (jsonDecode(raw) as Map).cast<String, dynamic>());
    } catch (_) {
      integrations = const Integrations();
    }
  }

  Future<void> saveIntegrations(Integrations next) async {
    integrations = next;
    await store.write(_kIntegrations, jsonEncode(next.toJson()));
    notifyListeners();
  }

  Future<IntegrationAccount> addAccount({
    required IntegrationKind kind,
    required String token,
    String label = '',
  }) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      throw IntegrationException('Paste a token first.');
    }
    final username = kind == IntegrationKind.github
        ? await GitHubClient(trimmed, client: httpClient).login()
        : await VercelClient(trimmed, client: httpClient).login();
    final account = IntegrationAccount(
      id: '${kind.name}-${DateTime.now().microsecondsSinceEpoch}',
      kind: kind,
      label: label.trim(),
      username: username,
      token: trimmed,
      createdAt: DateTime.now(),
    );
    await saveIntegrations(integrations.addOrReplace(account));
    return account;
  }

  Future<void> removeAccount(IntegrationAccount account) =>
      saveIntegrations(integrations.remove(account.id));

  Future<void> activateAccount(IntegrationAccount account) =>
      saveIntegrations(integrations.activate(account));

  Future<String> testGithubToken(String token) =>
      GitHubClient(token, client: httpClient).login();

  Future<String> testVercelToken(String token) =>
      VercelClient(token, client: httpClient).login();

  Future<List<String>> githubBranches(
    IntegrationAccount account,
    String owner,
    String repo,
  ) =>
      GitHubClient(account.token, client: httpClient).branches(owner, repo);

  Future<PushState> pushStateFor(Project project) async {
    final cached = _pushStates[project.id];
    if (cached != null) return cached;
    final loaded = await PushStore.load(fsFor(project));
    return _pushStates[project.id] = loaded;
  }

  Future<PushState> savePushState(Project project, PushState state) async {
    _pushStates[project.id] = state;
    await PushStore.save(fsFor(project), state);
    notifyListeners();
    return state;
  }

  Future<List<RepoChange>> changesFor(Project project) async {
    final state = await pushStateFor(project);
    final current = await fsFor(project).textFiles();
    final paths = <String>{...state.baseline.keys, ...current.keys}.toList()
      ..sort();
    final changes = <RepoChange>[];
    for (final path in paths) {
      final before = state.baseline[path];
      final after = current[path];
      if (after == null) continue;
      if (before == after) continue;
      final diff = computeDiff(before ?? '', after);
      changes.add(RepoChange(
        path: path,
        status:
            before == null ? RepoChangeStatus.added : RepoChangeStatus.modified,
        before: before ?? '',
        after: after,
        added: diff.added,
        removed: diff.removed,
      ));
    }
    return changes;
  }

  Future<int> pendingCommitsFor(Project project) async {
    final state = await pushStateFor(project);
    final parts = project.repo.split('/');
    final owner = state.owner.isNotEmpty
        ? state.owner
        : (parts.length == 2 ? parts.first : '');
    final repo = state.repo.isNotEmpty
        ? state.repo
        : (parts.length == 2 ? parts.last : '');
    final branch = project.branch;
    return state.pendingFor(owner, repo, branch);
  }

  Future<GitHubCommit> createGithubCommit(
    IntegrationAccount account, {
    required String owner,
    required String repo,
    required String branch,
    required String message,
    required Map<String, String> files,
    String? parentSha,
  }) =>
      GitHubClient(account.token, client: httpClient).createCommit(
        owner: owner,
        repo: repo,
        branch: branch,
        message: message,
        files: files,
        parentSha: parentSha,
      );

  Future<void> pushGithubRef(
    IntegrationAccount account, {
    required String owner,
    required String repo,
    required String branch,
    required String sha,
  }) =>
      GitHubClient(account.token, client: httpClient).pushRef(
        owner: owner,
        repo: repo,
        branch: branch,
        sha: sha,
      );

  Future<IntegrationResult> deployToVercel(
    Project project,
    IntegrationAccount account, {
    required String name,
  }) async {
    final files = await fsFor(project).textFiles();
    return VercelClient(account.token, client: httpClient)
        .deploy(name: name, files: files);
  }

  // ---------------------------------------------------------------- usage

  void _loadUsage() {
    usageEvents.clear();
    final raw = store.read(_kUsage);
    if (raw == null) return;
    try {
      for (final item in jsonDecode(raw) as List) {
        if (item is Map) {
          final event = UsageEvent.fromJson(item.cast<String, dynamic>());
          if (event != null) usageEvents.add(event);
        }
      }
    } catch (_) {
      usageEvents.clear();
    }
    if (usageEvents.isNotEmpty) _lastUsage = usageEvents.last;
  }

  Future<void> _persistUsage() => store.write(
        _kUsage,
        jsonEncode(usageEvents.map((event) => event.toJson()).toList()),
      );

  int? contextUsedFor(String providerId, String model) =>
      usage.latestFor(providerId, model)?.promptTokens;

  int? contextLimitFor(String model) => contextWindowFor(model);

  // -------------------------------------------------------------- settings

  Future<void> setWordWrap(bool value) async {
    wordWrap = value;
    await store.write(_kWordWrap, value.toString());
    notifyListeners();
  }

  Future<void> setAutoNextKey(bool value) async {
    autoNextKey = value;
    await store.write(_kAutoNextKey, value.toString());
    notifyListeners();
  }

  Future<void> setAutoNextProvider(bool value) async {
    autoNextProvider = value;
    await store.write(_kAutoNextProvider, value.toString());
    notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    darkMode = value;
    await store.write(_kDarkMode, value.toString());
    notifyListeners();
  }

  Future<void> resetEverything() async {
    final projectsDir = Directory('${root.path}/projects');
    if (await projectsDir.exists()) await projectsDir.delete(recursive: true);
    await projectsDir.create(recursive: true);
    projects.clear();
    _threads.clear();
    _fs.clear();
    _shells.clear();
    _systemShells.clear();
    _pushStates.clear();
    _clearLive();
    usageEvents.clear();
    _lastUsage = null;
    for (final key in [
      _kProviders,
      _kSkills,
      _kIntegrations,
      _kActiveProvider,
      _kWordWrap,
      _kAutoNextKey,
      _kAutoNextProvider,
      _kUsage,
    ]) {
      await store.remove(key);
    }
    providers.clear();
    skills
      ..clear()
      ..add(const Skill(
        id: 'concise',
        name: 'Concise replies',
        instructions:
            'Keep replies short and always name the files you changed.',
      ));
    integrations = const Integrations();
    activeProviderId = '';
    wordWrap = false;
    autoNextKey = false;
    autoNextProvider = false;
    await createProject('hello-praxis', ProjectKind.web, persistChat: false);
    notifyListeners();
  }
}

String formatDuration(Duration duration) {
  if (duration.inSeconds < 60) return '${duration.inSeconds}s';
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60);
  if (minutes < 60) return '${minutes}m ${seconds}s';
  final hours = duration.inHours;
  return '${hours}h ${minutes.remainder(60)}m';
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({
    super.key,
    required AppState state,
    required super.child,
  }) : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this widget');
    return scope!.notifier!;
  }
}
