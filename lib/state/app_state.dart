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
import '../core/background_jobs.dart';
import '../core/cloudflare_routing.dart';
import '../core/dependencies.dart';
import '../core/deploy_logs.dart';
import '../core/ai.dart';
import '../core/diff.dart';
import '../core/file_import.dart';
import '../core/file_types.dart';
import '../core/follow_ups.dart';
import '../core/gitignore.dart';
import '../core/integrations.dart';
import '../core/linux_environment.dart';
import '../core/model_info.dart';
import '../core/package_cache.dart';
import '../core/agent_todos.dart';
import '../core/project_env.dart';
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

/// Asks the user which configured provider and model to use after every key
/// on the current provider has failed. Returning null stops the run.
typedef ProviderChoicePrompt = Future<ProviderChoice?> Function(
  ProviderConfig current,
  List<ProviderConfig> providers,
  String reason,
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

/// A deployment owned by AppState rather than the deploy sheet. Keeping it
/// here means closing the sheet does not cancel the upload or lose its result.
class DeployJob {
  DeployJob({
    required this.platform,
    required this.runtime,
    DateTime? startedAt,
  }) : startedAt = startedAt ?? DateTime.now();

  final IntegrationKind platform;
  final String runtime;
  final DateTime startedAt;
  String jobId = '';
  bool running = true;
  DeployProgress? progress;
  IntegrationResult? result;
  String? error;
  String? failureLogs;
  String? failureRuntime;
  LastDeployLog? lastDeploy;
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
    BackgroundJobPlatform? backgroundJobs,
  })  : httpClient = httpClient ?? http.Client(),
        backgroundJobPlatform = backgroundJobs ?? BackgroundJobPlatform();

  static const _kProviders = 'praxis.providers';
  static const _kSkills = 'praxis.skills';
  static const _kLiveDraft = 'praxis.liveDraft';
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
  final BackgroundJobPlatform backgroundJobPlatform;

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
  ProviderChoicePrompt? providerChoicePrompt;
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
  final Map<String, List<AgentTodo>> _todos = {};
  final Map<String, DeployJob> _deployJobs = {};
  late final BackgroundJobJournal _jobJournal = BackgroundJobJournal(store);
  Future<void> _foregroundSync = Future.value();
  String? _activeAgentJobId;
  bool _foregroundServiceOn = false;
  bool _jobsLoaded = false;
  QuotaTracker _quota = QuotaTracker();
  Future<void> _checkpointWrite = Future.value();
  Future<void> _todosWrite = Future.value();

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
    await _jobJournal.load();
    _jobsLoaded = true;
    _restoreDeployJobRecords();
    await linux?.restoreRuntimeState();
    _loadDrafts();
    await _restoreLiveDraft();
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

  // ----------------------------------------------------------- background jobs

  List<BackgroundJobRecord> get backgroundJobs =>
      List.unmodifiable(_jobJournal.items);

  List<BackgroundJobRecord> get runningBackgroundJobs =>
      _jobJournal.items.where((job) => job.running).toList();

  BackgroundJobRecord _startBackgroundJob({
    required Project project,
    required BackgroundJobKind kind,
    required String title,
    required String detail,
    Map<String, dynamic> data = const {},
  }) {
    final now = DateTime.now();
    final record = BackgroundJobRecord(
      id: '${kind.name}-${now.microsecondsSinceEpoch}',
      projectId: project.id,
      projectName: project.name,
      kind: kind,
      title: title,
      detail: detail,
      startedAt: now,
      updatedAt: now,
      data: data,
    );
    _jobJournal.upsert(record);
    _syncForegroundService();
    notifyListeners();
    return record;
  }

  void _updateBackgroundJob(
    String id, {
    String? detail,
    BackgroundJobStatus? status,
    bool persist = true,
  }) {
    final index = _jobJournal.items.indexWhere((job) => job.id == id);
    if (index < 0) return;
    final current = _jobJournal.items[index];
    final next = current.copyWith(
      detail: detail,
      status: status,
      updatedAt: DateTime.now(),
    );
    _jobJournal.upsert(next, persist: persist);
    _syncForegroundService();
    notifyListeners();
  }

  void _finishBackgroundJob(
    String id, {
    required BackgroundJobStatus status,
    required String detail,
  }) =>
      _updateBackgroundJob(id, status: status, detail: detail);

  void _syncForegroundService() {
    final active = runningBackgroundJobs;
    final title = active.length > 1
        ? 'Praxis · ${active.length} jobs running'
        : active.isNotEmpty
            ? active.first.title
            : '';
    final detail = active.length > 1
        ? active
            .map((job) => job.detail.isEmpty ? job.title : job.detail)
            .join(' · ')
        : active.isNotEmpty
            ? active.first.detail
            : '';
    _foregroundSync = _foregroundSync.then((_) async {
      if (active.isEmpty) {
        if (!_foregroundServiceOn) return;
        await backgroundJobPlatform.stop();
        _foregroundServiceOn = false;
        return;
      }
      if (_foregroundServiceOn) {
        await backgroundJobPlatform.update(title: title, detail: detail);
      } else {
        await backgroundJobPlatform.start(title: title, detail: detail);
        _foregroundServiceOn = true;
      }
    });
  }

  Future<void> clearFinishedBackgroundJobs() async {
    _jobJournal.clearFinished();
    notifyListeners();
    await _jobJournal.flush();
  }

  String _platformLabel(IntegrationKind platform) => switch (platform) {
        IntegrationKind.github => 'GitHub',
        IntegrationKind.vercel => 'Vercel',
        IntegrationKind.cloudflare => 'Cloudflare Pages',
        IntegrationKind.expo => 'Expo',
        IntegrationKind.tavily => 'Tavily',
        IntegrationKind.supabase => 'Supabase',
      };

  void _restoreDeployJobRecords() {
    for (final record in _jobJournal.items) {
      if (record.kind != BackgroundJobKind.deploy ||
          record.status != BackgroundJobStatus.interrupted) {
        continue;
      }
      if (_deployJobs.containsKey(record.projectId)) continue;
      final platformName = '${record.data['platform'] ?? ''}';
      final platform = IntegrationKind.values.firstWhere(
        (value) => value.name == platformName,
        orElse: () => IntegrationKind.vercel,
      );
      final job = DeployJob(
        platform: platform,
        runtime: '${record.data['runtime'] ?? ''}',
        startedAt: record.startedAt,
      )
        ..jobId = record.id
        ..running = false
        ..error = record.detail.isEmpty
            ? 'Praxis closed before this deployment finished.'
            : record.detail;
      _deployJobs[record.projectId] = job;
    }
  }

  // ---------------------------------------------------------------- projects

  Project projectById(String id) => projects.firstWhere(
        (project) => project.id == id,
        orElse: () => projects.first,
      );

  /// Pinned projects stay first, then new projects start at the top and a
  /// project moves up as soon as its conversation has newer activity than its
  /// creation time.
  List<Project> get projectsByActivity {
    final sorted = [...projects];
    sorted.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
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
        () => SystemShell(
          fsFor(project),
          linux: linux,
          packageCacheRoot: Directory('${root.path}/package-cache'),
        ),
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
        baseHashes: snapshot.hashes,
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
    _jobJournal.items
        .removeWhere((job) => job.projectId == project.id && !job.running);
    if (_jobsLoaded) await _jobJournal.flush();
    await store.remove('$_kChatPrefix${project.id}');
    await _persistDrafts();
    notifyListeners();
  }

  Future<Project> renameProject(Project project, String name) async {
    final trimmed = name.trim();
    final next =
        project.copyWith(name: trimmed.isEmpty ? project.name : trimmed);
    if (next.name == project.name) return project;
    _replaceProject(next);
    await _writeProjectMeta(
        Directory('${root.path}/projects/${project.id}'), next);
    notifyListeners();
    return next;
  }

  Future<Project> setProjectPinned(Project project, bool pinned) async {
    final next = project.copyWith(pinned: pinned);
    if (next.pinned == project.pinned) return project;
    _replaceProject(next);
    await _writeProjectMeta(
        Directory('${root.path}/projects/${project.id}'), next);
    notifyListeners();
    return next;
  }

  void _replaceProject(Project project) {
    final index = projects.indexWhere((item) => item.id == project.id);
    if (index >= 0) projects[index] = project;
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

  Future<List<ProjectEnvEntry>> environmentFor(Project project) =>
      ProjectEnvStore.load(fsFor(project));

  Future<void> saveEnvironment(
    Project project,
    List<ProjectEnvEntry> entries,
  ) =>
      ProjectEnvStore.save(fsFor(project), entries);

  Future<CloudflareDeployPlan> cloudflareDeployPlan(Project project) =>
      planCloudflareDeploy(fsFor(project));

  /// The checklist currently shown for a project. The agent updates this while
  /// it works, and the persisted copy restores it after a pause or restart.
  List<AgentTodo> todosFor(String projectId) => _todos[projectId] ?? const [];

  Future<void> loadTodos(Project project) async {
    final loaded = await ProjectTodosStore.load(fsFor(project));
    _todos[project.id] = loaded;
    notifyListeners();
  }

  void _setTodos(Project project, List<AgentTodo> next) {
    _todos[project.id] = List.unmodifiable(next);
    notifyListeners();
    _todosWrite = _todosWrite
        .then((_) => ProjectTodosStore.save(fsFor(project), next))
        .catchError((Object _) {});
  }

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
  int? devPortFor(Project project) {
    final stored = _devPorts[project.id];
    // Zero is the explicit "preview project files" choice, so clearing the
    // default must not fall back to 3000 again.
    if (stored != null) return stored == 0 ? null : stored;
    return project.kind == ProjectKind.node ? 3000 : null;
  }

  /// The deploy target last chosen for this project and platform, so the
  /// deploy sheet can preselect it instead of starting from scratch.
  String? deployChoice(Project project, String platform) =>
      store.read('praxis.deployChoice.${project.id}.$platform');

  Future<void> rememberDeployChoice(
    Project project,
    String platform,
    String value,
  ) async {
    await store.write('praxis.deployChoice.${project.id}.$platform', value);
  }

  Future<void> setDevPort(Project project, int? port) async {
    final ports = _devPorts;
    final value = port ?? 0;
    if (ports[project.id] == value) return;
    ports[project.id] = value;
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
    // Keep the whole transcript for normal projects. Dropping the middle of a
    // long conversation made earlier messages look like they had vanished
    // after a restart. Only an extreme transcript is compressed, and then the
    // opening request and the recent tail are preserved.
    final trimmed = thread.length > 2000
        ? [...thread.take(40), ...thread.skip(thread.length - 1960)]
        : thread;
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
    _liveDraftTimer?.cancel();
    _liveDraftTimer = null;
    liveText = '';
    liveThinking = '';
    liveTools.clear();
    _lastLiveDraftText = '';
    _liveDraftVersion++;
    final hadDraft = _liveDraftSaved;
    _liveDraftSaved = false;
    if (hadDraft) {
      // Queue the clear behind any write already in flight, so a slow storage
      // write cannot restore a finished reply after the run ends.
      _liveDraftWrites = _liveDraftWrites
          .catchError((Object _) {})
          .then((_) => store.write(_kLiveDraft, ''));
    }
  }

  Timer? _liveNotify;
  Timer? _liveDraftTimer;
  Future<void> _liveDraftWrites = Future.value();
  int _liveDraftVersion = 0;
  DateTime _lastLiveDraft = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastLiveDraftText = '';
  bool _liveDraftSaved = false;
  bool _restoringLiveDraft = false;
  Timer? _chatPersistTimer;
  String? _chatPersistProject;

  /// Streaming replies produce dozens of deltas a second. Repainting the whole
  /// workspace for each one made large projects stutter, so live text is
  /// coalesced into at most one frame update every 60 ms.
  void _notifyLive() {
    _queueLiveDraft();
    if (_liveNotify != null) return;
    _liveNotify = Timer(const Duration(milliseconds: 60), () {
      _liveNotify = null;
      notifyListeners();
    });
  }

  /// The app can be killed while a reply is streaming. Keep a draft of the
  /// text received so far, but not more often than every two seconds: writing
  /// a large transcript string to platform storage on every repaint made big
  /// projects stutter.
  void _queueLiveDraft() {
    final projectId = _activeProjectId;
    final text = liveText;
    if (projectId == null ||
        _restoringLiveDraft ||
        text.trim().isEmpty ||
        text == _lastLiveDraftText) {
      return;
    }
    final wait = DateTime.now().difference(_lastLiveDraft);
    const interval = Duration(milliseconds: 2000);
    if (wait >= interval) {
      _lastLiveDraft = DateTime.now();
      unawaited(_writeLiveDraft(projectId));
      return;
    }
    _liveDraftTimer ??= Timer(interval - wait, () {
      _liveDraftTimer = null;
      _queueLiveDraft();
    });
  }

  Future<void> _writeLiveDraft(String projectId) async {
    if (_activeProjectId != projectId) return;
    final text = liveText;
    if (text.trim().isEmpty || text == _lastLiveDraftText) return;
    _lastLiveDraftText = text;
    _liveDraftSaved = true;
    final version = _liveDraftVersion;
    final thinking = liveThinking;
    _liveDraftWrites =
        _liveDraftWrites.catchError((Object _) {}).then((_) async {
      // A run that finished while the previous write was waiting must not
      // leave its partial reply behind.
      if (version != _liveDraftVersion) return;
      await store.write(
        _kLiveDraft,
        jsonEncode({
          'projectId': projectId,
          'text': text,
          'thinking': thinking,
          'at': DateTime.now().toIso8601String(),
        }),
      );
    });
    await _liveDraftWrites;
  }

  /// Transcript writes used to happen on every tool event, which meant
  /// re-encoding the whole conversation dozens of times per task. Coalesce
  /// them; the final write still runs when the run ends.
  void _queueChatPersist(String projectId) {
    _chatPersistProject = projectId;
    if (_chatPersistTimer != null) return;
    _chatPersistTimer = Timer(const Duration(milliseconds: 1500), () {
      _chatPersistTimer = null;
      final id = _chatPersistProject;
      _chatPersistProject = null;
      if (id != null) unawaited(_persistChat(id));
    });
  }

  Future<void> _restoreLiveDraft() async {
    final raw = store.read(_kLiveDraft);
    if (raw == null || raw.isEmpty) return;
    await store.write(_kLiveDraft, '');
    Map<String, dynamic> data;
    try {
      data = (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    final projectId = data['projectId'] as String? ?? '';
    final text = (data['text'] as String? ?? '').trim();
    final thinking = data['thinking'] as String? ?? '';
    if (projectId.isEmpty ||
        text.isEmpty ||
        !projects.any((project) => project.id == projectId)) {
      return;
    }
    _restoringLiveDraft = true;
    try {
      final thread = threadOf(projectId);
      if (thread.isNotEmpty &&
          thread.last.role == ChatRole.assistant &&
          thread.last.text.trim() == text) {
        return;
      }
      thread.add(_entry(
        role: ChatRole.assistant,
        text: text,
        thinking: thinking,
      ));
      thread.add(_entry(
        role: ChatRole.note,
        text: 'Reply saved before the app closed.',
      ));
      await _persistChat(projectId);
    } finally {
      _restoringLiveDraft = false;
    }
  }

  Future<void> send(
    String projectId,
    String raw, {
    List<String> attachments = const [],
  }) async {
    // A paused task must continue from its checkpoint. Sending a fresh prompt
    // with only the recent transcript made the model restart the whole task.
    if (attachments.isEmpty && !busy && _looksLikeContinuePrompt(raw)) {
      if (hasResumableCheckpoint(projectId)) {
        await resumeTask(projectId);
        return;
      }
      // No checkpoint was kept, but the project already has this conversation.
      // Send an explicit continuation brief so the model resumes instead of
      // starting the task again from its first step.
      final continued = _continuePrompt(projectId);
      if (continued != null) {
        threadOf(projectId).add(_entry(
          role: ChatRole.note,
          text: 'Continuing the previous task from the last unfinished step.',
        ));
        notifyListeners();
        unawaited(_persistChat(projectId));
        await _runPrompt(projectId, continued, recordUserMessage: false);
        return;
      }
    }
    await _runPrompt(projectId, raw, attachments: attachments);
  }

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
    // The daily request limit is informational only: it is counted and shown,
    // never used to refuse a prompt or pause a run.

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
    // Mark the composer busy before the first persistence await so tapping
    // Send or Resume gives immediate feedback on a large conversation.
    busy = true;
    _cancelled = false;
    notifyListeners();
    unawaited(_persistChat(projectId));

    if (!provider.isConfigured) {
      thread.add(_entry(
        role: ChatRole.error,
        text: provider.requiresKey
            ? 'No provider is ready. Open Settings → Providers and add an API key.'
            : 'Finish configuring ${provider.name} in Settings → Providers.',
      ));
      busy = false;
      notifyListeners();
      await _persistChat(projectId);
      return;
    }

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
    var pauseMessage = '';
    _queueCheckpoint(checkpoint);
    _activeAgentJobId = _startBackgroundJob(
      project: project,
      kind: BackgroundJobKind.agent,
      title: 'Agent task',
      detail: 'Working with ${provider.name}',
      data: {'taskId': checkpoint.taskId},
    ).id;
    final savedTodos = await ProjectTodosStore.load(fsFor(project));
    _todos[projectId] = savedTodos;

    final agent = Agent(
      client: ai,
      provider: provider,
      taskId: checkpoint.taskId,
      roundLog: roundLog,
      fs: fsFor(project),
      shell: shellFor(project),
      deviceShell: systemShellFor(project),
      contextLimit: contextLimitFor(provider) ?? 128000,
      linuxShell: linux != null,
      activeFile: _activeFiles[projectId],
      skills: skills,
      mode: agentMode,
      onIntegrationQuery: (service, action, target, offset) =>
          _integrationStatus(project, service, action, target, offset: offset),
      onPause: (message) {
        pauseMessage = message;
        checkpoint = checkpoint.copyWith(
          pendingStep:
              'Continue the original request from the last completed step.',
          updatedAt: DateTime.now(),
        );
        _queueCheckpoint(checkpoint);
      },
      integrations: integrations,
      initialTodos: savedTodos,
      onTodosChanged: (next) => _setTodos(project, next),
      expectChanges: resumeFrom != null,
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
        final jobId = _activeAgentJobId;
        if (jobId != null) {
          _updateBackgroundJob(
            jobId,
            detail: 'Running ${call.name}',
            persist: false,
          );
        }
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
        // Committed text and tool rows are real transcript entries, so write
        // them during the run. Coalescing keeps a large thread from being
        // re-encoded on every single event.
        _queueChatPersist(projectId);
      },
    );

    final modelPrompt = stored.isEmpty
        ? prompt
        : '$prompt\n\nFiles the user attached (already inside the project):\n'
            '${stored.map((path) => '- $path').join('\n')}';

    try {
      await agent.run(
        history: history,
        prompt: modelPrompt,
        isCancelled: () => _cancelled,
      );
      if (!_cancelled) {
        if (pauseMessage.isEmpty) {
          checkpoint = checkpoint.copyWith(
            status: TaskCheckpointStatus.completed,
            pendingStep: '',
            updatedAt: DateTime.now(),
          );
        } else {
          checkpointError = pauseMessage;
        }
      }
    } on AiCancelledException {
      // Stop is not an error. The finally block keeps the streamed text.
    } on AiProviderException catch (error) {
      checkpointError = error.message;
      thread.add(_entry(role: ChatRole.error, text: error.message, ok: false));
    } catch (error) {
      if (!_cancelled) {
        checkpointError = '$error';
        thread.add(_entry(
          role: ChatRole.error,
          text: 'Unexpected error: $error',
          ok: false,
        ));
      }
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
      final finishedJobId = _activeAgentJobId;
      _activeAgentJobId = null;
      if (finishedJobId != null) {
        if (interrupted || _cancelled) {
          _finishBackgroundJob(
            finishedJobId,
            status: BackgroundJobStatus.interrupted,
            detail: _cancelled
                ? 'Stopped after ${formatDuration(elapsed)}. Resume is available.'
                : 'Paused after ${formatDuration(elapsed)}. Resume is available.',
          );
        } else {
          _finishBackgroundJob(
            finishedJobId,
            status: BackgroundJobStatus.completed,
            detail: 'Finished in ${formatDuration(elapsed)}',
          );
        }
      }
      busy = false;
      _activeProjectId = null;
      _chatPersistTimer?.cancel();
      _chatPersistTimer = null;
      _chatPersistProject = null;
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
    // Keep the opening request and its first answer even after a long
    // conversation. Dropping them made a later "continue" look like a new
    // task and discarded the original constraints.
    const maxTurns = 24;
    if (history.length <= maxTurns) return history;
    final firstUser = history.indexWhere((turn) => turn.role == 'user');
    if (firstUser < 0) return history.sublist(history.length - 16);
    final firstEnd =
        firstUser + 2 > history.length ? history.length : firstUser + 2;
    var tailStart = history.length - (maxTurns - firstEnd);
    if (tailStart < firstEnd) tailStart = firstEnd;
    return [...history.take(firstEnd), ...history.skip(tailStart)];
  }

  /// Builds a continuation brief from the visible transcript. It names the
  /// original request, the work already recorded, and the open checklist so a
  /// "continue" after a stop picks up instead of restarting the task.
  String? _continuePrompt(String projectId) {
    final thread = threadOf(projectId);
    final requests = thread
        .where((entry) =>
            entry.role == ChatRole.user && entry.text.trim().isNotEmpty)
        .toList();
    if (requests.isEmpty) return null;
    final replies = thread
        .where((entry) =>
            entry.role == ChatRole.assistant && entry.text.trim().isNotEmpty)
        .toList();
    final changed = <String>{};
    for (final entry in thread) {
      if (entry.role == ChatRole.tool &&
          entry.ok &&
          const {
            'write_file',
            'write_files',
            'edit_file',
            'apply_patch',
            'download_file',
          }.contains(entry.tool) &&
          entry.detail.trim().isNotEmpty) {
        changed.add(entry.detail.trim());
      }
    }
    final open = todosFor(projectId)
        .where((todo) => !todo.done)
        .map((todo) => '- ${todo.text}')
        .toList();
    final lastReply =
        replies.isEmpty ? '' : replies.last.text.trim().replaceAll('\n', ' ');
    return '''CONTINUE THE PREVIOUS TASK
Do not restart this task. The transcript above is the same task and the project already contains the work done so far.

Original request: ${requests.last.text.trim()}

Last assistant message: ${lastReply.isEmpty ? '(none)' : lastReply}

Files already changed in this task:
${changed.isEmpty ? '- None recorded.' : changed.take(12).map((path) => '- $path').join('\n')}

Open checklist steps:
${open.isEmpty ? '- None recorded. Continue from the last unfinished step.' : open.take(12).join('\n')}

Resume from the last unfinished step now. Re-read a file before editing it. Do not repeat a write or command that already succeeded, and do not begin the task again from the first step.'''
        .trim();
  }

  bool _looksLikeContinuePrompt(String raw) => RegExp(
        r'^\s*(?:please\s+)?(continue|resume|keep going|go on|carry on)\b',
        caseSensitive: false,
      ).hasMatch(raw.trim());

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

    // Show the provider error before the picker opens. Otherwise the picker
    // hides why the run stopped until it is dismissed.
    final reasonText = error.message.trim();
    _addNote(
      '${current.name}${current.keys.length > 1 ? ' (key ${current.keyIndex + 1})' : ''} '
      '${error.isLimit ? 'is rate-limited or out of credit' : 'returned an error'}'
      '${reasonText.isEmpty ? '.' : ': $reasonText'}',
    );

    if (current.hasMoreKeys) {
      var nextIndex = -1;
      for (var i = current.keyIndex + 1; i < current.keys.length; i++) {
        if (current.keys[i].trim().isNotEmpty) {
          nextIndex = i;
          break;
        }
      }
      if (nextIndex >= 0) {
        final reason = error.isLimit
            ? 'is rate-limited or out of credit'
            : 'returned an error';
        final allowed = autoNextKey ||
            await (limitPrompt?.call(
                  error.isLimit ? 'Key limit reached' : 'Key request failed',
                  '${current.name} (key ${current.keyIndex + 1}) $reason.\n\n'
                      '${error.message}\n\n'
                      'Use key ${nextIndex + 1} of ${current.keys.length}?',
                  'Use key ${nextIndex + 1}',
                ) ??
                Future.value(false));
        if (!allowed) return null;
        final next = current.copyWith(keyIndex: nextIndex);
        _replaceProvider(next);
        _clearLive();
        _addNote(
          '${current.name} (key ${current.keyIndex + 1}) ${error.isLimit ? 'reached its limit' : 'failed'}. Using key ${nextIndex + 1}.',
        );
        await _persistProviders();
        notifyListeners();
        return next;
      }
    }

    final candidates = configuredProviders
        .where((provider) => provider.id != current.id)
        .toList();
    if (candidates.isEmpty) return null;

    ProviderChoice? choice;
    if (autoNextProvider) {
      final provider = candidates.first;
      choice = ProviderChoice(provider, provider.model);
    } else {
      choice =
          await providerChoicePrompt?.call(current, candidates, reasonText);
    }
    if (choice == null) return null;

    // The picker chooses one provider and model for this task. Keep every
    // other provider exactly as it was, and only change the active model when
    // the user picked a different one.
    var next = choice.provider;
    if (choice.model.trim().isNotEmpty && choice.model != next.model) {
      next = next.copyWith(model: choice.model);
      _replaceProvider(next);
      await _persistProviders();
    }
    activeProviderId = next.id;
    _clearLive();
    _addNote(
      '${current.name}${current.keys.length > 1 ? ' (all keys)' : ''} could not complete the request. Switched to ${next.name} (${next.model}).',
    );
    await store.write(_kActiveProvider, next.id);
    notifyListeners();
    return next;
  }

  TaskCheckpoint? checkpointFor(String projectId) => _checkpoints[projectId];

  bool hasResumableCheckpoint(String projectId) =>
      _checkpoints[projectId]?.resumable ?? false;

  Future<void> resumeTask(String projectId) async {
    if (busy) return;
    final checkpoint = _checkpoints[projectId];
    if (checkpoint == null || !checkpoint.resumable) return;
    final project = projectById(projectId);
    final provider = activeProvider;
    final skip =
        checkpoint.completedActions.map((action) => action.fingerprint).toSet();
    final thread = threadOf(projectId);
    thread.add(_entry(
      role: ChatRole.note,
      text: 'Resumed with ${provider.name} (${provider.model}). '
          '${checkpoint.completed.isEmpty ? 'No completed steps.' : 'Completed ${checkpoint.completed.length} steps; '}'
          '${checkpoint.changedFiles.length} changed files.',
    ));
    _queueCheckpoint(checkpoint.copyWith(
      status: TaskCheckpointStatus.running,
      updatedAt: DateTime.now(),
    ));
    notifyListeners();
    unawaited(_persistChat(projectId));
    // Hashing changed files used to delay Resume itself. Run that check while
    // the task is already starting and report it as a note.
    unawaited(_reportExternalChanges(project, checkpoint));
    await _runPrompt(
      projectId,
      _resumeSummary(checkpoint, const []),
      historyOverride: _historyFor(thread),
      skipActionFingerprints: skip,
      resumeFrom: checkpoint,
      recordUserMessage: false,
    );
  }

  Future<void> _reportExternalChanges(
    Project project,
    TaskCheckpoint checkpoint,
  ) async {
    try {
      final external = await _externalChanges(project, checkpoint);
      if (external.isEmpty || !projects.any((item) => item.id == project.id)) {
        return;
      }
      threadOf(project.id).add(_entry(
        role: ChatRole.note,
        text: '${external.length} file(s) changed outside the task.',
      ));
      notifyListeners();
    } catch (_) {
      // This note is informational; it must not affect the resumed task.
    }
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

Continue seamlessly from the remaining step. Do not restart the task from the beginning and do not repeat a write or destructive action that already completed. Use the current files on disk, not assumptions from before the interruption.'''
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
    final catalogue = await ai.listModelCatalogue(provider);
    final index = providers.indexWhere((item) => item.id == provider.id);
    if (index >= 0) {
      providers[index] = providers[index].copyWith(
        models: catalogue.ids,
        contextLengths: catalogue.contexts,
      );
      await _persistProviders();
      notifyListeners();
    }
    return catalogue.ids;
  }

  /// Refreshes context windows in the background. Called when the model sheet
  /// opens so an already-saved model also gets its provider-reported size.
  Future<void> refreshModelContexts(ProviderConfig provider) async {
    if (!provider.ready) return;
    try {
      final catalogue = await ai.listModelCatalogue(provider);
      final index = providers.indexWhere((item) => item.id == provider.id);
      if (index < 0) return;
      providers[index] = providers[index].copyWith(
        models: catalogue.ids,
        contextLengths: catalogue.contexts,
      );
      await _persistProviders();
      notifyListeners();
    } catch (_) {
      // The fallback table still gives a usable estimate offline.
    }
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
      IntegrationKind.expo => await _verifyExpoToken(trimmed),
      IntegrationKind.tavily => await _verifyTavilyToken(trimmed),
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
    // Store the account's display name, not the raw 32-character id. If the
    // token cannot read account details, the integration still shows a human
    // label and keeps the id as secondary metadata.
    final name = await CloudflarePagesClient(
      token,
      accountId: accountId,
      client: httpClient,
    ).accountName();
    return name.trim().isEmpty ? 'Cloudflare' : name.trim();
  }

  /// Tavily's usage endpoint validates the key without spending search
  /// credits. It returns real account usage when the key is valid.
  Future<String> _verifyTavilyToken(String token) async {
    final response = await httpClient.get(
      Uri.parse('https://api.tavily.com/usage'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    ).timeout(const Duration(seconds: 25));
    if (response.statusCode == 401 ||
        response.statusCode == 403 ||
        response.statusCode == 422) {
      throw IntegrationException('Tavily rejected that API key.');
    }
    if (response.statusCode != 200) {
      throw IntegrationException(
          'Tavily returned HTTP ${response.statusCode} while checking the key.');
    }
    final body = jsonDecode(response.body);
    final plan = body is Map ? body['account'] : null;
    final planName = plan is Map ? '${plan['current_plan'] ?? ''}'.trim() : '';
    return planName.isEmpty ? 'Tavily' : 'Tavily · $planName';
  }

  /// Expo has no public versioned REST auth endpoint; its own EAS CLI uses the
  /// GraphQL `meActor` query with a bearer token. A robot token may expose a
  /// firstName instead of a username, so both are accepted.
  Future<String> _verifyExpoToken(String token) async {
    const query = '''
query CurrentUser {
  meActor {
    __typename
    id
    ... on UserActor { username }
    ... on Robot { firstName }
    ... on PartnerActor { username }
  }
}
''';
    final response = await httpClient
        .post(
          Uri.parse('https://api.expo.dev/graphql'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({'query': query}),
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw IntegrationException('Expo rejected that access token.');
    }
    if (response.statusCode != 200) {
      throw IntegrationException(
          'Expo returned HTTP ${response.statusCode} while checking the token.');
    }
    final body = jsonDecode(response.body);
    if (body is! Map || body['errors'] is List) {
      throw IntegrationException(
          'Expo rejected that access token or returned no account.');
    }
    final data = body['data'];
    final actor = data is Map ? data['meActor'] : null;
    if (actor is! Map) {
      throw IntegrationException(
          'Expo returned no account for that access token.');
    }
    final name = ('${actor['username'] ?? actor['firstName'] ?? ''}').trim();
    return name.isEmpty ? 'Expo' : name;
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
    return count == 0 ? 'Supabase' : 'Supabase · $count projects';
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

  Future<String?> githubDefaultBranch(
    IntegrationAccount account,
    String owner,
    String repo,
  ) =>
      GitHubClient(account.token, client: httpClient)
          .defaultBranch(owner, repo);

  Future<String?> githubFileText(
    IntegrationAccount account, {
    required String owner,
    required String repo,
    required String branch,
    required String path,
  }) =>
      GitHubClient(account.token, client: httpClient)
          .fileText(owner, repo, path, branch);

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
    bool force = false,
  }) async {
    final current = await pushStateFor(project);
    final sameTarget = current.owner == owner &&
        current.repo == repo &&
        current.branch == branch;
    if (sameTarget && current.synced && !force) return current;
    final client = GitHubClient(account.token, client: httpClient);
    final tree = await client.tree(owner, repo, branch);
    final local = await fsFor(project).localSnapshot();
    // Keep the previous merge base when the target is unchanged. A remote edit
    // changes `hashes`, not the files on this device, so the base is what
    // separates "changed here" from "changed on GitHub".
    final base = sameTarget
        ? (current.baseHashes.isEmpty ? current.hashes : current.baseHashes)
        : const <String, String>{};
    final baseline = <String, String>{};
    final needed = <GitHubTreeFile>[];
    for (final file in tree.textFiles) {
      final remoteHash = tree.hashes[file.path];
      final localHash = local.hashes[file.path];
      final baseHash = base[file.path];
      if (localHash == null ||
          localHash == baseHash ||
          localHash == remoteHash) {
        continue;
      }
      // Only a file that differs locally needs its old text for a diff. Every
      // unchanged file is dropped from the stored baseline, which keeps
      // push.json small and branch switches fast.
      final cached = current.baseline[file.path];
      if (cached != null &&
          ((baseHash != null && gitBlobSha(utf8.encode(cached)) == baseHash) ||
              current.hashes[file.path] == remoteHash)) {
        baseline[file.path] = cached;
      } else if (baseHash == null || remoteHash == baseHash) {
        // Unchanged remotely since the merge base, so the remote text is the
        // text this device started from.
        needed.add(file);
      }
    }
    baseline.addAll(await client.textFiles(owner, repo, needed));
    final next = current.copyWith(
      owner: owner,
      repo: repo,
      branch: branch,
      baseline: baseline,
      hashes: tree.hashes,
      baseHashes: base,
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

  Future<List<RepoChange>> changesFor(
    Project project, {
    Future<String?> Function(String path)? beforeText,
  }) async {
    final state = await pushStateFor(project);
    final current = await fsFor(project).localSnapshot();
    final gitignore = await GitIgnoreSet.load(fsFor(project));
    // Compare against what this device last synced, not against the current
    // remote tree. Otherwise a file edited only on GitHub looks like a local
    // edit and the pull refuses to replace it.
    final base = state.comparisonBase;
    final paths = <String>{
      ...base.keys,
      ...state.hashes.keys,
      ...current.hashes.keys,
    }.toList()
      ..sort();
    final changes = <RepoChange>[];
    for (final path in paths) {
      final localHash = current.hashes[path];
      final baseHash = base[path];
      final remoteHash = state.hashes[path];
      final isNew = baseHash == null && remoteHash == null;
      // Ignore rules only hide untracked files. A file that is already on the
      // remote branch stays visible and editable even when it matches a rule.
      if (isNew && gitignore.ignores(path)) continue;
      if (localHash == null) {
        // A file removed from this device is a change too. Without a merge
        // base it was never synced here, so it is not a local deletion.
        if (baseHash == null) continue;
        var before = state.baseline[path];
        if (before != null && gitBlobSha(utf8.encode(before)) != baseHash) {
          before = null;
        }
        if (before == null && remoteHash == baseHash && beforeText != null) {
          try {
            before = await beforeText(path);
          } catch (_) {
            // The deletion is still real without a diff preview.
          }
        }
        final diff = before == null ? null : computeDiff(before, '');
        changes.add(RepoChange(
          path: path,
          status: RepoChangeStatus.deleted,
          before: before ?? '',
          after: '',
          added: 0,
          removed: diff?.removed ?? 0,
          isBinary: before == null,
        ));
        continue;
      }
      if (localHash == baseHash) continue;
      var before = state.baseline[path];
      if (before != null &&
          baseHash != null &&
          gitBlobSha(utf8.encode(before)) != baseHash) {
        // The cached text no longer matches the merge base, so it cannot
        // describe what changed here.
        before = null;
      }
      if (before == null &&
          baseHash != null &&
          remoteHash == baseHash &&
          beforeText != null) {
        try {
          before = await beforeText(path);
        } catch (_) {
          // A missing preview must not hide a real local change.
        }
      }
      final after = current.texts[path];
      final isBinary = after == null;
      final canDiff = !isBinary && (before != null || isNew);
      final diff = canDiff ? computeDiff(before ?? '', after) : null;
      changes.add(RepoChange(
        path: path,
        status: baseHash == null && remoteHash == null
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
    Set<String> deleted = const {},
    String? parentSha,
  }) =>
      GitHubClient(account.token, client: httpClient).createCommit(
        owner: owner,
        repo: repo,
        branch: branch,
        message: message,
        files: files,
        deleted: deleted,
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
    // The merge base is what this device last synced. Using the freshly
    // fetched remote tree here made every remote-only edit look local, so the
    // pull kept the stale file instead of updating it.
    final mergeBase = state.comparisonBase;
    String? baseHash(String path) {
      final known = mergeBase[path];
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
        if (base == null) {
          writes[path] = cloned.files[path]!;
        } else if (remoteHash != base) {
          // Deleted locally, but GitHub also changed the file. Keeping either
          // side would silently lose the other, so stop and report it.
          conflicts.add(path);
        } else {
          // Deleted on this device since the last sync. Keep that deletion; a
          // pull must not bring a file the user removed back to life.
          keptLocal++;
        }
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
      baseHashes: remoteHashes,
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
    final deleted = <String>{};
    for (final change in changes) {
      if (change.status == RepoChangeStatus.deleted) {
        deleted.add(change.path);
        continue;
      }
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
      deleted: deleted,
      parentSha: parent?.sha,
    );
    final baseHashes = {...state.comparisonBase, ...hashes};
    final remoteHashes = {...state.hashes, ...hashes};
    for (final path in deleted) {
      baseHashes.remove(path);
      remoteHashes.remove(path);
    }
    var next = state
        .copyWith(
          owner: owner,
          repo: repo,
          branch: branch,
          // Start from the full merge base: storing only the committed paths
          // would make every other remote file look edited.
          baseHashes: baseHashes,
          hashes: remoteHashes,
        )
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
          deleted: deleted.toList(growable: false),
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
    void Function(DeployProgress)? onProgress,
  }) async {
    onProgress?.call(
        const DeployProgress('Preparing', detail: 'Collecting project files'));
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
      onProgress: onProgress,
    );
    await _rememberDeployment(project, 'vercel', target, signature);
    return _secureDeployResult(
      project,
      result.copyWith(runtime: 'Vercel'),
    );
  }

  String _boundedLog(String text) =>
      text.length > 40000 ? text.substring(text.length - 40000) : text;

  Future<String> _fetchPagesLogs(
    CloudflarePagesClient pages,
    String projectName,
    String deploymentId,
    Iterable<ProjectEnvEntry> entries, {
    int maxChars = 40000,
  }) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final logs = await pages.deploymentLogs(
          project: projectName,
          deploymentId: deploymentId,
          secrets: entries,
          maxChars: maxChars,
        );
        if (logs.trim().isNotEmpty) return logs;
      } catch (_) {
        // A delayed or unavailable log must not turn a deploy into a failure.
      }
      if (attempt < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 900));
      }
    }
    return '';
  }

  Future<IntegrationResult> _secureDeployResult(
    Project project,
    IntegrationResult result, {
    bool success = true,
  }) async {
    final entries = await environmentFor(project);
    final secured = result.copyWith(
      logs: maskSecretLog(result.logs ?? '', entries),
    );
    try {
      await DeployLogStore.save(
        fsFor(project),
        LastDeployLog(
          runtime: secured.runtime ?? 'Deploy',
          message: secured.message,
          logs: secured.logs ?? '',
          at: DateTime.now(),
          url: secured.url ?? '',
          deploymentId: secured.deploymentId ?? '',
          success: success,
        ),
      );
    } catch (_) {
      // A log write must not turn a successful deploy into a failure.
    }
    return secured;
  }

  Future<LastDeployLog?> lastDeployLogFor(Project project) async {
    final record = await DeployLogStore.load(fsFor(project));
    if (record == null) return null;
    final entries = await environmentFor(project);
    return record.copyWith(logs: maskSecretLog(record.logs, entries));
  }

  Future<LastDeployLog> rememberDeployFailure(
    Project project, {
    required String runtime,
    required String message,
    required String logs,
    String deploymentId = '',
  }) async {
    final entries = await environmentFor(project);
    final record = LastDeployLog(
      runtime: runtime,
      message: message,
      logs: maskSecretLog(logs, entries),
      at: DateTime.now(),
      deploymentId: deploymentId,
      success: false,
    );
    try {
      await DeployLogStore.save(fsFor(project), record);
    } catch (_) {
      // The failure card can still show the masked log for this session.
    }
    return record;
  }

  Future<LastDeployLog?> refreshCloudflareDeploymentLogs(
    Project project, {
    required String projectName,
    required String deploymentId,
  }) async {
    final account = integrations.activeFor(IntegrationKind.cloudflare);
    if (account == null) {
      throw IntegrationException('Cloudflare is not connected.');
    }
    final pages = CloudflarePagesClient(
      account.token,
      accountId: account.accountId,
      client: httpClient,
    );
    final entries = await environmentFor(project);
    final logs = await _fetchPagesLogs(
      pages,
      projectName,
      deploymentId,
      entries,
    );
    final masked = maskSecretLog(logs, entries);
    final existing = await DeployLogStore.load(fsFor(project));
    final record = (existing ??
            LastDeployLog(
              runtime: 'Cloudflare Pages',
              message: 'Cloudflare Pages deployment',
              logs: '',
              at: DateTime.now(),
              deploymentId: deploymentId,
            ))
        .copyWith(logs: masked, deploymentId: deploymentId);
    try {
      await DeployLogStore.save(fsFor(project), record);
    } catch (_) {
      // The refreshed log is still returned to the caller for display.
    }
    return record;
  }

  DeployJob? deployJobFor(String projectId) => _deployJobs[projectId];

  void clearDeployJob(String projectId) {
    if (_deployJobs.remove(projectId) == null) return;
    notifyListeners();
  }

  /// Starts a deploy that outlives the sheet that launched it. Progress and
  /// the final result stay in AppState, so reopening the deploy page can pick
  /// the job back up.
  Future<void> startDeploy(
    String projectId,
    DeployJob job,
    Future<IntegrationResult> Function(
      void Function(DeployProgress) onProgress,
    ) run,
  ) async {
    final project = projectById(projectId);
    final record = _startBackgroundJob(
      project: project,
      kind: BackgroundJobKind.deploy,
      title: 'Deploy · ${_platformLabel(job.platform)}',
      detail: 'Preparing ${job.runtime}',
      data: {'platform': job.platform.name, 'runtime': job.runtime},
    );
    job.jobId = record.id;
    _deployJobs[projectId] = job;
    notifyListeners();
    try {
      final result = await run((progress) {
        job.progress = progress;
        if (job.jobId.isNotEmpty) {
          _updateBackgroundJob(
            job.jobId,
            detail: progress.detail.isEmpty
                ? progress.stage
                : '${progress.stage} · ${progress.detail}',
            persist: false,
          );
        }
        notifyListeners();
      });
      job.result = result;
      job.running = false;
      try {
        job.lastDeploy = await lastDeployLogFor(projectById(projectId));
      } catch (_) {
        // The result itself is still enough to show a successful deploy.
      }
      if (job.jobId.isNotEmpty) {
        _finishBackgroundJob(
          job.jobId,
          status: BackgroundJobStatus.completed,
          detail:
              result.message.isEmpty ? 'Deployment finished' : result.message,
        );
      }
      notifyListeners();
    } on IntegrationException catch (error) {
      job.error = error.message;
      job.failureRuntime = error.runtime ?? job.runtime;
      final logs = error.logs ?? '';
      final deploymentId = error.deploymentId ?? '';
      if (logs.trim().isNotEmpty || deploymentId.isNotEmpty) {
        try {
          job.lastDeploy = await rememberDeployFailure(
            projectById(projectId),
            runtime: job.failureRuntime ?? job.runtime,
            message: error.message,
            logs: logs,
            deploymentId: deploymentId,
          );
          job.failureLogs = job.lastDeploy?.logs ?? logs;
        } catch (_) {
          job.failureLogs = logs;
        }
      }
      job.running = false;
      if (job.jobId.isNotEmpty) {
        _finishBackgroundJob(
          job.jobId,
          status: BackgroundJobStatus.failed,
          detail: 'Deployment failed: ${error.message}',
        );
      }
      notifyListeners();
    } catch (error) {
      job.error = '$error';
      job.running = false;
      if (job.jobId.isNotEmpty) {
        _finishBackgroundJob(
          job.jobId,
          status: BackgroundJobStatus.failed,
          detail: 'Deployment failed: $error',
        );
      }
      notifyListeners();
    }
  }

  Future<IntegrationResult> deployToCloudflare(
    Project project,
    IntegrationAccount account, {
    required String projectName,
    String projectUrl = '',
    String environment = 'production',
    String branch = 'main',
    void Function(DeployProgress)? onProgress,
  }) async {
    final fs = fsFor(project);
    final plan = await planCloudflareDeploy(fs);
    if (plan.usesWorkers) {
      throw IntegrationException(
        cloudflareWorkersUnavailable,
        runtime: 'Cloudflare Workers',
      );
    }
    onProgress?.call(
        const DeployProgress('Preparing', detail: 'Collecting project files'));
    final files = await _cloudflareFiles(project, onProgress);
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
    final pages = CloudflarePagesClient(
      account.token,
      accountId: account.accountId,
      client: httpClient,
    );
    IntegrationResult result;
    try {
      result = await pages.deploy(
        project: projectName,
        projectUrl: projectUrl,
        files: files,
        environment: environment,
        branch: branch,
        onProgress: onProgress,
      );
    } on IntegrationException catch (error) {
      final failedDeploymentId = error.deploymentId ?? '';
      if (failedDeploymentId.isNotEmpty && (error.logs ?? '').trim().isEmpty) {
        // A failed build can publish its logs a moment after the deployment
        // status flips to failure. Retry before giving up on the real output.
        final entries = await environmentFor(project);
        final logs = await _fetchPagesLogs(
          pages,
          projectName,
          failedDeploymentId,
          entries,
        );
        if (logs.trim().isNotEmpty) {
          throw IntegrationException(
            error.message,
            logs: maskSecretLog(logs, entries),
            runtime: error.runtime,
            deploymentId: failedDeploymentId,
          );
        }
      }
      rethrow;
    }
    var logs = result.logs;
    final deploymentId = result.deploymentId ?? '';
    if (deploymentId.isNotEmpty) {
      final entries = await environmentFor(project);
      logs = await _fetchPagesLogs(
        pages,
        projectName,
        deploymentId,
        entries,
      );
    }
    await _rememberDeployment(
      project,
      'cloudflare',
      target,
      signature,
    );
    return _secureDeployResult(project, result.copyWith(logs: logs));
  }

  /// Used by tests to exercise the exact callback the agent receives.
  @visibleForTesting
  Future<String> integrationStatusForAgent(
    Project project,
    String service,
    String action,
    String target, {
    int offset = -1,
  }) =>
      _integrationStatus(project, service, action, target, offset: offset);

  /// Returns a readable slice of a long log without hiding the rest. With no
  /// offset the failure end is returned because builds fail at the end; an
  /// explicit offset can page through the entire masked log.
  String _logSlice(String masked, int offset, {int maxChars = 24000}) {
    final total = masked.length;
    if (total == 0) return '';
    var start = offset;
    if (start < 0) start = total > maxChars ? total - maxChars : 0;
    if (start > total) start = total;
    var end = start + maxChars;
    if (end > total) end = total;
    final buffer = StringBuffer();
    if (start > 0 || end < total) {
      buffer.write('[log characters $start-$end of $total]');
      if (start > 0) {
        buffer.write(' Earlier log: call with offset 0.');
      }
      buffer.writeln();
    }
    buffer.write(masked.substring(start, end));
    if (end < total) {
      buffer.write('\n[log continues at offset $end]');
    }
    return buffer.toString();
  }

  /// Reads deployment and workflow data from connected accounts for the
  /// agent. Credentials never appear in the returned text.
  Future<String> _integrationStatus(
    Project project,
    String service,
    String action,
    String target, {
    int offset = -1,
  }) async {
    try {
      switch (service) {
        case 'github':
          final account = activeGithub;
          if (account == null) {
            return 'GitHub is not connected. Ask the user to connect it in '
                'Integrations.';
          }
          final resolved = _githubRunTarget(target, project.repo);
          final repo = resolved.$1;
          final jobSelector = resolved.$3.trim();
          if (repo.isEmpty) {
            return 'No GitHub repository is linked to this project. Pass '
                'owner/repo or open the repository first.';
          }
          final headers = {
            'Authorization': 'Bearer ${account.token}',
            'Accept': 'application/vnd.github+json',
          };
          if (action == 'logs') {
            var runId = resolved.$2;
            if (runId.isEmpty) {
              // The agent should not need a run id from the user. Resolve the
              // latest run for the project repository and use its jobs.
              final latest = await httpClient.get(
                Uri.parse('https://api.github.com/repos/$repo/actions/runs'
                    '?per_page=1'),
                headers: headers,
              );
              if (latest.statusCode != 200) {
                return 'GitHub returned ${latest.statusCode} while looking '
                    'for the latest workflow run in $repo.';
              }
              final latestBody = jsonDecode(latest.body);
              final runs =
                  latestBody is Map ? latestBody['workflow_runs'] : null;
              if (runs is! List || runs.isEmpty) {
                return 'No workflow runs found for $repo. Start a workflow or '
                    'pass an Actions run URL as target.';
              }
              final first = runs.whereType<Map>().isEmpty
                  ? null
                  : runs.whereType<Map>().first;
              runId = '${first?['id'] ?? ''}'.trim();
              if (runId.isEmpty) {
                return 'GitHub returned a workflow run without an id for '
                    '$repo.';
              }
            }
            final jobsResponse = await httpClient.get(
              Uri.parse(
                  'https://api.github.com/repos/$repo/actions/runs/$runId/jobs'
                  '?per_page=100'),
              headers: headers,
            );
            if (jobsResponse.statusCode == 404) {
              return 'No workflow run $runId exists in $repo. Pass a run id or '
                  'a full github.com Actions run URL.';
            }
            if (jobsResponse.statusCode != 200) {
              return 'GitHub returned ${jobsResponse.statusCode} for run '
                  '$runId in $repo.';
            }
            final decoded = jsonDecode(jobsResponse.body);
            final rawJobs = decoded is Map ? decoded['jobs'] : null;
            final jobs =
                rawJobs is List ? rawJobs.whereType<Map>().toList() : <Map>[];
            if (jobs.isEmpty) {
              return 'No jobs for run $runId in $repo yet.';
            }
            final summary = jobs.map((job) {
              final steps = job['steps'];
              final failed = steps is List
                  ? steps
                      .whereType<Map>()
                      .where((step) =>
                          step['conclusion'] == 'failure' ||
                          step['conclusion'] == 'timed_out')
                      .map((step) => step['name'])
                      .join(', ')
                  : '';
              return '- ${job['name']} (job ${job['id']}) '
                  '[${job['status']}/${job['conclusion']}]'
                  '${failed.isEmpty ? '' : ' failed: $failed'}';
            }).join('\n');

            // A job selector can name any job by id or name. Without one, the
            // failing jobs are the useful default; when no job failed (a
            // queued or successful run), fetch the first job so the agent
            // still sees real output instead of only names.
            List<Map> logJobs;
            if (jobSelector.isNotEmpty) {
              final wanted = jobSelector.toLowerCase();
              bool exact(Map job) {
                final id = '${job['id'] ?? ''}'.trim();
                final name = '${job['name'] ?? ''}'.trim().toLowerCase();
                return id == jobSelector || name == wanted;
              }

              // Prefer an id or a full name. Only fall back to a partial name
              // when the caller gave a distinctive fragment.
              final exactMatches = jobs.where(exact).toList();
              final matched = exactMatches.isNotEmpty
                  ? exactMatches
                  : jobs.where((job) {
                      final name = '${job['name'] ?? ''}'.trim().toLowerCase();
                      return name.contains(wanted);
                    }).toList();
              if (matched.isEmpty) {
                return 'GitHub Actions run $runId in $repo:\n$summary\n\n'
                    'No job matched "$jobSelector". Pass a job id or name from '
                    'the list above, or a URL ending in '
                    '.../actions/runs/$runId/job/<job-id>.';
              }
              logJobs = matched;
            } else {
              logJobs = jobs
                  .where((job) =>
                      job['conclusion'] == 'failure' ||
                      job['conclusion'] == 'timed_out')
                  .toList();
              if (logJobs.isEmpty) logJobs = jobs.take(1).toList();
            }
            final entries = await environmentFor(project);
            final logs = StringBuffer();
            for (final job in jobSelector.isEmpty ? logJobs.take(2) : logJobs) {
              final jobId = '${job['id'] ?? ''}'.trim();
              if (jobId.isEmpty) continue;
              final logResponse = await httpClient.get(
                Uri.parse(
                    'https://api.github.com/repos/$repo/actions/jobs/$jobId/logs'),
                headers: headers,
              );
              final rawLog = logResponse.body;
              if (logResponse.statusCode == 200 && rawLog.trim().isNotEmpty) {
                // Keep the whole masked log available so an offset slice can
                // reach the beginning as well as the failure at the end.
                final masked = maskSecretLog(rawLog, entries, maxChars: 0);
                logs.write('\n\nLogs for ${job['name']} (job $jobId, '
                    '${masked.length} characters):\n'
                    '${_logSlice(masked, offset, maxChars: 16000)}');
              } else if (logResponse.statusCode == 200) {
                logs.write('\n\nLogs for ${job['name']} are empty. The job may '
                    'still be running.');
              } else if (logResponse.statusCode == 404 ||
                  logResponse.statusCode == 410) {
                logs.write('\n\nLogs for ${job['name']} are not available '
                    '(HTTP ${logResponse.statusCode}). GitHub keeps job logs '
                    'for a limited time; the run may be old or private.');
              } else {
                logs.write('\n\nLogs for ${job['name']} returned HTTP '
                    '${logResponse.statusCode}. Check that the GitHub token '
                    'still has Actions read access.');
              }
            }
            return 'GitHub Actions run $runId in $repo:\n$summary'
                '${logs.isEmpty ? '\n\nNo job logs were available yet. The run may still be queued.' : logs}'
                '\n\nTo read another job from this run, pass target '
                '"$runId/job/<job-id>" or "$runId/job/<job-name>".';
          }
          final response = await httpClient.get(
            Uri.parse(
                'https://api.github.com/repos/$repo/actions/runs?per_page=8'),
            headers: headers,
          );
          if (response.statusCode != 200) {
            return 'GitHub returned ${response.statusCode} for $repo.';
          }
          final decoded = jsonDecode(response.body);
          final runs = decoded is Map ? decoded['workflow_runs'] : null;
          if (runs is! List || runs.isEmpty) {
            return 'No workflow runs found for $repo.';
          }
          return 'GitHub Actions for $repo:\n${runs.whereType<Map>().take(8).map((run) => '- #${run['id']} ${run['name']} '
              '[${run['status']}/${run['conclusion']}] '
              'branch ${run['head_branch']} ${run['html_url'] ?? ''}').join('\n')}';
        case 'cloudflare':
          final account = integrations.activeFor(IntegrationKind.cloudflare);
          if (account == null) {
            return 'Cloudflare is not connected. Ask the user to connect it in '
                'Integrations.';
          }
          final accountId = account.accountId.trim();
          if (accountId.isEmpty) {
            return 'The Cloudflare account has no account id configured.';
          }
          final headers = {
            'Authorization': 'Bearer ${account.token}',
            'Content-Type': 'application/json',
          };
          if (action == 'logs') {
            final parts = target.split('/');
            final projectName = parts.first.trim();
            if (projectName.isEmpty) {
              return 'Pass a Pages project name, optionally followed by a '
                  'deployment id: project/deployment-id.';
            }
            final client = CloudflarePagesClient(
              account.token,
              accountId: accountId,
              client: httpClient,
            );
            var deploymentId = parts.length > 1 ? parts[1].trim() : '';
            if (deploymentId.isEmpty) {
              deploymentId = await client.latestDeploymentId(projectName);
            }
            if (deploymentId.isEmpty) {
              return 'No deployment was found for $projectName.';
            }
            final entries = await environmentFor(project);
            final logs = await client.deploymentLogs(
              project: projectName,
              deploymentId: deploymentId,
              secrets: entries,
              maxChars: 0,
            );
            if (logs.trim().isEmpty) {
              return 'Cloudflare returned no build log for $projectName/'
                  '$deploymentId yet.';
            }
            // The client already masked the entire log. Slice after masking
            // so no secret is ever split by a character cutoff.
            final excerpt = _logSlice(logs, offset, maxChars: 24000);
            return 'Cloudflare Pages build logs for $projectName/$deploymentId:'
                '\n$excerpt';
          }
          if (action == 'deployments' && target.isNotEmpty) {
            final response = await httpClient.get(
              Uri.parse(
                  'https://api.cloudflare.com/client/v4/accounts/$accountId/pages/projects/${Uri.encodeComponent(target)}/deployments?per_page=8'),
              headers: headers,
            );
            if (response.statusCode != 200) {
              return 'Cloudflare returned ${response.statusCode} for $target.';
            }
            final decoded = jsonDecode(response.body);
            final deployments = decoded is Map ? decoded['result'] : null;
            if (deployments is! List || deployments.isEmpty) {
              return 'No deployments found for $target.';
            }
            return 'Cloudflare deployments for $target:\n${deployments.whereType<Map>().take(8).map((item) {
              final stage = item['latest_stage'];
              final stageText = stage is Map
                  ? '${stage['name']}/${stage['status']}'
                  : '${item['environment'] ?? ''}';
              return '- ${item['created_on'] ?? ''} $stageText '
                  '${item['url'] ?? ''}';
            }).join('\n')}';
          }
          final response = await httpClient.get(
            Uri.parse(
                'https://api.cloudflare.com/client/v4/accounts/$accountId/pages/projects?per_page=10'),
            headers: headers,
          );
          if (response.statusCode != 200) {
            return 'Cloudflare returned ${response.statusCode}.';
          }
          final decoded = jsonDecode(response.body);
          final projects = decoded is Map ? decoded['result'] : null;
          if (projects is! List || projects.isEmpty) {
            return 'No Cloudflare Pages projects found.';
          }
          return 'Cloudflare Pages projects:\n${projects.whereType<Map>().map((item) => '- ${item['name']} '
              '(${item['subdomain'] ?? item['domains'] ?? ''})').join('\n')}';
        case 'vercel':
          final account = activeVercel;
          if (account == null) {
            return 'Vercel is not connected. Ask the user to connect it in '
                'Integrations.';
          }
          final headers = {'Authorization': 'Bearer ${account.token}'};
          if (action == 'logs') {
            var deploymentId = target.trim();
            if (deploymentId.isEmpty) {
              final latest = await httpClient.get(
                Uri.parse('https://api.vercel.com/v6/deployments?limit=1'),
                headers: headers,
              );
              if (latest.statusCode != 200) {
                return 'Vercel returned ${latest.statusCode} while looking '
                    'for the latest deployment.';
              }
              final latestBody = jsonDecode(latest.body);
              final deployments =
                  latestBody is Map ? latestBody['deployments'] : null;
              if (deployments is! List || deployments.isEmpty) {
                return 'No Vercel deployments were found. Pass a deployment '
                    'id or URL as target.';
              }
              final first = deployments.whereType<Map>().isEmpty
                  ? null
                  : deployments.whereType<Map>().first;
              deploymentId = '${first?['id'] ?? ''}'.trim();
            }
            if (deploymentId.isEmpty) {
              return 'No Vercel deployment id was found. Pass one as target.';
            }
            final response = await httpClient.get(
              Uri.parse('https://api.vercel.com/v3/deployments/'
                  '${Uri.encodeComponent(deploymentId)}/events'
                  '?direction=forward&limit=-1&builds=1'),
              headers: headers,
            );
            if (response.statusCode == 401 || response.statusCode == 403) {
              return 'Vercel rejected the saved access token. Ask the user to '
                  'reconnect it in Integrations.';
            }
            if (response.statusCode != 200) {
              return 'Vercel returned ${response.statusCode} for deployment '
                  '$deploymentId.';
            }
            final decoded = jsonDecode(response.body);
            final events =
                decoded is List ? decoded.whereType<Map>().toList() : <Map>[];
            if (events.isEmpty) {
              return 'Vercel returned no build events for $deploymentId yet.';
            }
            final lines = <String>[];
            for (final event in events) {
              final payload = event['payload'];
              final text = payload is Map
                  ? '${payload['text'] ?? ''}'.trimRight()
                  : '${event['text'] ?? ''}'.trimRight();
              if (text.trim().isNotEmpty) lines.add(text);
            }
            final entries = await environmentFor(project);
            final masked =
                maskSecretLog(lines.join('\n'), entries, maxChars: 0);
            if (masked.trim().isEmpty) {
              return 'Vercel returned no readable build output for '
                  '$deploymentId yet.';
            }
            return 'Vercel build logs for $deploymentId:\n'
                '${_logSlice(masked, offset, maxChars: 24000)}';
          }
          final response = await httpClient.get(
            Uri.parse(
                'https://api.vercel.com/v6/deployments?limit=8${target.isEmpty ? '' : '&projectId=${Uri.encodeQueryComponent(target)}'}'),
            headers: headers,
          );
          if (response.statusCode != 200) {
            return 'Vercel returned ${response.statusCode}.';
          }
          final decoded = jsonDecode(response.body);
          final deployments = decoded is Map ? decoded['deployments'] : null;
          if (deployments is! List || deployments.isEmpty) {
            return 'No Vercel deployments found.';
          }
          return 'Vercel deployments:\n${deployments.whereType<Map>().take(8).map((item) => '- ${item['name']} [${item['state']}] '
              'https://${item['url']}').join('\n')}';
        case 'tavily':
          return _tavilyStatus(target);
        case 'supabase':
          return _supabaseStatus(target);
        case 'expo':
          return action == 'builds'
              ? _expoBuildsStatus(project, target)
              : _expoProjectsStatus();
        default:
          return 'Unknown integration service: $service.';
      }
    } catch (error) {
      return 'Integration request failed: $error';
    }
  }

  Future<String> _tavilyStatus(String rawQuery) async {
    final account = integrations.activeFor(IntegrationKind.tavily);
    if (account == null) {
      return 'Tavily is not connected. Ask the user to connect it in '
          'Integrations.';
    }
    final query = rawQuery.trim();
    if (query.isEmpty) return 'Pass the web search query as target.';
    final response = await httpClient
        .post(
          Uri.parse('https://api.tavily.com/search'),
          headers: {
            'Authorization': 'Bearer ${account.token}',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'query': query,
            'search_depth': 'basic',
            'max_results': 5,
            'include_answer': false,
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 401 || response.statusCode == 403) {
      return 'Tavily rejected the saved API key. Ask the user to reconnect it '
          'in Integrations.';
    }
    if (response.statusCode != 200) {
      return 'Tavily returned ${response.statusCode} for this search.';
    }
    final decoded = jsonDecode(response.body);
    final results = decoded is Map ? decoded['results'] : null;
    if (results is! List || results.isEmpty) {
      return 'Tavily returned no results for "$query".';
    }
    final lines = results.whereType<Map>().take(5).map((item) {
      final title = '${item['title'] ?? ''}'.trim();
      final url = '${item['url'] ?? ''}'.trim();
      final content = '${item['content'] ?? ''}'.trim();
      final excerpt =
          content.length > 500 ? '${content.substring(0, 500)}…' : content;
      return '- ${title.isEmpty ? url : title}\n  $url\n  $excerpt';
    }).join('\n');
    return 'Tavily results for "$query":\n$lines';
  }

  Future<String> _supabaseStatus(String rawTarget) async {
    final account = integrations.activeFor(IntegrationKind.supabase);
    if (account == null) {
      return 'Supabase is not connected. Ask the user to connect it in '
          'Integrations.';
    }
    final response = await httpClient.get(
      Uri.parse('https://api.supabase.com/v1/projects'),
      headers: {
        'Authorization': 'Bearer ${account.token}',
        'Accept': 'application/json',
      },
    ).timeout(const Duration(seconds: 30));
    if (response.statusCode == 401 || response.statusCode == 403) {
      return 'Supabase rejected the saved access token. Ask the user to '
          'reconnect it in Integrations.';
    }
    if (response.statusCode != 200) {
      return 'Supabase returned ${response.statusCode} while listing projects.';
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      return 'Supabase returned an unexpected project list.';
    }
    final wanted = rawTarget.trim().toLowerCase();
    final projects = decoded.whereType<Map>().where((item) {
      if (wanted.isEmpty) return true;
      final ref = '${item['ref'] ?? ''}'.toLowerCase();
      final name = '${item['name'] ?? ''}'.toLowerCase();
      return ref == wanted ||
          name == wanted ||
          ref.contains(wanted) ||
          name.contains(wanted);
    }).toList();
    if (projects.isEmpty) {
      return 'No Supabase project matched "${rawTarget.trim()}".';
    }
    final lines = projects.take(12).map((item) {
      final database = item['database'];
      final host = database is Map ? '${database['host'] ?? ''}'.trim() : '';
      return '- ${item['name'] ?? 'project'} (ref ${item['ref'] ?? '?'}) '
          '· ${item['region'] ?? ''} · ${item['status'] ?? ''}'
          '${host.isEmpty ? '' : ' · $host'}';
    }).join('\n');
    return 'Supabase projects:\n$lines';
  }

  Future<(dynamic, String)> _expoGraphql(
    IntegrationAccount account,
    Map<String, dynamic> payload,
  ) async {
    final response = await httpClient
        .post(
          Uri.parse('https://api.expo.dev/graphql'),
          headers: {
            'Authorization': 'Bearer ${account.token}',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 401 || response.statusCode == 403) {
      return (
        null,
        'Expo rejected the saved access token. Ask the user to reconnect it '
            'in Integrations.'
      );
    }
    if (response.statusCode != 200) {
      return (null, 'Expo returned ${response.statusCode}.');
    }
    final decoded = jsonDecode(response.body);
    final errors = decoded is Map ? decoded['errors'] : null;
    if (errors is List && errors.isNotEmpty) {
      final message = errors
          .whereType<Map>()
          .map((item) => '${item['message'] ?? ''}'.trim())
          .where((item) => item.isNotEmpty)
          .join('; ');
      return (
        null,
        'Expo returned an error: '
            '${message.isEmpty ? 'unknown GraphQL error' : message}.'
      );
    }
    return (decoded, '');
  }

  Future<String> _expoBuildsStatus(Project project, String rawAppId) async {
    final account = integrations.activeFor(IntegrationKind.expo);
    if (account == null) {
      return 'Expo is not connected. Ask the user to connect it in '
          'Integrations.';
    }
    final appId = rawAppId.trim().isNotEmpty
        ? rawAppId.trim()
        : await _easProjectId(project);
    if (appId.isEmpty) {
      return 'No EAS project id is configured. Add extra.eas.projectId to '
          'app.json or pass the project id as target.';
    }
    const query = r'''query Builds($appId: String!, $limit: Int!) {
  app {
    byId(appId: $appId) {
      id
      name
      slug
      builds(limit: $limit, offset: 0) {
        id
        platform
        status
        createdAt
        error { message }
        artifacts { buildUrl }
      }
    }
  }
}''';
    final result = await _expoGraphql(account, {
      'query': query,
      'variables': {'appId': appId, 'limit': 8},
    });
    final decoded = result.$1;
    if (decoded == null) return result.$2;
    final data = decoded is Map ? decoded['data'] : null;
    final appQuery = data is Map ? data['app'] : null;
    final app = appQuery is Map ? appQuery['byId'] : null;
    if (app is! Map) return 'No Expo app matched project id $appId.';
    final builds = app['builds'];
    if (builds is! List || builds.isEmpty) {
      return 'No EAS builds found for ${app['slug'] ?? appId} yet.';
    }
    final lines = builds.whereType<Map>().take(8).map((build) {
      final error = build['error'];
      final errorMessage =
          error is Map ? '${error['message'] ?? ''}'.trim() : '';
      final artifacts = build['artifacts'];
      final buildUrl =
          artifacts is Map ? '${artifacts['buildUrl'] ?? ''}'.trim() : '';
      return '- ${build['id']} · ${build['platform'] ?? ''} '
          '· ${build['status'] ?? ''} · ${build['createdAt'] ?? ''}'
          '${buildUrl.isEmpty ? '' : ' · $buildUrl'}'
          '${errorMessage.isEmpty ? '' : ' · failed: $errorMessage'}';
    }).join('\n');
    return 'EAS builds for ${app['name'] ?? appId} '
        '(${app['slug'] ?? appId}):\n$lines';
  }

  Future<String> _expoProjectsStatus() async {
    final account = integrations.activeFor(IntegrationKind.expo);
    if (account == null) {
      return 'Expo is not connected. Ask the user to connect it in '
          'Integrations.';
    }
    const query = r'''query {
  meActor {
    __typename
    ... on UserActor { username }
    ... on Robot { firstName }
    ... on PartnerActor { username }
    accounts {
      id
      name
      apps {
        id
        name
        slug
      }
    }
  }
}''';
    final result = await _expoGraphql(account, {'query': query});
    final decoded = result.$1;
    if (decoded == null) return result.$2;
    final data = decoded is Map ? decoded['data'] : null;
    final actor = data is Map ? data['meActor'] : null;
    final accounts = actor is Map ? actor['accounts'] : null;
    if (accounts is! List || accounts.isEmpty) {
      return 'No Expo accounts were found for this token.';
    }
    final lines = <String>[];
    for (final item in accounts.whereType<Map>()) {
      final name = '${item['name'] ?? 'account'}'.trim();
      final apps = item['apps'];
      if (apps is! List || apps.isEmpty) {
        lines.add('- $name: no apps');
        continue;
      }
      for (final app in apps.whereType<Map>()) {
        lines.add('- $name: ${app['name'] ?? 'app'} '
            '(slug ${app['slug'] ?? '?'}, id ${app['id'] ?? '?'})');
      }
    }
    if (lines.isEmpty) return 'No Expo apps were found for this token.';
    return 'Expo accounts and projects:\n${lines.join('\n')}';
  }

  /// Reads the EAS project id from the project's Expo config so the agent can
  /// query builds without the user pasting it.
  Future<String> _easProjectId(Project project) async {
    for (final name in const ['app.json', 'app.config.json']) {
      try {
        final raw = await fsFor(project).read(name);
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        final extra = decoded['extra'];
        final eas = extra is Map ? extra['eas'] : null;
        final id = eas is Map ? eas['projectId'] : null;
        if (id is String && id.trim().isNotEmpty) return id.trim();
      } catch (_) {
        // A missing or non-JSON config is normal for non-Expo projects.
      }
    }
    return '';
  }

  /// Resolves a GitHub Actions target into an owner/repo, an optional run id
  /// and an optional job selector. It accepts a bare run id, owner/repo, a full
  /// Actions run or job URL, a relative run/job path, and `job:<id or name>`.
  /// An empty run id means "latest" and an empty selector means "failing jobs".
  (String, String, String) _githubRunTarget(String raw, String fallbackRepo) {
    final target = raw.trim();
    String clean(String value) =>
        value.replaceAll(RegExp(r'\.git$'), '').trim();
    String decode(String value) {
      try {
        return Uri.decodeComponent(value).trim();
      } catch (_) {
        return value.trim();
      }
    }

    String queryJob(String value) {
      final match = RegExp(r'[?&]job=([^&\s#]+)').firstMatch(value);
      return match == null ? '' : decode(match.group(1)!);
    }

    final fallback = clean(fallbackRepo);
    if (target.isEmpty) return (fallback, '', '');

    final absoluteRun = RegExp(
      r'(?:api\.github\.com/repos/|github\.com/)([^/\s]+)/([^/\s?#]+)/actions/runs/(\d+)(?:/job/([^/\s?#]+))?',
    ).firstMatch(target);
    if (absoluteRun != null) {
      return (
        '${absoluteRun.group(1)}/${clean(absoluteRun.group(2)!)}',
        absoluteRun.group(3)!,
        decode(absoluteRun.group(4) ?? queryJob(target)),
      );
    }
    final relativeRun = RegExp(
      r'^([^/\s]+)/([^/\s]+)/actions/runs/(\d+)(?:/job/([^/\s?#]+))?',
    ).firstMatch(target);
    if (relativeRun != null) {
      return (
        '${relativeRun.group(1)}/${clean(relativeRun.group(2)!)}',
        relativeRun.group(3)!,
        decode(relativeRun.group(4) ?? queryJob(target)),
      );
    }
    final bareRun = RegExp(r'^(\d+)(?:[?&].*)?$').firstMatch(target);
    if (bareRun != null) {
      return (fallback, bareRun.group(1)!, queryJob(target));
    }
    final runAndJob = RegExp(r'^(\d+)/job/([^/\s?#]+)').firstMatch(target);
    if (runAndJob != null) {
      return (fallback, runAndJob.group(1)!, decode(runAndJob.group(2)!));
    }
    final runOnly = RegExp(r'/actions/runs/(\d+)').firstMatch(target);
    if (runOnly != null) return (fallback, runOnly.group(1)!, queryJob(target));
    final jobOnly =
        RegExp(r'^job[:\s]+(.+)$', caseSensitive: false).firstMatch(target);
    if (jobOnly != null) return (fallback, '', decode(jobOnly.group(1)!));
    if (target.startsWith('http')) {
      final repoUrl =
          RegExp(r'github\.com/([^/\s]+)/([^/\s?#]+)').firstMatch(target);
      if (repoUrl != null) {
        return ('${repoUrl.group(1)}/${clean(repoUrl.group(2)!)}', '', '');
      }
      return (fallback, '', '');
    }
    if (target.contains('/')) return (clean(target), '', '');
    return (fallback, '', '');
  }

  /// Pages Direct Upload serves the files it receives; it does not build a
  /// Node project. Build first and upload the static output, otherwise a
  /// Next/React source tree is published and every URL returns 404.
  static const _npmInstallMarker = '.praxis/npm-install.json';

  Future<String> _npmInstallFingerprint(ProjectFs fs) async {
    final packageJson = await fs.read('package.json');
    final lock = await fs.exists('package-lock.json')
        ? await fs.read('package-lock.json')
        : '';
    return TaskCheckpoint.digestText('$packageJson\n$lock');
  }

  Future<bool> _npmInstallIsCurrent(
    ProjectFs fs,
    String fingerprint,
  ) async {
    // A folder alone is not proof of a finished install. npm writes its own
    // hidden lockfile at the end, and our marker records which manifest was
    // installed. A timeout can leave a partial folder with neither.
    String? markerFingerprint;
    try {
      final raw = jsonDecode(await fs.read(_npmInstallMarker));
      if (raw is Map) markerFingerprint = raw['fingerprint'] as String?;
    } catch (_) {
      markerFingerprint = null;
    }
    return npmInstallReusable(
      hasNodeModules: await fs.exists('node_modules'),
      hasNpmLock: await fs.exists('node_modules/.package-lock.json'),
      markerFingerprint: markerFingerprint,
      fingerprint: fingerprint,
    );
  }

  /// Exercises the production Pages preparation path, including its real
  /// install, build, marker and output-folder checks.
  @visibleForTesting
  Future<List<DeploymentFile>> prepareCloudflareFilesForTest(Project project) =>
      _cloudflareFiles(project, null);

  Future<List<DeploymentFile>> _cloudflareFiles(
    Project project,
    void Function(DeployProgress)? onProgress,
  ) async {
    final fs = fsFor(project);
    if (project.kind != ProjectKind.node || !await fs.exists('package.json')) {
      return fs.deploymentFiles();
    }
    // A Node project that already has a root index.html is a static site.
    if (await fs.exists('index.html')) return fs.deploymentFiles();

    var hasBuild = false;
    try {
      hasBuild = hasNpmBuildScript(await fs.read('package.json'));
    } catch (_) {
      hasBuild = false;
    }
    if (!hasBuild) {
      final existing = await _staticOutput(fs);
      if (existing != null) return fs.deploymentFiles(from: existing);
      throw IntegrationException(
          'This Node project has no build script and no static output. Add a '
          'build script that writes to out/, dist/ or build/.');
    }

    final shell = systemShellFor(project);
    final envEntries = await environmentFor(project);
    final environment = ProjectEnvStore.values(envEntries);
    final installFingerprint = await _npmInstallFingerprint(fs);
    if (!await _npmInstallIsCurrent(fs, installFingerprint)) {
      // Remove a partial node_modules left by an earlier timeout before a
      // clean install. Skipping this because the folder merely existed kept
      // publishing builds with missing dependencies.
      if (await fs.exists('node_modules')) {
        onProgress?.call(const DeployProgress(
          'Building',
          detail: 'Removing incomplete node_modules',
        ));
        try {
          await fs.delete('node_modules');
        } catch (error) {
          throw IntegrationException(
            'Could not remove the incomplete node_modules folder. Delete it '
            'and deploy again. $error',
          );
        }
      }
      if (await fs.exists(_npmInstallMarker)) {
        try {
          await fs.delete(_npmInstallMarker);
        } catch (_) {
          // A stale marker is harmless when node_modules is gone.
        }
      }
      onProgress?.call(const DeployProgress(
        'Building',
        detail: 'Installing dependencies (clean install)',
      ));
      final install = await shell.run(
        cloudflareNpmInstallCommand,
        environment: environment,
        timeout: const Duration(minutes: 20),
      );
      if (install.exitCode != 0) {
        final logs = maskSecretValues(install.output, envEntries);
        throw IntegrationException(
          'npm install failed (exit ${install.exitCode}). ${_tail(logs)}',
          logs: _boundedLog(logs),
          runtime: 'Cloudflare Pages',
        );
      }
      try {
        await fs.write(
          _npmInstallMarker,
          jsonEncode({
            'fingerprint': installFingerprint,
            'installedAt': DateTime.now().toIso8601String(),
          }),
        );
      } catch (_) {
        // A missing marker only causes a clean install on the next deploy.
      }
    }
    onProgress?.call(const DeployProgress(
      'Building',
      detail: 'Running npm run build',
    ));
    final build = await shell.run(
      cloudflareNpmBuildCommand,
      environment: environment,
      timeout: const Duration(minutes: 20),
    );
    if (build.exitCode != 0) {
      final logs = maskSecretValues(build.output, envEntries);
      throw IntegrationException(
        'npm run build failed (exit ${build.exitCode}). ${_tail(logs)}',
        logs: _boundedLog(logs),
        runtime: 'Cloudflare Pages',
      );
    }
    final output = await _staticOutput(fs);
    if (output == null) {
      throw IntegrationException(
          'The build finished but no static folder was found. For Next.js, set '
          "output: 'export' so the build writes to out/.");
    }
    onProgress?.call(DeployProgress('Preparing', detail: 'Reading $output/'));
    return fs.deploymentFiles(from: output);
  }

  Future<String?> _staticOutput(ProjectFs fs) => staticOutputFolder(fs);

  String _tail(String output) {
    final trimmed = output.trim();
    if (trimmed.isEmpty) return '';
    final lines = trimmed.split('\n');
    return lines.skip(lines.length > 6 ? lines.length - 6 : 0).join('\n');
  }

  /// Removes the newest unpushed commit record for a branch. The files on disk
  /// stay untouched and immediately return to the changed-files list.
  /// Records a locally created commit without changing the remote tree. The
  /// pending commit keeps its own hashes, so reverting it can restore the
  /// previous merge base instead of treating the committed files as clean.
  PushState recordPendingCommit(
    PushState current, {
    required String owner,
    required String repo,
    required String branch,
    required String sha,
    required String message,
    required Map<String, String> texts,
    required Map<String, String> hashes,
    required Set<String> deleted,
  }) {
    final baseHashes = {...current.comparisonBase, ...hashes};
    for (final path in deleted) {
      baseHashes.remove(path);
    }
    // The baseline is the remote text used for offline diffs. Leave it alone
    // until the commit is pushed; the pending commit carries its own text.
    return current
        .copyWith(
          owner: owner,
          repo: repo,
          branch: branch,
          baseHashes: baseHashes,
        )
        .withPending(PendingCommit(
          sha: sha,
          message: message,
          at: DateTime.now(),
          owner: owner,
          repo: repo,
          branch: branch,
          files: texts,
          hashes: hashes,
          deleted: deleted.toList(growable: false),
        ));
  }

  Future<PushState> revertLatestPending(
    Project project, {
    required String owner,
    required String repo,
    required String branch,
  }) async {
    final current = await pushStateFor(project);
    final latest = current.lastPendingFor(owner, repo, branch);
    if (latest == null) return current;
    // The commit moved these files into the base. Undo that so they appear as
    // uncommitted edits again, relative to the branch that is still on GitHub.
    final paths = {
      ...latest.hashes.keys,
      ...latest.files.keys,
      ...latest.deleted,
    };
    final baseHashes = Map<String, String>.from(current.baseHashes);
    final hashes = Map<String, String>.from(current.hashes);
    if (baseHashes.isNotEmpty) {
      for (final path in paths) {
        final remote = current.hashes[path];
        if (remote == null) {
          baseHashes.remove(path);
          hashes.remove(path);
        } else {
          baseHashes[path] = remote;
        }
      }
    }
    return savePushState(
      project,
      current
          .copyWith(baseHashes: baseHashes, hashes: hashes)
          .withoutPending([latest.sha]),
    );
  }

  /// Paths whose content changed on GitHub since this device last synced.
  /// These are pullable; they are deliberately not part of the local change
  /// list.
  Future<List<String>> remoteDriftFor(Project project) async {
    final state = await pushStateFor(project);
    final base = state.comparisonBase;
    final paths = <String>{...base.keys, ...state.hashes.keys};
    return paths.where((path) => state.hashes[path] != base[path]).toList()
      ..sort();
  }

  /// Restores one file to the merge base, so only this file stops being shown
  /// as a local change. A file that exists only on this device is deleted.
  Future<PushState> revertFile(
    Project project, {
    IntegrationAccount? account,
    required String owner,
    required String repo,
    required String branch,
    required String path,
  }) async {
    final state = await pushStateFor(project);
    final base = state.comparisonBase;
    final baseHash = base[path];
    final remoteHash = state.hashes[path];
    final fs = fsFor(project);
    if (baseHash == null && remoteHash == null) {
      if (await fs.exists(path)) await fs.delete(path);
      final baseHashes = Map<String, String>.from(state.baseHashes)
        ..remove(path);
      final hashes = Map<String, String>.from(state.hashes)..remove(path);
      final baseline = Map<String, String>.from(state.baseline)..remove(path);
      return savePushState(
        project,
        state.copyWith(
          baseHashes: baseHashes,
          hashes: hashes,
          baseline: baseline,
        ),
      );
    }
    final cached = state.baseline[path];
    List<int>? restored;
    if (cached != null &&
        (baseHash == null || gitBlobSha(utf8.encode(cached)) == baseHash)) {
      restored = utf8.encode(cached);
    } else if (account != null &&
        remoteHash != null &&
        (baseHash == null || remoteHash == baseHash)) {
      restored = await GitHubClient(account.token, client: httpClient)
          .fileBytes(owner, repo, path, branch);
    }
    if (restored == null) {
      throw IntegrationException(
          'Praxis has no saved copy of $path to restore. Pull from GitHub first.');
    }
    await fs.writeBytes(path, restored);
    final baseHashes = Map<String, String>.from(state.comparisonBase);
    final baseline = Map<String, String>.from(state.baseline);
    if (baseHash == null) {
      baseHashes.remove(path);
    } else {
      baseHashes[path] = baseHash;
    }
    final text = decodeUtf8(restored, allowEmpty: true);
    if (text != null) {
      baseline[path] = text;
    } else {
      baseline.remove(path);
    }
    return savePushState(
      project,
      state.copyWith(baseHashes: baseHashes, baseline: baseline),
    );
  }

  // ------------------------------------------------------------ dependencies

  /// Dependency commands always run at the project root on their own shell.
  /// Reusing the interactive shell would run npm in whatever subfolder the
  /// user last entered and would race an agent command using that shell.
  SystemShell _dependencyShell(Project project) => SystemShell(
        fsFor(project),
        linux: linux,
        packageCacheRoot: Directory('${root.path}/package-cache'),
      );

  void _ensureDependencyToolsIdle() {
    final deploying = runningBackgroundJobs
        .any((job) => job.kind == BackgroundJobKind.deploy);
    if (busy || deploying) {
      throw StateError('Wait for the current agent or deploy job to finish.');
    }
  }

  Future<DependencyReport> dependencyReport(Project project) async {
    final nodeStatus = linux?.runtimes[LinuxRuntime.node];
    final pythonStatus = linux?.runtimes[LinuxRuntime.python];
    final nodeReady =
        linux == null ? !Platform.isAndroid : nodeStatus?.installed ?? false;
    final pythonReady =
        linux == null ? !Platform.isAndroid : pythonStatus?.installed ?? false;
    return inspectDependencies(
      fsFor(project),
      nodeProject: project.kind == ProjectKind.node,
      pythonProject: project.kind == ProjectKind.python,
      nodeRuntimeReady: nodeReady,
      nodeRuntimeVersion: nodeStatus?.version ?? '',
      pythonRuntimeReady: pythonReady,
      pythonRuntimeVersion: pythonStatus?.version ?? '',
    );
  }

  Future<DependencyAudit> auditDependencies(Project project) async {
    _ensureDependencyToolsIdle();
    final report = await dependencyReport(project);
    if (report.ecosystem != DependencyEcosystem.node) {
      return const DependencyAudit(
        error: 'Registry checks are available for npm projects.',
      );
    }
    final shell = _dependencyShell(project);
    final entries = await environmentFor(project);
    final environment = ProjectEnvStore.values(entries);
    final outdated = await shell.run(
      'npm outdated --json',
      environment: environment,
      timeout: const Duration(minutes: 2),
    );
    final audit = await shell.run(
      'npm audit --json',
      environment: environment,
      timeout: const Duration(minutes: 4),
    );
    final parsedOutdated = parseNpmOutdated(outdated.output);
    final parsedAudit = parseNpmAudit(audit.output);
    var error = '';
    if (outdated.exitCode != 0 && parsedOutdated.isEmpty) {
      error = 'npm outdated could not complete (exit ${outdated.exitCode}).';
    }
    if (audit.exitCode != 0 && !parsedAudit.hasData) {
      error = [
        if (error.isNotEmpty) error,
        'npm audit could not complete (exit ${audit.exitCode}).',
      ].join(' ');
    }
    return DependencyAudit(
      latest: parsedOutdated,
      severities: parsedAudit.severities,
      totalVulnerabilities: parsedAudit.totalVulnerabilities,
      error: maskSecretValues(error, entries),
      checkedAt: DateTime.now(),
    );
  }

  Future<String> repairDependencies(Project project) async {
    _ensureDependencyToolsIdle();
    final report = await dependencyReport(project);
    if (!report.hasEcosystem || report.repairCommand.isEmpty) {
      throw StateError('No dependency install was found for this project.');
    }
    final fs = fsFor(project);
    final shell = _dependencyShell(project);
    final entries = await environmentFor(project);
    final environment = ProjectEnvStore.values(entries);
    if (report.ecosystem == DependencyEcosystem.node) {
      if (await fs.exists('node_modules')) {
        await fs.delete('node_modules');
      }
      if (await fs.exists(_npmInstallMarker)) {
        await fs.delete(_npmInstallMarker);
      }
    }
    final result = await shell.run(
      report.repairCommand,
      environment: environment,
      timeout: const Duration(minutes: 20),
    );
    final output = maskSecretValues(result.output, entries);
    if (result.exitCode != 0) {
      throw StateError(
        'Dependency install failed (exit ${result.exitCode}). ${_tail(output)}',
      );
    }
    if (report.ecosystem == DependencyEcosystem.node &&
        report.manager == 'npm' &&
        await fs.exists('package.json')) {
      try {
        final fingerprint = await _npmInstallFingerprint(fs);
        await fs.write(
          _npmInstallMarker,
          jsonEncode({
            'fingerprint': fingerprint,
            'installedAt': DateTime.now().toIso8601String(),
          }),
        );
      } catch (_) {
        // The install succeeded; a missing marker only causes a clean retry.
      }
    }
    notifyListeners();
    return output.trim().isEmpty
        ? 'Dependencies installed with ${report.manager}.'
        : 'Dependencies installed. ${_tail(output)}';
  }

  Future<String> repairDependencyCache(Project project) async {
    _ensureDependencyToolsIdle();
    final report = await dependencyReport(project);
    if (report.cacheCommand.isEmpty) {
      throw StateError('No package cache was found for this project.');
    }
    final entries = await environmentFor(project);
    final result = await _dependencyShell(project).run(
      report.cacheCommand,
      environment: ProjectEnvStore.values(entries),
      timeout: const Duration(minutes: 10),
    );
    final output = maskSecretValues(result.output, entries);
    if (result.exitCode != 0) {
      throw StateError(
        'Cache repair failed (exit ${result.exitCode}). ${_tail(output)}',
      );
    }
    return output.trim().isEmpty ? 'Package cache repaired.' : _tail(output);
  }

  Future<String> updateDependency(Project project, String package) async {
    if (!isDependencyName(package)) {
      throw ArgumentError('Use a valid package name.');
    }
    final report = await dependencyReport(project);
    final command = switch (report.manager) {
      'yarn' => 'yarn add $package@latest',
      'pnpm' => 'pnpm add $package@latest',
      'bun' => 'bun add $package@latest',
      _ => 'npm install $package@latest --no-audit --no-fund',
    };
    return _runDependencyCommand(project, command);
  }

  Future<String> removeDependency(Project project, String package) async {
    if (!isDependencyName(package)) {
      throw ArgumentError('Use a valid package name.');
    }
    final report = await dependencyReport(project);
    final command = switch (report.manager) {
      'yarn' => 'yarn remove $package',
      'pnpm' => 'pnpm remove $package',
      'bun' => 'bun remove $package',
      _ => 'npm uninstall $package --no-audit --no-fund',
    };
    return _runDependencyCommand(project, command);
  }

  Future<String> _runDependencyCommand(
    Project project,
    String command,
  ) async {
    _ensureDependencyToolsIdle();
    final entries = await environmentFor(project);
    final result = await _dependencyShell(project).run(
      command,
      environment: ProjectEnvStore.values(entries),
      timeout: const Duration(minutes: 20),
    );
    final output = maskSecretValues(result.output, entries);
    if (result.exitCode != 0) {
      throw StateError(
        'Package change failed (exit ${result.exitCode}). ${_tail(output)}',
      );
    }
    notifyListeners();
    return output.trim().isEmpty ? 'Package change complete.' : _tail(output);
  }

  // ------------------------------------------------------------- follow-ups

  Future<List<FollowUpSuggestion>> followUpSuggestions(Project project) async {
    var changed = <String>[];
    try {
      changed = (await changesFor(project))
          .map((change) => change.path)
          .where((path) => !path.startsWith('.'))
          .take(12)
          .toList();
    } catch (_) {
      // A fresh project may not have a baseline yet; the other signals still
      // produce useful suggestions.
    }
    return buildFollowUps(
      project: project,
      thread: threadOf(project.id),
      changedFiles: changed,
      todos: todosFor(project.id),
      canPush: activeGithub != null,
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
    // usageEvents is append-only, so walking it forward returned the oldest
    // request. The context meter must reflect the most recent request.
    UsageEvent? latest;
    for (final event in usageEvents) {
      if (projectId != null && event.projectId != projectId) continue;
      if (event.providerId != providerId || event.model != model) continue;
      if (latest == null || event.at.isAfter(latest.at)) latest = event;
    }
    return latest?.promptTokens;
  }

  int? contextLimitFor(ProviderConfig provider) =>
      provider.contextLengths[provider.model] ??
      contextWindowFor(provider.model);

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
    // Transcripts live in the key-value store, not in the project folder, so
    // deleting the folder alone would leave the conversation history behind.
    for (final project in projects) {
      await store.remove('$_kChatPrefix${project.id}');
    }
    _chatPersistTimer?.cancel();
    _chatPersistTimer = null;
    _chatPersistProject = null;
    projects.clear();
    _threads.clear();
    _todos.clear();
    _checkpoints.clear();
    _deployJobs.clear();
    _drafts.clear();
    _fs.clear();
    _shells.clear();
    _systemShells.clear();
    _pushStates.clear();
    _jobJournal.items.clear();
    await _jobJournal.flush();
    if (_foregroundServiceOn) {
      await backgroundJobPlatform.stop();
      _foregroundServiceOn = false;
    }
    _clearLive();
    await _liveDraftWrites;
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
      _kQuota,
      _kLiveDraft,
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

  @override
  void dispose() {
    _activeAgentJobId = null;
    if (_foregroundServiceOn) unawaited(backgroundJobPlatform.stop());
    if (_jobsLoaded) unawaited(_jobJournal.flush());
    super.dispose();
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
