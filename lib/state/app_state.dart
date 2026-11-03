import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/agent.dart';
import '../core/ai.dart';
import '../core/integrations.dart';
import '../core/shell.dart';
import '../core/store.dart';
import '../core/vfs.dart';
import '../models.dart';

class AppState extends ChangeNotifier {
  AppState({
    required this.root,
    required this.store,
    http.Client? httpClient,
    this.seedWelcome = true,
  }) : httpClient = httpClient ?? http.Client();

  static const _kProviders = 'devnest.providers';
  static const _kSkills = 'devnest.skills';
  static const _kIntegrations = 'devnest.integrations';
  static const _kActiveProvider = 'devnest.activeProvider';
  static const _kWordWrap = 'devnest.wrap';
  static const _kChatPrefix = 'devnest.chat.';

  final Directory root;
  final KVStore store;
  final http.Client httpClient;
  final bool seedWelcome;

  late final AiClient ai = AiClient(client: httpClient);

  final List<Project> projects = [];
  final List<ProviderConfig> providers = [];
  final List<Skill> skills = [];

  Integrations integrations = const Integrations();
  String activeProviderId = '';
  bool busy = false;
  bool wordWrap = false;
  bool _cancelled = false;
  int _entrySeq = 0;

  final Map<String, List<ChatEntry>> _threads = {};
  final Map<String, ProjectFs> _fs = {};
  final Map<String, Shell> _shells = {};

  bool _ready = false;
  bool get ready => _ready;

  static Future<AppState> bootstrap() async {
    final directory = await getApplicationDocumentsDirectory();
    final root = Directory('${directory.path}/devnest');
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
    wordWrap = store.read(_kWordWrap) == 'true';

    if (projects.isEmpty && seedWelcome) {
      await createProject('hello-dev', ProjectKind.web, persistChat: false);
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

  Future<Project> createProject(
    String name,
    ProjectKind kind, {
    bool persistChat = true,
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
    );
    await File('${dir.path}/.project.json')
        .writeAsString(jsonEncode(project.toJson()));
    final fs = ProjectFs(dir);
    for (final file in kind.scaffold) {
      await fs.write(file.key, file.value);
    }
    projects.insert(0, project);
    if (persistChat) await _persistChat(project.id);
    notifyListeners();
    return project;
  }

  Future<void> deleteProject(Project project) async {
    final dir = Directory('${root.path}/projects/${project.id}');
    if (await dir.exists()) await dir.delete(recursive: true);
    projects.removeWhere((item) => item.id == project.id);
    _threads.remove(project.id);
    _fs.remove(project.id);
    _shells.remove(project.id);
    await store.remove('$_kChatPrefix${project.id}');
    notifyListeners();
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

  /// Absolute path of the file the preview should load, or null for a project
  /// that has no HTML entry point.
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

  static String _slug(String name) {
    final base = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return base.isEmpty ? 'project' : base;
  }

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
        thread.length > 120 ? thread.sublist(thread.length - 120) : thread;
    await store.write(
      '$_kChatPrefix$projectId',
      jsonEncode(trimmed.map((entry) => entry.toJson()).toList()),
    );
  }

  String _nextId() =>
      'e${DateTime.now().microsecondsSinceEpoch}-${_entrySeq++}';

  Future<void> send(String projectId, String raw) async {
    final prompt = raw.trim();
    if (prompt.isEmpty || busy) return;
    final project = projectById(projectId);
    final provider = activeProvider;
    final thread = threadOf(projectId);

    final history = <AiTurn>[];
    for (final entry in thread) {
      if (entry.role == ChatRole.user) {
        history.add(AiTurn.user(entry.text));
      } else if (entry.role == ChatRole.assistant &&
          entry.text.trim().isNotEmpty) {
        history.add(AiTurn.assistant(entry.text, const []));
      }
    }

    thread.add(ChatEntry(
      id: _nextId(),
      role: ChatRole.user,
      text: prompt,
      at: DateTime.now(),
    ));
    notifyListeners();
    await _persistChat(projectId);

    if (!provider.isConfigured) {
      thread.add(ChatEntry(
        id: _nextId(),
        role: ChatRole.error,
        text: provider.requiresKey
            ? 'No API key for ${provider.name}. Open Settings → Models, paste a key and run Test connection.'
            : 'Finish configuring ${provider.name} in Settings → Models.',
        at: DateTime.now(),
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
      onEvent: (event) {
        thread.add(ChatEntry(
          id: _nextId(),
          role: event.kind == AgentEventKind.tool
              ? ChatRole.tool
              : event.kind == AgentEventKind.error
                  ? ChatRole.error
                  : ChatRole.assistant,
          text: event.text,
          tool: event.tool,
          detail: event.detail,
          ok: event.ok,
          at: DateTime.now(),
        ));
        notifyListeners();
      },
    );

    try {
      await agent.run(
        history: history.length > 12
            ? history.sublist(history.length - 12)
            : history,
        prompt: prompt,
        isCancelled: () => _cancelled,
      );
    } on AiProviderException catch (error) {
      thread.add(ChatEntry(
        id: _nextId(),
        role: ChatRole.error,
        text: error.message,
        at: DateTime.now(),
      ));
    } catch (error) {
      thread.add(ChatEntry(
        id: _nextId(),
        role: ChatRole.error,
        text: 'Unexpected error: $error',
        at: DateTime.now(),
      ));
    } finally {
      busy = false;
      notifyListeners();
      await _persistChat(projectId);
    }
  }

  void stop() {
    _cancelled = true;
    notifyListeners();
  }

  Future<void> clearChat(String projectId) async {
    _threads[projectId] = [];
    await store.remove('$_kChatPrefix$projectId');
    notifyListeners();
  }

  // -------------------------------------------------------------- providers

  ProviderConfig get activeProvider => providers.firstWhere(
        (provider) => provider.id == activeProviderId,
        orElse: () =>
            providers.isNotEmpty ? providers.first : kProviderPresets.first,
      );

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
    for (final preset in kProviderPresets) {
      if (!providers.any((provider) => provider.id == preset.id)) {
        providers.add(preset);
      }
    }
    activeProviderId = store.read(_kActiveProvider) ?? '';
    if (!providers.any((provider) => provider.id == activeProviderId)) {
      activeProviderId = providers
          .firstWhere((provider) => provider.ready,
              orElse: () => providers.first)
          .id;
    }
  }

  Future<void> saveProvider(ProviderConfig provider) async {
    final index = providers.indexWhere((item) => item.id == provider.id);
    if (index >= 0) {
      providers[index] = provider;
    } else {
      providers.add(provider);
    }
    await _persistProviders();
    notifyListeners();
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
      activeProviderId = providers.first.id;
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

  Future<String> testGithub() =>
      GitHubClient(integrations.githubToken, client: httpClient).login();

  Future<String> testVercel() =>
      VercelClient(integrations.vercelToken, client: httpClient).login();

  Future<IntegrationResult> pushToGithub(
    Project project, {
    required String repo,
    required bool private,
  }) async {
    final files = await fsFor(project).textFiles();
    return GitHubClient(integrations.githubToken, client: httpClient)
        .push(repoName: repo, private: private, files: files);
  }

  Future<IntegrationResult> deployToVercel(Project project,
      {required String name}) async {
    final files = await fsFor(project).textFiles();
    return VercelClient(integrations.vercelToken, client: httpClient)
        .deploy(name: name, files: files);
  }

  // -------------------------------------------------------------- settings

  Future<void> setWordWrap(bool value) async {
    wordWrap = value;
    await store.write(_kWordWrap, value.toString());
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
    for (final key in [
      _kProviders,
      _kSkills,
      _kIntegrations,
      _kActiveProvider,
      _kWordWrap
    ]) {
      await store.remove(key);
    }
    providers
      ..clear()
      ..addAll(kProviderPresets);
    skills
      ..clear()
      ..add(const Skill(
        id: 'concise',
        name: 'Concise replies',
        instructions:
            'Keep replies short and always name the files you changed.',
      ));
    integrations = const Integrations();
    activeProviderId = providers.first.id;
    wordWrap = false;
    await createProject('hello-dev', ProjectKind.web, persistChat: false);
    notifyListeners();
  }
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
