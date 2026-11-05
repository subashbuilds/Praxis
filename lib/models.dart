import 'package:flutter/material.dart';

import 'theme/tokens.dart';

enum ProjectKind { web, flutter, python, blank }

extension ProjectKindX on ProjectKind {
  String get label => switch (this) {
        ProjectKind.web => 'Web',
        ProjectKind.flutter => 'Flutter',
        ProjectKind.python => 'Python',
        ProjectKind.blank => 'Empty',
      };

  String get blurb => switch (this) {
        ProjectKind.web => 'index.html, style.css, app.js — previews live',
        ProjectKind.flutter => 'Dart sources, edited on device',
        ProjectKind.python => 'main.py — run from the shell',
        ProjectKind.blank => 'Nothing but a folder',
      };

  IconData get glyph => switch (this) {
        ProjectKind.web => Icons.language_rounded,
        ProjectKind.flutter => Icons.flutter_dash,
        ProjectKind.python => Icons.code_rounded,
        ProjectKind.blank => Icons.folder_open_rounded,
      };

  Color get tint => switch (this) {
        ProjectKind.web => Pal.mint,
        ProjectKind.flutter => Pal.sky,
        ProjectKind.python => Pal.amber,
        ProjectKind.blank => Pal.textMuted,
      };

  List<MapEntry<String, String>> get scaffold => switch (this) {
        ProjectKind.web => const [
            MapEntry('index.html', kIndexHtml),
            MapEntry('style.css', kStyleCss),
            MapEntry('app.js', kAppJs),
            MapEntry('README.md',
                '# New project\n\nA web project, served from the Preview tab.\n'),
          ],
        ProjectKind.flutter => const [
            MapEntry('pubspec.yaml',
                'name: app\nenvironment:\n  sdk: ">=3.4.0 <4.0.0"\ndependencies:\n  flutter:\n    sdk: flutter\n'),
            MapEntry('lib/main.dart', kDartMain),
            MapEntry('README.md', '# New Flutter project\n'),
          ],
        ProjectKind.python => const [
            MapEntry('main.py',
                'def main():\n    print("hello from Praxis")\n\n\nif __name__ == "__main__":\n    main()\n'),
            MapEntry('README.md', '# New Python project\n'),
          ],
        ProjectKind.blank => const [],
      };

  static ProjectKind fromId(String? id) => ProjectKind.values.firstWhere(
        (k) => k.name == id,
        orElse: () => ProjectKind.blank,
      );
}

class Project {
  const Project({
    required this.id,
    required this.name,
    required this.kind,
    required this.createdAt,
    this.repo = '',
    this.branch = 'main',
  });

  final String id;
  final String name;
  final ProjectKind kind;
  final DateTime createdAt;

  /// `owner/name` when the project was cloned from or pushed to GitHub.
  final String repo;
  final String branch;

  Project copyWith({String? repo, String? branch}) => Project(
        id: id,
        name: name,
        kind: kind,
        createdAt: createdAt,
        repo: repo ?? this.repo,
        branch: branch ?? this.branch,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'createdAt': createdAt.toIso8601String(),
        'repo': repo,
        'branch': branch,
      };

  static Project fromJson(Map<String, dynamic> json) => Project(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'project',
        kind: ProjectKindX.fromId(json['kind'] as String?),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        repo: json['repo'] as String? ?? '',
        branch: json['branch'] as String? ?? 'main',
      );
}

enum ApiFlavor { openai, anthropic }

class ProviderConfig {
  const ProviderConfig({
    required this.id,
    required this.name,
    required this.icon,
    required this.baseUrl,
    required this.model,
    required this.flavor,
    this.keys = const [],
    this.keyIndex = 0,
    this.models = const [],
    this.selectedModels = const [],
    this.requiresKey = true,
    this.isCustom = false,
    this.hint = '',
  });

  final String id;
  final String name;
  final String icon;
  final String baseUrl;
  final String model;
  final ApiFlavor flavor;

  /// Keys are tried in order. [keyIndex] is the one the agent is using now;
  /// it moves forward when a key hits its limit and the user allows it.
  final List<String> keys;
  final int keyIndex;

  /// Models returned by the provider's `/models` endpoint, and the subset the
  /// user chose to keep.
  final List<String> models;
  final List<String> selectedModels;
  final bool requiresKey;
  final bool isCustom;
  final String hint;

  String get apiKey {
    if (keys.isEmpty) return '';
    final index = keyIndex.clamp(0, keys.length - 1);
    return keys[index].trim();
  }

  bool get hasKeys => keys.any((key) => key.trim().isNotEmpty);
  bool get ready => !requiresKey || hasKeys;
  bool get isConfigured => model.trim().isNotEmpty && ready;
  bool get hasMoreKeys =>
      keyIndex + 1 < keys.length &&
      keys.skip(keyIndex + 1).any((key) => key.trim().isNotEmpty);

  ProviderConfig copyWith({
    String? name,
    String? baseUrl,
    String? model,
    ApiFlavor? flavor,
    List<String>? keys,
    int? keyIndex,
    List<String>? models,
    List<String>? selectedModels,
    bool? requiresKey,
  }) =>
      ProviderConfig(
        id: id,
        name: name ?? this.name,
        icon: icon,
        baseUrl: baseUrl ?? this.baseUrl,
        model: model ?? this.model,
        flavor: flavor ?? this.flavor,
        keys: keys ?? this.keys,
        keyIndex: keyIndex ?? this.keyIndex,
        models: models ?? this.models,
        selectedModels: selectedModels ?? this.selectedModels,
        requiresKey: requiresKey ?? this.requiresKey,
        isCustom: isCustom,
        hint: hint,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'baseUrl': baseUrl,
        'model': model,
        'flavor': flavor.name,
        'keys': keys,
        'keyIndex': keyIndex,
        'models': models,
        'selectedModels': selectedModels,
        'requiresKey': requiresKey,
        'isCustom': isCustom,
        'hint': hint,
      };

  static List<String> _strings(Object? raw) =>
      raw is List ? raw.whereType<String>().toList() : const [];

  static ProviderConfig fromJson(Map<String, dynamic> json) {
    final stored = _strings(json['keys']);
    final legacy = json['apiKey'] as String? ?? '';
    final keys = stored.isNotEmpty
        ? stored
        : (legacy.trim().isEmpty ? const <String>[] : [legacy]);
    final keyIndex = (json['keyIndex'] as int? ?? 0).clamp(
      0,
      keys.isEmpty ? 0 : keys.length - 1,
    );
    return ProviderConfig(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Provider',
      icon: json['icon'] as String? ?? 'assets/icons/opencode.svg',
      baseUrl: json['baseUrl'] as String? ?? '',
      model: json['model'] as String? ?? '',
      flavor: ApiFlavor.values.firstWhere(
        (f) => f.name == json['flavor'],
        orElse: () => ApiFlavor.openai,
      ),
      keys: keys,
      keyIndex: keyIndex,
      models: _strings(json['models']),
      selectedModels: _strings(json['selectedModels']),
      requiresKey: json['requiresKey'] as bool? ?? true,
      isCustom: json['isCustom'] as bool? ?? false,
      hint: json['hint'] as String? ?? '',
    );
  }
}

/// Every preset is a real endpoint that needs the user's own key (except
/// Ollama, which talks to a server on the user's network). There is no
/// bundled "free" model: without a key there is nothing to call.
const kProviderPresets = <ProviderConfig>[
  ProviderConfig(
    id: 'openai',
    name: 'OpenAI',
    icon: 'assets/icons/openai.svg',
    baseUrl: 'https://api.openai.com/v1',
    model: 'gpt-4o-mini',
    flavor: ApiFlavor.openai,
    hint: 'platform.openai.com/api-keys',
  ),
  ProviderConfig(
    id: 'anthropic',
    name: 'Anthropic',
    icon: 'assets/icons/claude.svg',
    baseUrl: 'https://api.anthropic.com/v1',
    model: 'claude-3-5-sonnet-latest',
    flavor: ApiFlavor.anthropic,
    hint: 'console.anthropic.com/settings/keys',
  ),
  ProviderConfig(
    id: 'gemini',
    name: 'Google Gemini',
    icon: 'assets/icons/gemini.svg',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
    model: 'gemini-2.0-flash',
    flavor: ApiFlavor.openai,
    hint: 'aistudio.google.com/apikey',
  ),
  ProviderConfig(
    id: 'openrouter',
    name: 'OpenRouter',
    icon: 'assets/icons/openrouter.svg',
    baseUrl: 'https://openrouter.ai/api/v1',
    model: 'openai/gpt-4o-mini',
    flavor: ApiFlavor.openai,
    hint: 'openrouter.ai/keys',
  ),
  ProviderConfig(
    id: 'groq',
    name: 'Groq',
    icon: 'assets/icons/groq.svg',
    baseUrl: 'https://api.groq.com/openai/v1',
    model: 'llama-3.3-70b-versatile',
    flavor: ApiFlavor.openai,
    hint: 'console.groq.com/keys',
  ),
  ProviderConfig(
    id: 'deepseek',
    name: 'DeepSeek',
    icon: 'assets/icons/deepseek.svg',
    baseUrl: 'https://api.deepseek.com/v1',
    model: 'deepseek-chat',
    flavor: ApiFlavor.openai,
    hint: 'platform.deepseek.com/api_keys',
  ),
  ProviderConfig(
    id: 'mistral',
    name: 'Mistral',
    icon: 'assets/icons/mistral.svg',
    baseUrl: 'https://api.mistral.ai/v1',
    model: 'codestral-latest',
    flavor: ApiFlavor.openai,
    hint: 'console.mistral.ai/api-keys',
  ),
  ProviderConfig(
    id: 'cerebras',
    name: 'Cerebras',
    icon: 'assets/icons/cerebras.svg',
    baseUrl: 'https://api.cerebras.ai/v1',
    model: 'llama-3.3-70b',
    flavor: ApiFlavor.openai,
    hint: 'cloud.cerebras.ai',
  ),
  ProviderConfig(
    id: 'together',
    name: 'Together AI',
    icon: 'assets/icons/meta.svg',
    baseUrl: 'https://api.together.xyz/v1',
    model: 'meta-llama/Llama-3.3-70B-Instruct-Turbo',
    flavor: ApiFlavor.openai,
    hint: 'api.together.ai/settings/api-keys',
  ),
  ProviderConfig(
    id: 'nvidia',
    name: 'NVIDIA NIM',
    icon: 'assets/icons/nvidia.svg',
    baseUrl: 'https://integrate.api.nvidia.com/v1',
    model: 'meta/llama-3.3-70b-instruct',
    flavor: ApiFlavor.openai,
    hint: 'build.nvidia.com → API keys',
  ),
  ProviderConfig(
    id: 'ollama',
    name: 'Ollama (LAN)',
    icon: 'assets/icons/ollama.svg',
    baseUrl: 'http://localhost:11434/v1',
    model: 'llama3.2',
    flavor: ApiFlavor.openai,
    requiresKey: false,
    hint: 'Ollama on this device or your network',
  ),
];

class AiProviderException implements Exception {
  AiProviderException(this.message, {this.status});
  final String message;
  final int? status;

  /// True when the provider said the key is rate-limited or out of credit,
  /// which is the only case where another key can help.
  bool get isLimit {
    if (status == 402 || status == 429) return true;
    final text = message.toLowerCase();
    return text.contains('quota') ||
        text.contains('insufficient') ||
        text.contains('credit') ||
        text.contains('rate limit') ||
        text.contains('rate_limit') ||
        text.contains('too many requests');
  }

  @override
  String toString() => message;
}

class Skill {
  const Skill({
    required this.id,
    required this.name,
    required this.instructions,
    this.enabled = true,
  });

  final String id;
  final String name;
  final String instructions;
  final bool enabled;

  Skill copyWith({String? name, String? instructions, bool? enabled}) => Skill(
        id: id,
        name: name ?? this.name,
        instructions: instructions ?? this.instructions,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'instructions': instructions,
        'enabled': enabled,
      };

  static Skill fromJson(Map<String, dynamic> json) => Skill(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Skill',
        instructions: json['instructions'] as String? ?? '',
        enabled: json['enabled'] as bool? ?? true,
      );
}

enum IntegrationKind { github, vercel }

extension IntegrationKindX on IntegrationKind {
  String get label => switch (this) {
        IntegrationKind.github => 'GitHub',
        IntegrationKind.vercel => 'Vercel',
      };

  String get tokenHint => switch (this) {
        IntegrationKind.github => 'GitHub personal access token',
        IntegrationKind.vercel => 'Vercel access token',
      };
}

class IntegrationAccount {
  const IntegrationAccount({
    required this.id,
    required this.kind,
    required this.label,
    required this.username,
    required this.token,
    this.createdAt,
  });

  final String id;
  final IntegrationKind kind;
  final String label;
  final String username;
  final String token;
  final DateTime? createdAt;

  String get displayName => label.trim().isNotEmpty
      ? label.trim()
      : username.trim().isNotEmpty
          ? username
          : kind.label;

  IntegrationAccount copyWith(
          {String? label, String? username, String? token}) =>
      IntegrationAccount(
        id: id,
        kind: kind,
        label: label ?? this.label,
        username: username ?? this.username,
        token: token ?? this.token,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'label': label,
        'username': username,
        'token': token,
        'createdAt': createdAt?.toIso8601String(),
      };

  static IntegrationAccount fromJson(Map<String, dynamic> json) =>
      IntegrationAccount(
        id: json['id'] as String? ??
            'account-${DateTime.now().microsecondsSinceEpoch}',
        kind: IntegrationKind.values.firstWhere(
          (kind) => kind.name == json['kind'],
          orElse: () => IntegrationKind.github,
        ),
        label: json['label'] as String? ?? '',
        username: json['username'] as String? ?? '',
        token: json['token'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      );
}

class Integrations {
  const Integrations({
    this.accounts = const [],
    this.activeGithubId = '',
    this.activeVercelId = '',
  });

  final List<IntegrationAccount> accounts;
  final String activeGithubId;
  final String activeVercelId;

  List<IntegrationAccount> ofKind(IntegrationKind kind) =>
      accounts.where((account) => account.kind == kind).toList();

  IntegrationAccount? accountById(String id) {
    for (final account in accounts) {
      if (account.id == id) return account;
    }
    return null;
  }

  IntegrationAccount? activeFor(IntegrationKind kind) {
    final list = ofKind(kind);
    if (list.isEmpty) return null;
    final id = kind == IntegrationKind.github ? activeGithubId : activeVercelId;
    return accountById(id) ?? list.first;
  }

  /// Kept for older call sites that only need to know whether an account exists.
  String get githubToken => activeFor(IntegrationKind.github)?.token ?? '';
  String get vercelToken => activeFor(IntegrationKind.vercel)?.token ?? '';

  Integrations copyWith({
    List<IntegrationAccount>? accounts,
    String? activeGithubId,
    String? activeVercelId,
  }) =>
      Integrations(
        accounts: accounts ?? this.accounts,
        activeGithubId: activeGithubId ?? this.activeGithubId,
        activeVercelId: activeVercelId ?? this.activeVercelId,
      );

  Integrations addOrReplace(IntegrationAccount account) {
    final next = [
      for (final existing in accounts)
        if (existing.id != account.id) existing,
      account,
    ];
    return copyWith(
      accounts: next,
      activeGithubId:
          account.kind == IntegrationKind.github ? account.id : activeGithubId,
      activeVercelId:
          account.kind == IntegrationKind.vercel ? account.id : activeVercelId,
    );
  }

  Integrations remove(String id) {
    final next = accounts.where((account) => account.id != id).toList();
    return Integrations(
      accounts: next,
      activeGithubId: activeGithubId == id ? '' : activeGithubId,
      activeVercelId: activeVercelId == id ? '' : activeVercelId,
    );
  }

  Integrations activate(IntegrationAccount account) => copyWith(
        activeGithubId: account.kind == IntegrationKind.github
            ? account.id
            : activeGithubId,
        activeVercelId: account.kind == IntegrationKind.vercel
            ? account.id
            : activeVercelId,
      );

  Map<String, dynamic> toJson() => {
        'accounts': accounts.map((account) => account.toJson()).toList(),
        'activeGithubId': activeGithubId,
        'activeVercelId': activeVercelId,
      };

  static Integrations fromJson(Map<String, dynamic> json) {
    final raw = json['accounts'];
    if (raw is List) {
      return Integrations(
        accounts: [
          for (final item in raw)
            if (item is Map)
              IntegrationAccount.fromJson(item.cast<String, dynamic>()),
        ],
        activeGithubId: json['activeGithubId'] as String? ?? '',
        activeVercelId: json['activeVercelId'] as String? ?? '',
      );
    }
    // Migration from the single-token shape. The username is filled on first
    // test or use; the token itself is enough to authenticate.
    final accounts = <IntegrationAccount>[];
    final github = json['githubToken'] as String? ?? '';
    final vercel = json['vercelToken'] as String? ?? '';
    if (github.trim().isNotEmpty) {
      accounts.add(IntegrationAccount(
        id: 'github-1',
        kind: IntegrationKind.github,
        label: 'GitHub',
        username: '',
        token: github,
      ));
    }
    if (vercel.trim().isNotEmpty) {
      accounts.add(IntegrationAccount(
        id: 'vercel-1',
        kind: IntegrationKind.vercel,
        label: 'Vercel',
        username: '',
        token: vercel,
      ));
    }
    return Integrations(
      accounts: accounts,
      activeGithubId: accounts.isNotEmpty ? accounts.first.id : '',
      activeVercelId: accounts.length > 1 ? accounts.last.id : '',
    );
  }
}

enum ChatRole { user, assistant, tool, error, note }

/// A tool call that has been announced by the model but has not finished yet.
/// The transcript shows it as a live pill with a status verb.
class ToolDraft {
  const ToolDraft({
    required this.id,
    required this.tool,
    required this.detail,
    this.running = true,
  });

  final String id;
  final String tool;
  final String detail;
  final bool running;

  ToolDraft copyWith({bool? running}) => ToolDraft(
        id: id,
        tool: tool,
        detail: detail,
        running: running ?? this.running,
      );
}

class ChatEntry {
  const ChatEntry({
    required this.id,
    required this.role,
    required this.text,
    this.tool = '',
    this.detail = '',
    this.thinking = '',
    this.patch = '',
    this.added = 0,
    this.removed = 0,
    this.attachments = const [],
    this.ok = true,
    required this.at,
  });

  final String id;
  final ChatRole role;
  final String text;
  final String tool;
  final String detail;

  /// Reasoning the model returned alongside its answer. Hidden behind a pill
  /// so a long chain of thought never floods the conversation.
  final String thinking;

  /// JSON encoded [FileDiff] for a write_file call, plus its line counts.
  final String patch;
  final int added;
  final int removed;

  /// Project-relative paths of files the user attached to this message.
  final List<String> attachments;
  final bool ok;
  final DateTime at;

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'text': text,
        'tool': tool,
        'detail': detail,
        'thinking': thinking,
        'patch': patch,
        'added': added,
        'removed': removed,
        'attachments': attachments,
        'ok': ok,
        'at': at.toIso8601String(),
      };

  static ChatEntry fromJson(Map<String, dynamic> json) => ChatEntry(
        id: json['id'] as String,
        role: ChatRole.values.firstWhere(
          (r) => r.name == json['role'],
          orElse: () => ChatRole.assistant,
        ),
        text: json['text'] as String? ?? '',
        tool: json['tool'] as String? ?? '',
        detail: json['detail'] as String? ?? '',
        thinking: json['thinking'] as String? ?? '',
        patch: json['patch'] as String? ?? '',
        added: json['added'] as int? ?? 0,
        removed: json['removed'] as int? ?? 0,
        attachments: json['attachments'] is List
            ? (json['attachments'] as List).whereType<String>().toList()
            : const [],
        ok: json['ok'] as bool? ?? true,
        at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
      );
}

const kIndexHtml = '''<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Hello from Praxis</title>
  <link rel="stylesheet" href="style.css" />
</head>
<body>
  <main>
    <p class="eyebrow">PRAXIS PREVIEW</p>
    <h1>Your project runs<br />on your phone.</h1>
    <p class="lede">Edit these files in the Files tab, then refresh. The agent can change them too — ask it to.</p>
    <button id="tap">Tap me</button>
    <p id="count" class="count">0 taps</p>
  </main>
  <script src="app.js"></script>
</body>
</html>
''';

const kStyleCss = '''* { box-sizing: border-box; }
body {
  margin: 0;
  min-height: 100vh;
  display: grid;
  place-items: center;
  background: #0a0908;
  color: #f4efe9;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
}
main { width: min(90vw, 420px); }
.eyebrow { color: #e4693f; letter-spacing: 2px; font-size: 11px; font-weight: 700; }
h1 { font-size: 30px; line-height: 1.15; letter-spacing: -1px; margin: 10px 0 14px; }
.lede { color: #b7ada2; line-height: 1.6; font-size: 14px; }
button {
  margin-top: 14px; padding: 12px 20px; border-radius: 12px; border: 1px solid #e4693f;
  background: #e4693f; color: #1a0e08; font-weight: 700; font-size: 14px;
}
.count { color: #877e74; font-size: 13px; }
''';

const kAppJs = '''const button = document.getElementById('tap');
const count = document.getElementById('count');
let taps = 0;
button.addEventListener('click', () => {
  taps += 1;
  count.textContent = taps + (taps === 1 ? ' tap' : ' taps');
});
''';

const kDartMain = '''import 'package:flutter/material.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Hello from Praxis')),
        ),
      );
}
''';
