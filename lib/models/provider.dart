enum ProviderGroup { builtin, own, local }

class AiProvider {
  const AiProvider({
    required this.id,
    required this.name,
    required this.icon,
    required this.detail,
    required this.group,
  });

  final String id;
  final String name;

  /// Bundled SVG from the APK's assets/icons set.
  final String icon;
  final String detail;
  final ProviderGroup group;
}

const kProviders = <AiProvider>[
  AiProvider(
    id: 'polydev',
    name: 'PolyDev AI',
    icon: 'assets/icons/polydev.svg',
    detail: 'Built-in · included with Pro',
    group: ProviderGroup.builtin,
  ),
  AiProvider(
    id: 'openai',
    name: 'OpenAI',
    icon: 'assets/icons/openai.svg',
    detail: 'Your key · sk-…',
    group: ProviderGroup.own,
  ),
  AiProvider(
    id: 'anthropic',
    name: 'Anthropic',
    icon: 'assets/icons/claude.svg',
    detail: 'Your key · Claude 4 Sonnet',
    group: ProviderGroup.own,
  ),
  AiProvider(
    id: 'gemini',
    name: 'Google Gemini',
    icon: 'assets/icons/gemini.svg',
    detail: 'Your key · 2.5 Pro',
    group: ProviderGroup.own,
  ),
  AiProvider(
    id: 'openrouter',
    name: 'OpenRouter',
    icon: 'assets/icons/openrouter.svg',
    detail: 'Your key · 300+ models',
    group: ProviderGroup.own,
  ),
  AiProvider(
    id: 'groq',
    name: 'Groq',
    icon: 'assets/icons/groq.svg',
    detail: 'Your key · fast inference',
    group: ProviderGroup.own,
  ),
  AiProvider(
    id: 'deepseek',
    name: 'DeepSeek',
    icon: 'assets/icons/deepseek.svg',
    detail: 'Your key · V3',
    group: ProviderGroup.own,
  ),
  AiProvider(
    id: 'mistral',
    name: 'Mistral',
    icon: 'assets/icons/mistral.svg',
    detail: 'Your key · Codestral',
    group: ProviderGroup.own,
  ),
  AiProvider(
    id: 'cerebras',
    name: 'Cerebras',
    icon: 'assets/icons/cerebras.svg',
    detail: 'Your key · wafer-scale',
    group: ProviderGroup.own,
  ),
  AiProvider(
    id: 'cohere',
    name: 'Cohere',
    icon: 'assets/icons/cohere.svg',
    detail: 'Your key · Command A',
    group: ProviderGroup.own,
  ),
  AiProvider(
    id: 'qwen',
    name: 'Qwen',
    icon: 'assets/icons/qwen.svg',
    detail: 'Your key · Qwen3 Coder',
    group: ProviderGroup.own,
  ),
  AiProvider(
    id: 'moonshot',
    name: 'Moonshot',
    icon: 'assets/icons/moonshot.svg',
    detail: 'Your key · Kimi K2',
    group: ProviderGroup.own,
  ),
  AiProvider(
    id: 'minimax',
    name: 'MiniMax',
    icon: 'assets/icons/minimax.svg',
    detail: 'Your key · M2',
    group: ProviderGroup.own,
  ),
  AiProvider(
    id: 'nvidia',
    name: 'NVIDIA',
    icon: 'assets/icons/nvidia.svg',
    detail: 'Your key · NIM',
    group: ProviderGroup.own,
  ),
  AiProvider(
    id: 'huggingface',
    name: 'Hugging Face',
    icon: 'assets/icons/huggingface.svg',
    detail: 'Your key · Inference API',
    group: ProviderGroup.own,
  ),
  AiProvider(
    id: 'siliconflow',
    name: 'SiliconFlow',
    icon: 'assets/icons/siliconflow.svg',
    detail: 'Your key · China region',
    group: ProviderGroup.own,
  ),
  AiProvider(
    id: 'yi',
    name: '01.AI Yi',
    icon: 'assets/icons/yi.svg',
    detail: 'Your key · Yi-Lightning',
    group: ProviderGroup.own,
  ),
  AiProvider(
    id: 'baichuan',
    name: 'Baichuan',
    icon: 'assets/icons/baichuan.svg',
    detail: 'Your key',
    group: ProviderGroup.own,
  ),
  AiProvider(
    id: 'gemma',
    name: 'Gemma',
    icon: 'assets/icons/gemma.svg',
    detail: 'Your key · via Google AI',
    group: ProviderGroup.own,
  ),
  AiProvider(
    id: 'meta',
    name: 'Llama',
    icon: 'assets/icons/meta.svg',
    detail: 'Your key · via provider',
    group: ProviderGroup.own,
  ),
  AiProvider(
    id: 'opencode',
    name: 'OpenCode',
    icon: 'assets/icons/opencode.svg',
    detail: 'Your key',
    group: ProviderGroup.own,
  ),
  AiProvider(
    id: 'freeai',
    name: 'FreeAI',
    icon: 'assets/icons/freeai.svg',
    detail: 'Your key · community endpoint',
    group: ProviderGroup.own,
  ),
  AiProvider(
    id: 'agnesai',
    name: 'Agnes AI',
    icon: 'assets/icons/agnesai.svg',
    detail: 'Your key',
    group: ProviderGroup.own,
  ),
  AiProvider(
    id: 'ollama',
    name: 'Ollama',
    icon: 'assets/icons/ollama.svg',
    detail: 'Local · localhost:11434',
    group: ProviderGroup.local,
  ),
];
