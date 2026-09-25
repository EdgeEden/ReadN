/// Model representing a single chat message in the AI assistant conversation.
class ChatMessage {
  final String id;
  final String role; // 'user' | 'assistant' | 'system'
  String content;
  final String? quotedText;
  final int? pageNumber;
  String? thinkingContent;
  bool isThinking;
  bool isThinkingExpanded;
  int? thinkingDurationMs;
  bool isStreaming;
  String? error;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.quotedText,
    this.pageNumber,
    this.thinkingContent,
    this.isThinking = false,
    this.isThinkingExpanded = false,
    this.thinkingDurationMs,
    this.isStreaming = false,
    this.error,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';
  bool get isSystem => role == 'system';
  bool get hasThinking => thinkingContent != null && thinkingContent!.trim().isNotEmpty;
  bool get hasQuote => quotedText != null && quotedText!.trim().isNotEmpty;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role,
      'content': content,
      'quotedText': quotedText,
      'pageNumber': pageNumber,
      'thinkingContent': thinkingContent,
      'thinkingDurationMs': thinkingDurationMs,
      'error': error,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      role: json['role'] as String,
      content: json['content'] as String? ?? '',
      quotedText: json['quotedText'] as String?,
      pageNumber: json['pageNumber'] as int?,
      thinkingContent: json['thinkingContent'] as String?,
      thinkingDurationMs: json['thinkingDurationMs'] as int?,
      error: json['error'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

/// Pre-configured AI Provider Presets
class AiProviderPreset {
  final String name;
  final String label;
  final String baseUrl;
  final List<String> recommendedModels;
  final String defaultModel;
  final String description;

  const AiProviderPreset({
    required this.name,
    required this.label,
    required this.baseUrl,
    required this.recommendedModels,
    required this.defaultModel,
    required this.description,
  });
}

/// Global AI Configuration Model (stored strictly in local storage)
class AiConfig {
  final String baseUrl;
  final String apiKey;
  final String model;
  final String systemPrompt;
  final double temperature;
  final bool includePageContext;

  const AiConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.systemPrompt,
    this.temperature = 0.6,
    this.includePageContext = true,
  });

  bool get hasValidKey => apiKey.trim().isNotEmpty;

  AiConfig copyWith({
    String? baseUrl,
    String? apiKey,
    String? model,
    String? systemPrompt,
    double? temperature,
    bool? includePageContext,
  }) {
    return AiConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      temperature: temperature ?? this.temperature,
      includePageContext: includePageContext ?? this.includePageContext,
    );
  }

  static const List<AiProviderPreset> presets = [
    AiProviderPreset(
      name: 'deepseek',
      label: 'DeepSeek (官方)',
      baseUrl: 'https://api.deepseek.com',
      defaultModel: 'deepseek-chat',
      recommendedModels: [
        'deepseek-chat',
        'deepseek-reasoner',
      ],
      description: '深度求索 DeepSeek-V3 / DeepSeek-R1 深度推理大模型',
    ),
    AiProviderPreset(
      name: 'siliconflow',
      label: '硅基流动 (SiliconFlow)',
      baseUrl: 'https://api.siliconflow.cn/v1',
      defaultModel: 'deepseek-ai/DeepSeek-V3',
      recommendedModels: [
        'deepseek-ai/DeepSeek-V3',
        'deepseek-ai/DeepSeek-R1',
        'Qwen/Qwen2.5-72B-Instruct',
        'THUDM/glm-4-9b-chat',
      ],
      description: '国内高速云端模型 API 聚合加速',
    ),
    AiProviderPreset(
      name: 'openai',
      label: 'OpenAI (官方)',
      baseUrl: 'https://api.openai.com/v1',
      defaultModel: 'gpt-4o-mini',
      recommendedModels: [
        'gpt-4o',
        'gpt-4o-mini',
        'o1-mini',
        'o3-mini',
      ],
      description: 'GPT-4o 与 OpenAI o系列推理模型',
    ),
    AiProviderPreset(
      name: 'moonshot',
      label: '月之暗面 (Moonshot Kimi)',
      baseUrl: 'https://api.moonshot.cn/v1',
      defaultModel: 'moonshot-v1-8k',
      recommendedModels: [
        'moonshot-v1-8k',
        'moonshot-v1-32k',
        'moonshot-v1-128k',
      ],
      description: '超长上下文中文学术理解与文献总结',
    ),
    AiProviderPreset(
      name: 'ollama',
      label: '本地 Ollama / LM Studio',
      baseUrl: 'http://localhost:11434/v1',
      defaultModel: 'deepseek-r1:latest',
      recommendedModels: [
        'deepseek-r1:latest',
        'llama3.1:latest',
        'qwen2.5:latest',
      ],
      description: '完全本地运行的开源模型，零 API 费用',
    ),
  ];
}
