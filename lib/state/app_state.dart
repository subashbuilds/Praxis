import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/agent.dart';
import '../core/ai.dart';
import '../core/diff.dart';
import '../core/file_import.dart';
import '../core/file_types.dart';
import '../core/integrations.dart';
import '../core/linux_environment.dart';
import '../core/model_info.dart';
import '../core/project_search.dart';
import '../core/project_skills.dart';
import '../core/project_templates.dart';
import '../core/push_state.dart';
import '../core/quota_tracker.dart';
import '../core/repo_clone.dart';
import '../core/round_log.dart';
import '../core/task_checkpoint.dart';
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

/// The UI supplies this for agent-initiated Git actions. A null callback means
/// the action is unavailable, so the agent can never bypass confirmation.
typedef ConfirmPrompt = Future<bool> Function(
  String title,
  String body,
  String acceptLabel,
);

class PullResult {
  const PullResult({
    required this.updated,
    required this.added,
    required this.deleted,
    required this.keptLocal,
  });

  final int updated;
  final int added;
  final int deleted;
  final int keptLocal;

  int get changed => updated + added + deleted;

  String get summary {
    final parts = <String>[
      if (updated > 0) '$updated updated',
      if (added > 0) '$added added',
      if (deleted > 0) '$deleted removed',
      if (keptLocal > 0) '$keptLocal local kept',
    ];
    return parts.isEmpty ? 'Already up to date' : parts.join(' · ');
  }
}

class AppState extends ChangeNotifier {
  AppState({
    required this.root,
    required this.store,
    http.Client? httpClient,
    this.roundLog,
    this.checkpointStore,
    this.linux,
    this.seedWelcome = true,
  }) : httpClient = httpClient ?? http.Client();

  static const _kProviders = 'praxis.providers';
  static const _kSkills = 'praxis.skills';
  static const _kIntegrations = 'praxis.integrations';
  static const _kActiveProvider = 'praxis.activeProvider';
  static const _kWordWrap = 'praxis.wrap';
  static const _kEditorFontSize = 'praxis.editorFontSize';
  static const _kAutoNextKey = 'praxis.autoNextKey';
  static const _kAutoNextProvider = 'praxis.autoNextProvider';
  static const _kDarkMode = 'praxis.darkMode';
  static const _kAgentMode = 'praxis.agentMode';
  static const _kUsage = 'praxis.usage';
  static const _kQuota = 'praxis.quota.requests';
  static const _kDrafts = 'praxis.drafts';
  static const _kChatPrefix = 'praxis.chat.';

  final Directory root;
  final KVStore store;
  final http.Client httpClient;
  final RoundLogStore? roundLog;
  final TaskCheckpointStore? checkpointStore;
  final LinuxEnvironment? linux;
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
  int editorFontSize = 10;
  bool autoNextKey = false;
  bool autoNextProvider = false;
  bool darkMode = true;
  AgentMode agentMode = AgentMode.build;

  /// Live stream while the agent is answering. Cleared when a final transcript
  /// entry lands or the run ends.
  String liveText = '';
  String liveThinking = '';
  final List<ToolDraft> liveTools = [];

  /// Set by the agent tab while it is on screen. Without it a limit stops the
  /// run instead of guessing.
  LimitPrompt? limitPrompt;
  ConfirmPrompt? confirmPrompt;

  bool _cancelled = false;
  int _entrySeq = 0;
  UsageEvent? _lastUsage;

  final Map<String, List<ChatEntry>> _threads = {};
  final Map<String, String> _drafts = {};
  final Map<String, String> _activeFiles = {};
  final Map<String, ProjectFs> _fs = {};
  final Map<String, Shell> _shells = {};
  final Map<String, SystemShell> _systemShells = {};
  final Map<String, PushState> _pushStates = {};
  final Map<String, TaskCheckpoint> _checkpoints = {};
  QuotaTracker _quota = QuotaTracker();
  Future<void> _checkpointWrite = Future.value();

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
    RoundLogStore? roundLog;
    TaskCheckpointStore? checkpointStore;
    LinuxEnvironment? linux;
    try {
      final support = await getApplicationSupportDirectory();
      final fileLog = FileRoundLog(Directory('${support.path}/praxis/logs'));
      await fileLog.prepare();
      roundLog = fileLog;
      final fileCheckpoints = FileTaskCheckpointStore(
        Directory('${support.path}/praxis/checkpoints'),
      );
      await fileCheckpoints.prepare();
      checkpointStore = fileCheckpoints;
      linux = LinuxEnvironment(
        base: Directory('${support.path}/praxis/linux'),
      );
    } catch (_) {
      // Logging is diagnostic; it must never prevent the app from starting.
      roundLog = null;
    }
    final prefs = await SharedPreferences.getInstance();
    final state = AppState(
      root: root,
      store: PrefsStore(prefs),
      roundLog: roundLog,
      checkpointStore: checkpointStore,
      linux: linux,
    );
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
      await ProjectFs(entity).ensureRoot();
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
    _loadQuota();
    await _loadCheckpoints();
    await linux?.restoreRuntimeState();
    _loadDrafts();
    wordWrap = store.read(_kWordWrap) == 'true';
    editorFontSize =
        (int.tryParse(store.read(_kEditorFontSize) ?? '') ?? 10).clamp(8, 22);
    autoNextKey = store.read(_kAutoNextKey) == 'true';
    autoNextProvider = store.read(_kAutoNextProvider) == 'true';
    darkMode = store.read(_kDarkMode) != 'false';
    agentMode =
        store.read(_kAgentMode) == 'plan' ? AgentMode.plan : AgentMode.build;

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

  /// New projects start at the top, and a project moves to the top as soon as
  /// its conversation has newer activity than its creation time.
  List<Project> get projectsByActivity {
    final sorted = [...projects];
    sorted.sort((a, b) {
      final difference = lastActivityFor(b).compareTo(lastActivityFor(a));
      if (difference != 0) return difference;
      return b.createdAt.compareTo(a.createdAt);
    });
    return sorted;
  }

  DateTime lastActivityFor(Project project) {
    var latest = project.createdAt;
    for (final entry in threadOf(project.id)) {
      if (entry.at.isAfter(latest)) latest = entry.at;
    }
    return latest;
  }

  ProjectFs fsFor(Project project) => _fs.putIfAbsent(
        project.id,
        () => ProjectFs(Directory('${root.path}/projects/${project.id}')),
      );

  Shell shellFor(Project project) =>
      _shells.putIfAbsent(project.id, () => Shell(fsFor(project)));

  SystemShell systemShellFor(Project project) => _systemShells.putIfAbsent(
        project.id,
        () => SystemShell(fsFor(project), linux: linux),
      );

  /// The editor publishes the open path so context prefetch can include it.
  void setActiveFile(String projectId, String? path) {
    if (path == null || path.isEmpty) {
      _activeFiles.remove(projectId);
    } else {
      _activeFiles[projectId] = path;
    }
  }

  void setAgentMode(AgentMode mode) {
    if (agentMode == mode) return;
    agentMode = mode;
    unawaited(store.write(_kAgentMode, mode.name));
    notifyListeners();
  }

  Future<Project> createProject(
    String name,
    ProjectKind kind, {
    bool persistChat = true,
    String repo = '',
    String branch = 'main',
    ProjectTemplate? template,
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
    await fs.ensureRoot();
    final scaffold =
        template?.files ?? Map<String, String>.fromEntries(kind.scaffold);
    for (final file in scaffold.entries) {
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
  Future<List<String>> cloneBranches(
    String repoUrl, {
    String token = '',
  }) async {
    final ref = RepoRef.parse(repoUrl);
    if (ref == null) {
      throw RepoCloneException(
          'Use a GitHub repository such as owner/repo or https://github.com/owner/repo.');
    }
    return repoClone.branches(ref, token: token);
  }

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
    await fs.ensureRoot();
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
      } else if (cloned.files.keys.any((path) => path.endsWith('.go'))) {
        kind = ProjectKind.go;
      } else if (cloned.files.keys.any((path) => path.endsWith('.php'))) {
        kind = ProjectKind.php;
      } else if (await fs.exists('package.json')) {
        kind = ProjectKind.node;
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
      final snapshot = await fs.localSnapshot();
      final initialPush = PushState(
        owner: ref.owner,
        repo: ref.name,
        branch: cloned.branch,
        baseline: snapshot.texts,
        hashes: snapshot.hashes,
        synced: true,
      );
      _pushStates[id] = initialPush;
      await PushStore.save(fs, initialPush);
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
    _drafts.remove(project.id);
    _fs.remove(project.id);
    _shells.remove(project.id);
    _systemShells.remove(project.id);
    _pushStates.remove(project.id);
    await store.remove('$_kChatPrefix${project.id}');
    await _persistDrafts();
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

  Future<List<FileEntry>> filesOf(Project project) =>
      fsFor(project).list(includeHidden: true);

  Future<ImportSummary> importIntoProject(
    Project project,
    List<ImportEntry> entries, {
    required ImportConflictResolver onConflict,
  }) async {
    final summary = await importEntries(
      fsFor(project),
      entries,
      onConflict: onConflict,
    );
    if (summary.changed > 0 || summary.failed.isNotEmpty) notifyListeners();
    return summary;
  }

  Future<String> readFile(Project project, String path) =>
      fsFor(project).read(path);

  Future<Uint8List> readFileBytes(Project project, String path) =>
      fsFor(project).readBytes(path);

  Future<void> writeFile(Project project, String path, String content) async {
    await fsFor(project).write(path, content);
    notifyListeners();
  }

  Future<List<ProjectSkill>> installedSkillsFor(Project project) =>
      ProjectSkillsStore.load(fsFor(project));

  Future<void> deletePath(Project project, String path) async {
    await fsFor(project).delete(path);
    notifyListeners();
  }

  Future<void> renamePath(Project project, String from, String to) async {
    await fsFor(project).rename(from, to);
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
    const candidates = [
      'index.html',
      'dist/index.html',
      'build/web/index.html',
      'build/index.html',
      'public/index.html',
      'out/index.html',
      'web/index.html',
    ];
    for (final candidate in candidates) {
      if (await fs.exists(candidate)) return fs.absolute(candidate);
    }
    final entries = await fs.list();
    final html = entries
        .where((entry) =>
            !entry.isDir && entry.path.toLowerCase().endsWith('.html'))
        .toList()
      ..sort((a, b) {
        final aName = a.name.toLowerCase();
        final bName = b.name.toLowerCase();
        final aIndex = aName == 'index.html' ? 0 : 1;
        final bIndex = bName == 'index.html' ? 0 : 1;
        if (aIndex != bIndex) return aIndex.compareTo(bIndex);
        final aDepth = '/'.allMatches(a.path).length;
        final bDepth = '/'.allMatches(b.path).length;
        if (aDepth != bDepth) return aDepth.compareTo(bDepth);
        return a.path.compareTo(b.path);
      });
    return html.isEmpty ? null : fs.absolute(html.first.path);
  }

  static const _kDevPorts = 'praxis.devPorts';
  Map<String, int>? _devPortCache;

  Map<String, int> get _devPorts {
    final cached = _devPortCache;
    if (cached != null) return cached;
    final ports = <String, int>{};
    final raw = store.read(_kDevPorts);
    if (raw != null) {
      try {
        (jsonDecode(raw) as Map).forEach((key, value) {
          if (value is int) ports['$key'] = value;
        });
      } catch (_) {
        // A corrupt entry just means no remembered port.
      }
    }
    return _devPortCache = ports;
  }

  /// The port a project's dev server was last seen on. Preview uses it to load
  /// the running app instead of the exported files.
  int? devPortFor(Project project) => _devPorts[project.id];

  Future<void> setDevPort(Project project, int? port) async {
    final ports = _devPorts;
    if (port == null) {
      if (ports.remove(project.id) == null) return;
    } else {
      if (ports[project.id] == port) return;
      ports[project.id] = port;
    }
    notifyListeners();
    await store.write(_kDevPorts, jsonEncode(ports));
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

  void _loadDrafts() {
    _drafts.clear();
    final raw = store.read(_kDrafts);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          if (entry.key is String && entry.value is String) {
            _drafts[entry.key as String] = entry.value as String;
          }
        }
      }
    } catch (_) {
      _drafts.clear();
    }
  }

  String promptDraftFor(String projectId) => _drafts[projectId] ?? '';

  /// Keeps the composer alive across tabs and app restarts. Drafts are stored
  /// per project and deliberately do not rebuild the whole app on each key.
  void setPromptDraft(String projectId, String text) {
    if (text.isEmpty) {
      if (_drafts.remove(projectId) == null) return;
    } else {
      if (_drafts[projectId] == text) return;
      _drafts[projectId] = text;
    }
    unawaited(_persistDrafts());
  }

  Future<void> _persistDrafts() => store.write(_kDrafts, jsonEncode(_drafts));

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
    _liveNotify?.cancel();
    _liveNotify = null;
    liveText = '';
    liveThinking = '';
    liveTools.clear();
  }

  Timer? _liveNotify;

  /// Streaming replies produce dozens of deltas a second. Repainting the whole
  /// workspace for each one made large projects stutter, so live text is
  /// coalesced into at most one frame update every 60 ms.
  void _notifyLive() {
    if (_liveNotify != null) return;
    _liveNotify = Timer(const Duration(milliseconds: 60), () {
      _liveNotify = null;
      notifyListeners();
    });
  }

  Future<void> send(
    String projectId,
    String raw, {
    List<String> attachments = const [],
  }) =>
      _runPrompt(projectId, raw, attachments: attachments);

  Future<void> _runPrompt(
    String projectId,
    String raw, {
    List<String> attachments = const [],
    List<AiTurn>? historyOverride,
    Set<String> skipActionFingerprints = const {},
    TaskCheckpoint? resumeFrom,
    bool recordUserMessage = true,
  }) async {
    final prompt = raw.trim();
    if ((prompt.isEmpty && attachments.isEmpty) || busy) return;
    final project = projectById(projectId);
    var provider = activeProvider;
    final thread = threadOf(projectId);
    final started = DateTime.now();
    _activeProjectId = projectId;
    final quota = _quota.status(provider);
    if (quota.exhausted) {
      thread.add(_entry(
        role: ChatRole.error,
        text: 'Daily request limit reached for ${provider.name}: '
            '${quota.used}/${quota.limit}. Raise the limit in the provider '
            'settings, choose another provider, or resume tomorrow.',
        ok: false,
      ));
      notifyListeners();
      await _persistChat(projectId);
      return;
    }

    final stored = attachments.isEmpty
        ? const <String>[]
        : await attachFiles(project, attachments);

    final history = historyOverride ?? _historyFor(thread);

    if (recordUserMessage) {
      thread.add(_entry(
        role: ChatRole.user,
        text: prompt.isEmpty ? 'Look at the attached files.' : prompt,
        attachments: stored,
      ));
    }
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

    var checkpoint = (resumeFrom ??
            TaskCheckpoint(
              taskId: '$projectId-${started.microsecondsSinceEpoch}',
              projectId: projectId,
              providerId: provider.id,
              providerName: provider.name,
              model: provider.model,
              originalPrompt: TaskCheckpoint.sanitize(prompt),
              createdAt: started,
              updatedAt: started,
            ))
        .copyWith(
      providerId: provider.id,
      providerName: provider.name,
      model: provider.model,
      status: TaskCheckpointStatus.running,
      updatedAt: DateTime.now(),
      pendingStep: resumeFrom?.pendingStep ?? '',
      conversationTail: _checkpointTurns(thread),
    );
    final pendingCalls = <String, AiToolCall>{};
    var checkpointError = '';
    _queueCheckpoint(checkpoint);

    final agent = Agent(
      client: ai,
      provider: provider,
      taskId: '$projectId-${started.microsecondsSinceEpoch}',
      roundLog: roundLog,
      fs: fsFor(project),
      shell: shellFor(project),
      deviceShell: systemShellFor(project),
      contextLimit: contextLimitFor(provider.model) ?? 128000,
      linuxShell: linux != null,
      activeFile: _activeFiles[projectId],
      skills: skills,
      mode: agentMode,
      fetchText: _fetchSkillText,
      fetchBytes: _fetchUrlBytes,
      onCommitAndPush: activeGithub == null
          ? null
          : (message) => agentCommitAndPush(projectId, message),
      onPullLatest:
          activeGithub == null ? null : () => agentPullLatest(projectId),
      onProviderLimit: _handleProviderLimit,
      onModelRequest: (used) {
        checkpoint = checkpoint.copyWith(
          providerId: used.id,
          providerName: used.name,
          model: used.model,
          updatedAt: DateTime.now(),
        );
        _queueCheckpoint(checkpoint);
        unawaited(_recordModelRequest(used));
      },
      skipActionFingerprints: skipActionFingerprints,
      onTextDelta: (delta) {
        liveText += delta;
        _notifyLive();
      },
      onThinkingDelta: (delta) {
        liveThinking += delta;
        _notifyLive();
      },
      onToolStart: (call) {
        final detail = _toolDetail(call);
        pendingCalls['${call.name}|$detail'] = call;
        liveTools.add(ToolDraft(
          id: '${DateTime.now().microsecondsSinceEpoch}',
          tool: call.name,
          detail: detail,
        ));
        notifyListeners();
      },
      onReply: (reply, usedProvider) {
        final tokens = reply.usage;
        if (tokens == null) return;
        _recordUsage(usedProvider, tokens, projectId);
      },
      onDiscardLive: () {
        _clearLive();
        notifyListeners();
      },
      toolApproval: (title, body, acceptLabel) async {
        final prompt = confirmPrompt;
        // A missing UI callback means no approval can be shown. Refuse the
        // compound action rather than silently bypassing the approval gate.
        if (prompt == null) return false;
        return prompt(title, body, acceptLabel);
      },
      onEvent: (event) {
        if (event.kind == AgentEventKind.text) {
          _clearLive();
          checkpoint = checkpoint.copyWith(
            pendingStep: TaskCheckpoint.sanitize(event.text),
            updatedAt: DateTime.now(),
          );
          _queueCheckpoint(checkpoint);
          thread.add(_entry(
            role: ChatRole.assistant,
            text: event.text,
            thinking: event.thinking,
          ));
        } else if (event.kind == AgentEventKind.activity) {
          thread.add(_entry(
            role: ChatRole.activity,
            text: event.text,
            tool: event.tool,
            detail: event.detail,
          ));
        } else if (event.kind == AgentEventKind.tool) {
          final call = pendingCalls.remove('${event.tool}|${event.detail}');
          if (event.ok && call != null && _isCheckpointAction(event.tool)) {
            final label = _checkpointLabel(event.tool, event.detail);
            checkpoint = checkpoint
                .withAction(CheckpointAction(
                  fingerprint: TaskCheckpoint.actionFingerprint(
                    event.tool,
                    call.arguments,
                  ),
                  tool: event.tool,
                  label: TaskCheckpoint.sanitize(label, maxLength: 160),
                ))
                .copyWith(
                  completed: [
                    ...checkpoint.completed,
                    TaskCheckpoint.sanitize(label, maxLength: 160),
                  ].take(12).toList(),
                  updatedAt: DateTime.now(),
                );
            final path = _checkpointPath(event.tool, call.arguments);
            if (path.isNotEmpty) {
              checkpoint = checkpoint.withChangedFile(path, '');
            }
            _queueCheckpoint(checkpoint);
          }
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
      if (!_cancelled) {
        checkpoint = checkpoint.copyWith(
          status: TaskCheckpointStatus.completed,
          pendingStep: '',
          updatedAt: DateTime.now(),
        );
      }
    } on AiProviderException catch (error) {
      checkpointError = error.message;
      _clearLive();
      thread.add(_entry(role: ChatRole.error, text: error.message, ok: false));
    } catch (error) {
      checkpointError = '$error';
      _clearLive();
      thread.add(_entry(
        role: ChatRole.error,
        text: 'Unexpected error: $error',
        ok: false,
      ));
    } finally {
      // Keep whatever the model had already streamed. Stopping cleared the live
      // reply and left the thread showing only the user's prompt.
      final partialText = liveText.trim();
      final partialThinking = liveThinking.trim();
      final partialTools = List<ToolDraft>.from(liveTools);
      _clearLive();
      final elapsed = DateTime.now().difference(started);
      final interrupted = _cancelled || checkpointError.isNotEmpty;
      if (interrupted) {
        for (final path in checkpoint.changedFiles.keys.toList()) {
          try {
            final text = await fsFor(project).read(path);
            checkpoint = checkpoint.withChangedFile(
              path,
              TaskCheckpoint.digestText(text),
            );
          } catch (_) {
            // A deleted file is still recorded; resume will report it.
          }
        }
        checkpoint = checkpoint.copyWith(
          status: TaskCheckpointStatus.resumable,
          lastError: TaskCheckpoint.sanitize(checkpointError),
          pendingStep: checkpoint.pendingStep.isEmpty
              ? 'Continue the original request from the last completed step.'
              : checkpoint.pendingStep,
          gitBranch: project.branch,
          conversationTail: _checkpointTurns(thread),
          updatedAt: DateTime.now(),
        );
        try {
          final changes = await changesFor(project);
          checkpoint = checkpoint.copyWith(
            gitPaths: changes.map((change) => change.path).take(40).toList(),
          );
        } catch (_) {}
        _queueCheckpoint(checkpoint);
        await _checkpointWrite;
        thread.add(_entry(
          role: ChatRole.note,
          text: 'Paused - this task can be resumed. '
              '${checkpoint.completed.isEmpty ? 'No completed steps yet.' : 'Completed: ${checkpoint.completed.last}.'} '
              '${checkpoint.changedFiles.isEmpty ? '' : '${checkpoint.changedFiles.length} changed files recorded.'}',
        ));
      } else {
        checkpoint = checkpoint.copyWith(
          status: TaskCheckpointStatus.completed,
          gitBranch: project.branch,
          conversationTail: _checkpointTurns(thread),
          updatedAt: DateTime.now(),
        );
        _queueCheckpoint(checkpoint);
      }
      if (_cancelled && partialText.isNotEmpty) {
        for (final tool in partialTools) {
          thread.add(_entry(
            role: ChatRole.tool,
            text: tool.detail,
            tool: tool.tool,
            detail: tool.detail,
          ));
        }
        thread.add(_entry(
          role: ChatRole.assistant,
          text: partialText,
          thinking: partialThinking,
        ));
      }
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

  List<AiTurn> _historyFor(List<ChatEntry> thread) {
    final history = <AiTurn>[];
    for (final entry in thread) {
      if (entry.role == ChatRole.user) {
        history.add(AiTurn.user(entry.text));
      } else if (entry.role == ChatRole.assistant &&
          entry.text.trim().isNotEmpty) {
        history.add(AiTurn.assistant(entry.text, const []));
      }
    }
    return history;
  }

  List<CheckpointTurn> _checkpointTurns(List<ChatEntry> thread) => [
        for (final entry
            in thread.skip(thread.length > 8 ? thread.length - 8 : 0))
          if (entry.role == ChatRole.user || entry.role == ChatRole.assistant)
            CheckpointTurn(
              role: entry.role.name,
              text: TaskCheckpoint.sanitize(entry.text, maxLength: 280),
            ),
      ];

  static const _checkpointTools = {
    'write_file',
    'edit_file',
    'apply_patch',
    'download_file',
    'install_skill',
    'run_command',
    'run_commands',
    'commit_and_push',
    'pull_latest',
  };

  bool _isCheckpointAction(String tool) => _checkpointTools.contains(tool);

  String _checkpointPath(String tool, Map<String, dynamic> args) =>
      switch (tool) {
        'write_file' ||
        'edit_file' ||
        'download_file' ||
        'install_skill' =>
          (args['path'] as String? ?? '').trim(),
        _ => '',
      };

  String _checkpointLabel(String tool, String detail) => switch (tool) {
        'run_command' => 'Ran ${detail.isEmpty ? 'a command' : detail}',
        'run_commands' => 'Ran a command batch',
        'write_file' => 'Wrote ${detail.isEmpty ? 'a file' : detail}',
        'edit_file' => 'Edited ${detail.isEmpty ? 'a file' : detail}',
        'apply_patch' => 'Applied a patch',
        'download_file' => 'Downloaded ${detail.isEmpty ? 'a file' : detail}',
        'install_skill' =>
          'Installed skill ${detail.isEmpty ? '' : detail}'.trim(),
        'commit_and_push' => 'Committed and pushed changes',
        'pull_latest' => 'Pulled the latest commit',
        _ => tool,
      };

  Future<List<AgentTask>> loadAgentTasks() async {
    final log = roundLog;
    if (log == null) return const [];
    return log.loadTasks();
  }

  /// A portable, privacy-preserving export. It contains the same names and
  /// counts as Logs — never prompts, tool arguments or file contents.
  Future<String> exportAgentLogJson() async {
    final tasks = await loadAgentTasks();
    final stats = AgentRoundStats(tasks);
    final payload = {
      'app': 'Praxis',
      'kind': 'agent-rounds',
      'version': 2,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'aggregate': {
        'tasks': stats.totalTasks,
        'modelRequests': stats.totalRounds,
        'averageRoundsPerTask': stats.averageRounds,
        'repeatedCalls': stats.repeatedCalls,
        'inputTokens': stats.inputTokens,
        'outputTokens': stats.outputTokens,
        'roundsByType': {
          for (final entry in stats.byType.entries) entry.key.wire: entry.value,
        },
        'outcomes': stats.outcomes,
      },
      'tasks': [
        for (final task in tasks)
          {
            'taskId': task.taskId,
            'outcome': task.outcome?.wire,
            'rounds': [for (final round in task.rounds) round.toJson()],
          },
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Future<void> clearAgentLog() async {
    await roundLog?.clear();
    notifyListeners();
  }

  Future<void> _recordUsage(
    ProviderConfig provider,
    AiUsage tokens,
    String projectId,
  ) async {
    final event = UsageEvent(
      at: DateTime.now(),
      projectId: projectId,
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
      'write_file' ||
      'edit_file' ||
      'read_file' ||
      'download_file' =>
        '${args['path'] ?? '?'}',
      'run_command' => '${args['command'] ?? '?'}',
      'run_commands' => args['commands'] is List
          ? '${(args['commands'] as List).length} commands'
          : 'commands',
      'read_files' => args['paths'] is List
          ? '${(args['paths'] as List).length} files'
          : 'files',
      'search_and_read' => '${args['query'] ?? '?'}',
      'apply_patch' => 'patch',
      'install_skill' => '${args['name'] ?? args['source_url'] ?? 'skill'}',
      'commit_and_push' => '${args['message'] ?? 'commit'}',
      'pull_latest' => 'latest commit',
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

    // Provider fallback always needs consent for this task: providers differ
    // in data handling and capabilities, so it is never silent.
    final allowed = await (limitPrompt?.call(
          'Provider limit reached',
          '${current.name} has no usable keys left.\n\n'
              'Continue on ${candidate.name} (${candidate.model})? '
              'This is only for the current task; no default provider is changed.',
          'Continue on ${candidate.name}',
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

  TaskCheckpoint? checkpointFor(String projectId) => _checkpoints[projectId];

  bool hasResumableCheckpoint(String projectId) =>
      _checkpoints[projectId]?.resumable ?? false;

  Future<void> resumeTask(String projectId) async {
    if (busy) return;
    final checkpoint = _checkpoints[projectId];
    if (checkpoint == null || !checkpoint.resumable) return;
    final project = projectById(projectId);
    final external = await _externalChanges(project, checkpoint);
    final provider = activeProvider;
    final summary = _resumeSummary(checkpoint, external);
    final skip =
        checkpoint.completedActions.map((action) => action.fingerprint).toSet();
    final thread = threadOf(projectId);
    thread.add(_entry(
      role: ChatRole.note,
      text: 'Resumed with ${provider.name} (${provider.model}). '
          '${checkpoint.completed.isEmpty ? 'No completed steps.' : 'Completed ${checkpoint.completed.length} steps; '}'
          '${checkpoint.changedFiles.length} changed files. '
          '${external.isEmpty ? 'No external file changes detected.' : '${external.length} file(s) changed outside the task.'}',
    ));
    _queueCheckpoint(checkpoint.copyWith(
      status: TaskCheckpointStatus.running,
      updatedAt: DateTime.now(),
    ));
    notifyListeners();
    await _persistChat(projectId);
    await _runPrompt(
      projectId,
      summary,
      historyOverride: const [],
      skipActionFingerprints: skip,
      resumeFrom: checkpoint,
      recordUserMessage: false,
    );
  }

  Future<List<String>> _externalChanges(
    Project project,
    TaskCheckpoint checkpoint,
  ) async {
    final changed = <String>[];
    final fs = fsFor(project);
    for (final entry in checkpoint.changedFiles.entries) {
      try {
        final text = await fs.read(entry.key);
        final digest = TaskCheckpoint.digestText(text);
        if (entry.value.isNotEmpty && digest != entry.value) {
          changed.add(entry.key);
        }
      } catch (_) {
        // A file that disappeared is an external change too.
        changed.add(entry.key);
      }
    }
    try {
      final current = await changesFor(project);
      for (final change in current) {
        if (!checkpoint.gitPaths.contains(change.path) &&
            !changed.contains(change.path)) {
          changed.add(change.path);
        }
      }
    } catch (_) {}
    return changed.take(20).toList();
  }

  String _resumeSummary(TaskCheckpoint checkpoint, List<String> external) {
    final completed = checkpoint.completed.isEmpty
        ? '- No completed steps were recorded.'
        : checkpoint.completed.map((step) => '- $step').join('\n');
    final files = checkpoint.changedFiles.keys.isEmpty
        ? '- None recorded.'
        : checkpoint.changedFiles.keys.map((path) => '- $path').join('\n');
    final externalText = external.isEmpty
        ? '- None.'
        : external.map((path) => '- $path').join('\n');
    return '''RESUME TASK
Original request: ${checkpoint.originalPrompt}

Completed before the interruption:
$completed

Files changed before the checkpoint:
$files

External changes since the checkpoint (re-read these before editing):
$externalText

Remaining step: ${checkpoint.pendingStep.isEmpty ? 'Continue the original request from the last completed step.' : checkpoint.pendingStep}
Git branch: ${checkpoint.gitBranch.isEmpty ? 'unknown' : checkpoint.gitBranch}

Continue the task. Do not repeat a write or destructive action that already completed. Use the current files on disk, not assumptions from before the interruption.'''
        .trim();
  }

  Future<void> dismissCheckpoint(String projectId) async {
    final checkpoint = _checkpoints[projectId];
    if (checkpoint == null) return;
    _checkpoints.remove(projectId);
    notifyListeners();
    await checkpointStore?.remove(checkpoint.taskId);
  }

  void stop() {
    if (!busy) return;
    _cancelled = true;
    final projectId = _activeProjectId;
    if (projectId != null &&
        projects.any((project) => project.id == projectId)) {
      systemShellFor(projectById(projectId)).cancel();
    }
    linux?.cancel();
    notifyListeners();
  }

  void clearLive() {
    _clearLive();
    notifyListeners();
  }

  Future<void> clearChat(String projectId) async {
    _threads[projectId] = [];
    _clearLive();
    _checkpoints.remove(projectId);
    await store.remove('$_kChatPrefix$projectId');
    notifyListeners();
  }

  Future<void> _recordModelRequest(ProviderConfig provider) async {
    _quota.record(provider.id);
    notifyListeners();
    await store.write(_kQuota, jsonEncode(_quota.toJson()));
  }

  void _loadQuota() {
    try {
      final raw = store.read(_kQuota);
      _quota = QuotaTracker.fromJson(raw == null ? null : jsonDecode(raw));
    } catch (_) {
      _quota = QuotaTracker();
    }
  }

  Future<void> _loadCheckpoints() async {
    _checkpoints.clear();
    final store = checkpointStore;
    if (store == null) return;
    try {
      final all = await store.loadAll();
      for (final checkpoint in all) {
        final current = _checkpoints[checkpoint.projectId];
        if (current == null ||
            checkpoint.updatedAt.isAfter(current.updatedAt)) {
          _checkpoints[checkpoint.projectId] = checkpoint;
        }
      }
      for (final entry in _checkpoints.entries.toList()) {
        final checkpoint = entry.value;
        if (checkpoint.status == TaskCheckpointStatus.running) {
          _checkpoints[entry.key] = checkpoint.copyWith(
            status: TaskCheckpointStatus.resumable,
            lastError: 'The app closed before this task finished.',
            updatedAt: DateTime.now(),
          );
        }
      }
    } catch (_) {
      _checkpoints.clear();
    }
  }

  void _queueCheckpoint(TaskCheckpoint checkpoint) {
    _checkpoints[checkpoint.projectId] = checkpoint;
    final store = checkpointStore;
    if (store == null) return;
    _checkpointWrite = _checkpointWrite.then((_) async {
      try {
        await store.save(checkpoint);
      } catch (_) {}
    });
  }

  QuotaStatus get activeQuota => _quota.status(activeProvider);

  QuotaStatus quotaStatusFor(ProviderConfig provider) =>
      _quota.status(provider);

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
    final parsed = ProjectSkillsStore.parse(content);
    final title = name.substring(0, name.lastIndexOf('.')).replaceAll(
          RegExp(r'[-_]+'),
          ' ',
        );
    final skill = Skill(
      id: 'skill-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}',
      name: parsed.name.trim().isNotEmpty
          ? parsed.name.trim()
          : title.trim().isEmpty
              ? 'Imported skill'
              : title.trim(),
      instructions: parsed.body.trim(),
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
    String accountId = '',
  }) async {
    final trimmed = token.trim();
    final trimmedAccountId = accountId.trim();
    if (trimmed.isEmpty) {
      throw IntegrationException('Paste a token first.');
    }
    final username = switch (kind) {
      IntegrationKind.github =>
        await GitHubClient(trimmed, client: httpClient).login(),
      IntegrationKind.vercel =>
        await VercelClient(trimmed, client: httpClient).login(),
      IntegrationKind.cloudflare =>
        await _verifyCloudflareToken(trimmed, trimmedAccountId),
      IntegrationKind.supabase => await _verifySupabaseToken(trimmed),
      IntegrationKind.expo => 'Expo',
      IntegrationKind.tavily => 'Tavily',
    };
    final account = IntegrationAccount(
      id: '${kind.name}-${DateTime.now().microsecondsSinceEpoch}',
      kind: kind,
      label: label.trim(),
      username: username,
      token: trimmed,
      accountId: kind == IntegrationKind.cloudflare ? trimmedAccountId : '',
      createdAt: DateTime.now(),
    );
    await saveIntegrations(integrations.addOrReplace(account));
    return account;
  }

  Future<void> removeAccount(IntegrationAccount account) =>
      saveIntegrations(integrations.remove(account.id));

  Future<void> activateAccount(IntegrationAccount account) =>
      saveIntegrations(integrations.activate(account));

  Future<String> _verifyCloudflareToken(String token, String accountId) async {
    if (accountId.isEmpty) {
      throw IntegrationException(
          'Paste the Cloudflare Account ID for these Pages projects.');
    }
    // No list options here: some accounts reject page/per_page on the Pages
    // endpoint with a 400 even though the token itself is valid.
    final response = await httpClient.get(
      Uri.parse(
        'https://api.cloudflare.com/client/v4/accounts/'
        '$accountId/pages/projects',
      ),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    ).timeout(const Duration(seconds: 25));
    if (response.statusCode == 401 ||
        response.statusCode == 403 ||
        response.statusCode == 404) {
      throw IntegrationException(
          'Cloudflare rejected that Account ID or API token '
          '(HTTP ${response.statusCode}). Check both and the Pages: Edit '
          'permission.');
    }
    if (response.statusCode != 200) {
      throw IntegrationException(
          'Cloudflare returned HTTP ${response.statusCode} while checking '
          'the Pages project.');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['success'] != true) {
      throw IntegrationException(
          'Cloudflare rejected that Account ID or API token.');
    }
    return accountId;
  }

  Future<String> _verifySupabaseToken(String token) async {
    final response = await httpClient.get(
      Uri.https('api.supabase.com', '/v1/projects'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    ).timeout(const Duration(seconds: 25));
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw IntegrationException('Supabase rejected that access token.');
    }
    if (response.statusCode != 200) {
      throw IntegrationException(
          'Supabase returned HTTP ${response.statusCode}.');
    }
    final body = jsonDecode(response.body);
    final count = body is List ? body.length : 0;
    return count == 0 ? 'Supabase' : '$count projects';
  }

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

  Future<List<GitHubRepo>> githubRepositories(IntegrationAccount account) =>
      GitHubClient(account.token, client: httpClient).repositories();

  Future<void> createGithubBranch(
    IntegrationAccount account, {
    required String owner,
    required String repo,
    required String branch,
    required String from,
  }) =>
      GitHubClient(account.token, client: httpClient).createBranch(
        owner: owner,
        repo: repo,
        branch: branch,
        from: from,
      );

  /// Loads the branch contents once so Files and Push compare against the
  /// repository instead of treating every local file as newly added.
  Future<PushState> syncPushBaseline(
    Project project,
    IntegrationAccount account, {
    required String owner,
    required String repo,
    required String branch,
  }) async {
    final current = await pushStateFor(project);
    final sameTarget = current.owner == owner &&
        current.repo == repo &&
        current.branch == branch;
    if (sameTarget && current.synced) return current;
    final snapshot = await GitHubClient(account.token, client: httpClient)
        .snapshot(owner, repo, branch);
    final next = current.copyWith(
      owner: owner,
      repo: repo,
      branch: branch,
      baseline: snapshot.files,
      hashes: snapshot.hashes,
      synced: true,
    );
    return savePushState(project, next);
  }

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
    final current = await fsFor(project).localSnapshot();
    final paths = <String>{
      ...state.hashes.keys,
      ...state.baseline.keys,
      ...current.hashes.keys,
    }.toList()
      ..sort();
    final changes = <RepoChange>[];
    for (final path in paths) {
      final localHash = current.hashes[path];
      if (localHash == null) continue;
      var remoteHash = state.hashes[path];
      final before = state.baseline[path];
      if (remoteHash == null && before != null) {
        remoteHash = gitBlobSha(utf8.encode(before));
      }
      if (remoteHash == localHash) continue;
      final after = current.texts[path];
      final isBinary = after == null;
      final diff = isBinary ? null : computeDiff(before ?? '', after);
      changes.add(RepoChange(
        path: path,
        status: before == null && remoteHash == null
            ? RepoChangeStatus.added
            : RepoChangeStatus.modified,
        before: before ?? '',
        after: after ?? '',
        added: diff?.added ?? 0,
        removed: diff?.removed ?? 0,
        isBinary: isBinary,
        size: current.sizes[path] ?? 0,
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
    required Map<String, List<int>> files,
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

  /// Downloads the current branch archive and applies it without touching
  /// local edits that GitHub has not changed. Files changed on both sides stop
  /// the pull instead of silently overwriting either version.
  Future<PullResult> pullProject(
    Project project,
    IntegrationAccount account, {
    String? owner,
    String? repo,
    String? branch,
  }) async {
    final parts = project.repo.split('/');
    final resolvedOwner = owner?.trim().isNotEmpty == true
        ? owner!.trim()
        : parts.length == 2
            ? parts.first
            : '';
    final resolvedRepo = repo?.trim().isNotEmpty == true
        ? repo!.trim()
        : parts.length == 2
            ? parts.last
            : '';
    final resolvedBranch =
        branch?.trim().isNotEmpty == true ? branch!.trim() : project.branch;
    if (resolvedOwner.isEmpty || resolvedRepo.isEmpty) {
      throw IntegrationException('Connect a GitHub repository first.');
    }
    final state = await pushStateFor(project);
    if (state.pendingFor(resolvedOwner, resolvedRepo, resolvedBranch) > 0) {
      throw IntegrationException(
          'Push your waiting commits before pulling, so nothing is overwritten.');
    }
    final cloned = await repoClone.clone(
      repo: RepoRef(owner: resolvedOwner, name: resolvedRepo),
      branch: resolvedBranch,
      token: account.token,
    );
    final remoteTexts = <String, String>{};
    final remoteHashes = <String, String>{};
    for (final entry in cloned.files.entries) {
      final bytes = entry.value;
      remoteHashes[entry.key] = gitBlobSha(bytes);
      if (bytes.length <= 200000 && classifyFile(entry.key).isText) {
        final text = decodeUtf8(bytes, allowEmpty: true);
        if (text != null) remoteTexts[entry.key] = text;
      }
    }

    final fs = fsFor(project);
    final local = await fs.localSnapshot();
    String? baseHash(String path) {
      final known = state.hashes[path];
      if (known != null) return known;
      final text = state.baseline[path];
      return text == null ? null : gitBlobSha(utf8.encode(text));
    }

    final writes = <String, List<int>>{};
    final deletes = <String>[];
    final conflicts = <String>[];
    var keptLocal = 0;
    for (final path in remoteHashes.keys) {
      final remoteHash = remoteHashes[path];
      final localHash = local.hashes[path];
      final base = baseHash(path);
      if (localHash == null) {
        writes[path] = cloned.files[path]!;
      } else if (localHash == remoteHash) {
        continue;
      } else if (base == localHash) {
        writes[path] = cloned.files[path]!;
      } else if (base == remoteHash) {
        keptLocal++;
      } else {
        conflicts.add(path);
      }
    }
    for (final path in local.hashes.keys) {
      if (remoteHashes.containsKey(path)) continue;
      final base = baseHash(path);
      if (base == null) {
        keptLocal++;
      } else if (base == local.hashes[path]) {
        deletes.add(path);
      } else {
        conflicts.add(path);
      }
    }
    if (conflicts.isNotEmpty) {
      final shown = conflicts.take(4).join(', ');
      final more =
          conflicts.length > 4 ? ' and ${conflicts.length - 4} more' : '';
      throw IntegrationException(
          'Pull stopped because these files changed locally and on GitHub: '
          '$shown$more. Commit or stash them first.');
    }

    final added =
        writes.keys.where((path) => !local.hashes.containsKey(path)).length;
    for (final entry in writes.entries) {
      await fs.writeBytes(entry.key, entry.value);
    }
    for (final path in deletes) {
      if (await fs.exists(path)) await fs.delete(path);
    }
    final next = state.copyWith(
      owner: resolvedOwner,
      repo: resolvedRepo,
      branch: resolvedBranch,
      baseline: remoteTexts,
      hashes: remoteHashes,
      synced: true,
    );
    await savePushState(project, next);
    await updateProjectGit(
      projectById(project.id),
      repo: '$resolvedOwner/$resolvedRepo',
      branch: resolvedBranch,
    );
    notifyListeners();
    return PullResult(
      updated: writes.length - added,
      added: added,
      deleted: deletes.length,
      keptLocal: keptLocal,
    );
  }

  Future<String> _fetchSkillText(String raw) async {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw IntegrationException(
          'Use an http or https URL for the skill source.');
    }
    if (uri.host == 'github.com') {
      final parts = uri.pathSegments;
      if (parts.length >= 5 && parts[2] == 'blob') {
        final rawUri = Uri.https(
          'raw.githubusercontent.com',
          '/${parts[0]}/${parts[1]}/${parts[3]}/${parts.skip(4).join('/')}',
        );
        return _decodeRemoteText(await _fetchUrlBytes(rawUri.toString()));
      }
      if (parts.length >= 2) {
        final path = parts.length >= 5 && parts[2] == 'tree'
            ? parts.skip(4).join('/')
            : '';
        final ref = parts.length >= 5 && parts[2] == 'tree' ? parts[3] : null;
        return _fetchGithubSkill(parts[0], parts[1], path, ref);
      }
    }
    return _decodeRemoteText(await _fetchUrlBytes(uri.toString()));
  }

  String _decodeRemoteText(List<int> bytes) {
    final text = decodeUtf8(bytes, allowEmpty: true);
    if (text == null) {
      throw IntegrationException('That URL is not a text file.');
    }
    return text;
  }

  Future<String> _fetchGithubSkill(
    String owner,
    String repo,
    String path,
    String? ref,
  ) async {
    final api = Uri.https('api.github.com', '/repos/$owner/$repo');
    final token = activeGithub?.token ?? '';
    final headers = <String, String>{
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'Praxis',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    var branch = ref;
    if (branch == null) {
      final repoResponse = await httpClient
          .get(api, headers: headers)
          .timeout(const Duration(seconds: 30));
      if (repoResponse.statusCode != 200) {
        throw IntegrationException(
            'Could not read $owner/$repo (HTTP ${repoResponse.statusCode}).');
      }
      branch =
          (jsonDecode(repoResponse.body) as Map)['default_branch'] as String?;
    }
    final treeUri = Uri.https(
      'api.github.com',
      '/repos/$owner/$repo/git/trees/${Uri.encodeComponent(branch ?? 'main')}',
      {'recursive': '1'},
    );
    final treeResponse = await httpClient
        .get(treeUri, headers: headers)
        .timeout(const Duration(seconds: 45));
    if (treeResponse.statusCode != 200) {
      throw IntegrationException(
          'Could not search $owner/$repo for a SKILL.md.');
    }
    final tree = (jsonDecode(treeResponse.body) as Map)['tree'];
    if (tree is! List) {
      throw IntegrationException('That repository has no files.');
    }
    final prefix = path.isEmpty ? '' : '${path.replaceAll(RegExp(r'/$'), '')}/';
    final candidates = tree
        .whereType<Map>()
        .map((item) => item['path'] as String? ?? '')
        .where((item) =>
            item.toLowerCase().endsWith('skill.md') && item.startsWith(prefix))
        .toList()
      ..sort((a, b) => a.split('/').length.compareTo(b.split('/').length));
    if (candidates.isEmpty) {
      throw IntegrationException(
          'No SKILL.md was found at that GitHub location.');
    }
    final contentsUri = Uri.https(
      'api.github.com',
      '/repos/$owner/$repo/contents/${candidates.first}',
      branch == null ? null : {'ref': branch},
    );
    final contents = await httpClient
        .get(contentsUri, headers: headers)
        .timeout(const Duration(seconds: 30));
    if (contents.statusCode != 200) {
      throw IntegrationException('Could not read the SKILL.md from GitHub.');
    }
    final body = jsonDecode(contents.body);
    if (body is! Map || body['content'] is! String) {
      throw IntegrationException(
          'GitHub did not return the SKILL.md contents.');
    }
    final encoded = (body['content'] as String).replaceAll('\n', '');
    return _decodeRemoteText(base64Decode(encoded));
  }

  Future<List<int>> _fetchUrlBytes(String raw) async {
    var uri = Uri.parse(raw);
    if (uri.host == 'github.com') {
      final parts = uri.pathSegments;
      if (parts.length >= 5 && parts[2] == 'blob') {
        uri = Uri.https(
          'raw.githubusercontent.com',
          '/${parts[0]}/${parts[1]}/${parts[3]}/${parts.skip(4).join('/')}',
        );
      }
    }
    final token = activeGithub?.token ?? '';
    final headers = <String, String>{
      'User-Agent': 'Praxis',
      if (token.isNotEmpty &&
          (uri.host == 'api.github.com' ||
              uri.host == 'raw.githubusercontent.com'))
        'Authorization': 'Bearer $token',
    };
    final response = await httpClient
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 90));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw IntegrationException(
          'Download failed (HTTP ${response.statusCode}) for $uri.');
    }
    return response.bodyBytes;
  }

  Future<String> agentCommitAndPush(String projectId, String message) async {
    final project = projectById(projectId);
    final account = activeGithub;
    if (account == null) {
      throw IntegrationException('Add a GitHub account first.');
    }
    final state = await pushStateFor(project);
    final parts = project.repo.split('/');
    final owner = state.owner.isNotEmpty
        ? state.owner
        : parts.length == 2
            ? parts.first
            : '';
    final repo = state.repo.isNotEmpty
        ? state.repo
        : parts.length == 2
            ? parts.last
            : '';
    final branch = state.branch.isNotEmpty ? state.branch : project.branch;
    if (owner.isEmpty || repo.isEmpty) {
      throw IntegrationException(
          'Connect this project to GitHub from Push first.');
    }
    if (state.pendingFor(owner, repo, branch) > 0) {
      throw IntegrationException(
          'There are already commits waiting to push. Push those first.');
    }
    final changes = await changesFor(project);
    if (changes.isEmpty) return 'No local changes to commit or push.';
    final confirm = confirmPrompt;
    if (confirm == null) {
      throw IntegrationException(
          'Push confirmation is unavailable. Open Files → Push and try again.');
    }
    final approved = await confirm(
      'Commit and push?',
      'The agent wants to commit ${changes.length} changed file${changes.length == 1 ? '' : 's'} '
          'and push them to $owner/$repo on $branch.',
      'Commit & push',
    );
    if (!approved) throw IntegrationException('Push cancelled by the user.');

    final snapshot = await fsFor(project).localSnapshot();
    final bytes = <String, List<int>>{};
    final texts = <String, String>{};
    final hashes = <String, String>{};
    for (final change in changes) {
      bytes[change.path] = await fsFor(project).readBytes(change.path);
      final text = snapshot.texts[change.path];
      if (text != null) texts[change.path] = text;
      hashes[change.path] =
          snapshot.hashes[change.path] ?? gitBlobSha(bytes[change.path]!);
    }
    final parent = state.lastPendingFor(owner, repo, branch);
    final commit = await createGithubCommit(
      account,
      owner: owner,
      repo: repo,
      branch: branch,
      message: message.trim(),
      files: bytes,
      parentSha: parent?.sha,
    );
    var next = state
        .copyWith(owner: owner, repo: repo, branch: branch)
        .withBaseline(texts, hashes: hashes)
        .withPending(PendingCommit(
          sha: commit.sha,
          message: message.trim(),
          at: DateTime.now(),
          owner: owner,
          repo: repo,
          branch: branch,
          files: texts,
          hashes: hashes,
        ));
    await savePushState(project, next);
    await pushGithubRef(
      account,
      owner: owner,
      repo: repo,
      branch: branch,
      sha: commit.sha,
    );
    next = next.withoutPending([commit.sha]);
    await savePushState(project, next);
    await updateProjectGit(project, repo: '$owner/$repo', branch: branch);
    return 'Committed and pushed ${changes.length} file${changes.length == 1 ? '' : 's'} '
        'to $owner/$repo on $branch (${commit.sha.substring(0, 7)}).';
  }

  Future<String> agentPullLatest(String projectId) async {
    final project = projectById(projectId);
    final account = activeGithub;
    if (account == null) {
      throw IntegrationException('Add a GitHub account first.');
    }
    final state = await pushStateFor(project);
    final parts = project.repo.split('/');
    final owner = state.owner.isNotEmpty
        ? state.owner
        : parts.length == 2
            ? parts.first
            : '';
    final repo = state.repo.isNotEmpty
        ? state.repo
        : parts.length == 2
            ? parts.last
            : '';
    final branch = state.branch.isNotEmpty ? state.branch : project.branch;
    if (owner.isEmpty || repo.isEmpty) {
      throw IntegrationException('Connect this project to GitHub first.');
    }
    final confirm = confirmPrompt;
    if (confirm == null) {
      throw IntegrationException('Pull confirmation is unavailable.');
    }
    final approved = await confirm(
      'Pull latest commit?',
      'Praxis will merge changes from $owner/$repo on $branch into this project. '
          'Local edits are kept when GitHub has not touched the same file.',
      'Pull changes',
    );
    if (!approved) {
      throw IntegrationException('Pull cancelled by the user.');
    }
    final result = await pullProject(
      project,
      account,
      owner: owner,
      repo: repo,
      branch: branch,
    );
    return 'Pulled $owner/$repo · $branch: ${result.summary}.';
  }

  Future<ProjectSearchResult> searchProject(
    Project project,
    String query,
  ) =>
      ProjectSearch.run(fsFor(project), query);

  Future<void> ensureGithubRepository(
    IntegrationAccount account, {
    required String owner,
    required String repo,
    bool private = true,
  }) =>
      GitHubClient(account.token, client: httpClient)
          .ensureRepo(owner, repo, private: private);

  // Records are versioned so the first deployment made with an older manifest
  // format can be retried without being treated as "nothing changed".
  String _deployRecordKey(Project project, String platform) =>
      'praxis.deploy.${project.id}.'
      '${platform == 'cloudflare' ? 'cloudflare.v2' : platform}';

  String _deploymentSignature(List<DeploymentFile> files) {
    final sorted = [...files]..sort((a, b) => a.path.compareTo(b.path));
    final buffer = StringBuffer();
    for (final file in sorted) {
      buffer
        ..write(file.path)
        ..write(':')
        ..write(gitBlobSha(file.bytes))
        ..write(';');
    }
    return sha256.convert(utf8.encode(buffer.toString())).toString();
  }

  Future<bool> deploymentUnchanged(
    Project project, {
    required String platform,
    required String target,
  }) async {
    final files = await fsFor(project).deploymentFiles();
    final record = store.read(_deployRecordKey(project, platform));
    return record == '$target\n${_deploymentSignature(files)}';
  }

  Future<void> _rememberDeployment(
    Project project,
    String platform,
    String target,
    String signature,
  ) async {
    await store.write(
        _deployRecordKey(project, platform), '$target\n$signature');
    notifyListeners();
  }

  Future<List<CloudflarePagesProject>> cloudflareProjects(
    IntegrationAccount account,
  ) =>
      CloudflarePagesClient(
        account.token,
        accountId: account.accountId,
        client: httpClient,
      ).projects();

  Future<CloudflarePagesProject> createCloudflareProject(
    IntegrationAccount account, {
    required String name,
    String branch = 'main',
  }) =>
      CloudflarePagesClient(
        account.token,
        accountId: account.accountId,
        client: httpClient,
      ).createProject(name, branch: branch);

  Future<IntegrationResult> deployToVercel(
    Project project,
    IntegrationAccount account, {
    required String name,
    String? projectId,
    String environment = 'production',
  }) async {
    final files = await fsFor(project).deploymentFiles();
    if (files.isEmpty) {
      throw IntegrationException('This project has no files to deploy.');
    }
    final target = '${projectId ?? name}|$environment';
    final signature = _deploymentSignature(files);
    if (store.read(_deployRecordKey(project, 'vercel')) ==
        '$target\n$signature') {
      throw IntegrationException(
          'No changes since the last deployment to this Vercel project. '
          'Edit the project before deploying again.');
    }
    final result = await VercelClient(account.token, client: httpClient).deploy(
      name: name,
      projectId: projectId,
      files: files,
      environment: environment,
    );
    await _rememberDeployment(project, 'vercel', target, signature);
    return result;
  }

  Future<IntegrationResult> deployToCloudflare(
    Project project,
    IntegrationAccount account, {
    required String projectName,
    String environment = 'production',
    String branch = 'main',
  }) async {
    final files = await fsFor(project).deploymentFiles();
    if (files.isEmpty) {
      throw IntegrationException('This project has no files to deploy.');
    }
    final target = '$projectName|$environment|$branch';
    final signature = _deploymentSignature(files);
    if (store.read(_deployRecordKey(project, 'cloudflare')) ==
        '$target\n$signature') {
      throw IntegrationException(
          'No changes since the last deployment to this Pages project. '
          'Edit the project before deploying again.');
    }
    final result = await CloudflarePagesClient(
      account.token,
      accountId: account.accountId,
      client: httpClient,
    ).deploy(
      project: projectName,
      files: files,
      environment: environment,
      branch: branch,
    );
    await _rememberDeployment(
      project,
      'cloudflare',
      target,
      signature,
    );
    return result;
  }

  /// Removes the newest unpushed commit record for a branch. The files on disk
  /// stay untouched and immediately return to the changed-files list.
  Future<PushState> revertLatestPending(
    Project project, {
    required String owner,
    required String repo,
    required String branch,
  }) async {
    final current = await pushStateFor(project);
    final latest = current.lastPendingFor(owner, repo, branch);
    if (latest == null) return current;
    return savePushState(
      project,
      current.withoutPending([latest.sha]),
    );
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

  UsageStats usageForProject(String projectId) => UsageStats(
        usageEvents.where((event) => event.projectId == projectId),
      );

  int? contextUsedFor(
    String providerId,
    String model, {
    String? projectId,
  }) {
    final events = projectId == null
        ? usage.events
        : usageEvents.where((event) => event.projectId == projectId);
    for (final event in events) {
      if (event.providerId == providerId && event.model == model) {
        return event.promptTokens;
      }
    }
    return null;
  }

  int? contextLimitFor(String model) => contextWindowFor(model);

  // -------------------------------------------------------------- settings

  Future<void> setWordWrap(bool value) async {
    wordWrap = value;
    await store.write(_kWordWrap, value.toString());
    notifyListeners();
  }

  Future<void> setEditorFontSize(int value) async {
    final next = value.clamp(8, 22);
    if (next == editorFontSize) return;
    editorFontSize = next;
    await store.write(_kEditorFontSize, '$next');
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
    _drafts.clear();
    _fs.clear();
    _shells.clear();
    _systemShells.clear();
    _pushStates.clear();
    _clearLive();
    await roundLog?.clear();
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
      _kDrafts,
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
