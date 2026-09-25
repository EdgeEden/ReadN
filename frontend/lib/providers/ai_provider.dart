import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/ai_message_model.dart';
import '../services/ai_service.dart';
import '../services/storage_service.dart';

class AiProvider extends ChangeNotifier {
  final StorageService storageService;
  final AiService aiService;
  final Uuid _uuid = const Uuid();

  AiConfig _config;
  final List<ChatMessage> _messages = [];
  bool _isGenerating = false;
  String? _pendingQuotedText;
  int? _pendingQuotedPage;
  StreamSubscription<AiStreamChunk>? _currentStreamSubscription;

  AiProvider({
    required this.storageService,
    AiService? aiService,
  })  : aiService = aiService ?? AiService(),
        _config = AiConfig(
          baseUrl: storageService.getAiBaseUrl(),
          apiKey: storageService.getAiApiKey(),
          model: storageService.getAiModel(),
          systemPrompt: storageService.getAiSystemPrompt(),
          temperature: storageService.getAiTemperature(),
          includePageContext: storageService.getAiIncludeContext(),
        );

  AiConfig get config => _config;
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isGenerating => _isGenerating;
  String? get pendingQuotedText => _pendingQuotedText;
  int? get pendingQuotedPage => _pendingQuotedPage;
  bool get hasPendingQuote => _pendingQuotedText != null && _pendingQuotedText!.trim().isNotEmpty;
  bool get isConfigured => _config.hasValidKey || _config.baseUrl.contains('localhost') || _config.baseUrl.contains('127.0.0.1');

  void setPendingQuote(String quote, {int? pageNumber}) {
    _pendingQuotedText = quote.trim();
    _pendingQuotedPage = pageNumber;
    notifyListeners();
  }

  void clearPendingQuote() {
    _pendingQuotedText = null;
    _pendingQuotedPage = null;
    notifyListeners();
  }

  void setIncludePageContext(bool val) {
    _config = _config.copyWith(includePageContext: val);
    storageService.setAiIncludeContext(val);
    notifyListeners();
  }

  Future<void> updateConfig(AiConfig newConfig) async {
    _config = newConfig;
    await storageService.setAiBaseUrl(newConfig.baseUrl);
    await storageService.setAiApiKey(newConfig.apiKey);
    await storageService.setAiModel(newConfig.model);
    await storageService.setAiSystemPrompt(newConfig.systemPrompt);
    await storageService.setAiTemperature(newConfig.temperature);
    await storageService.setAiIncludeContext(newConfig.includePageContext);
    notifyListeners();
  }

  void toggleThinkingExpanded(String messageId) {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx != -1) {
      _messages[idx].isThinkingExpanded = !_messages[idx].isThinkingExpanded;
      notifyListeners();
    }
  }

  void clearHistory() {
    stopGeneration();
    _messages.clear();
    _pendingQuotedText = null;
    _pendingQuotedPage = null;
    notifyListeners();
  }

  void stopGeneration() {
    if (_isGenerating) {
      _currentStreamSubscription?.cancel();
      _currentStreamSubscription = null;
      aiService.cancelStream();
      _isGenerating = false;

      if (_messages.isNotEmpty && _messages.last.isAssistant && _messages.last.isStreaming) {
        _messages.last.isStreaming = false;
        _messages.last.isThinking = false;
      }
      notifyListeners();
    }
  }

  Future<void> sendMessage(
    String prompt, {
    String? pageContextText,
    String? documentTitle,
  }) async {
    if (prompt.trim().isEmpty && !hasPendingQuote) return;
    if (_isGenerating) stopGeneration();

    final userQuote = _pendingQuotedText;
    final userPage = _pendingQuotedPage;

    // Clear pending quote once consumed
    _pendingQuotedText = null;
    _pendingQuotedPage = null;

    final userMessage = ChatMessage(
      id: _uuid.v4(),
      role: 'user',
      content: prompt.trim().isNotEmpty ? prompt.trim() : '请详细解析并说明此引文内容。',
      quotedText: userQuote,
      pageNumber: userPage,
    );

    final assistantMessageId = _uuid.v4();
    final assistantMessage = ChatMessage(
      id: assistantMessageId,
      role: 'assistant',
      content: '',
      isStreaming: true,
      isThinking: false,
      isThinkingExpanded: true,
    );

    _messages.add(userMessage);
    _messages.add(assistantMessage);
    _isGenerating = true;
    notifyListeners();

    final thinkStopwatch = Stopwatch();
    bool hasStartedFormalAnswer = false;

    try {
      final stream = aiService.streamChat(
        config: _config,
        history: _messages.sublist(0, _messages.length - 1),
        currentPrompt: userMessage.content,
        quotedText: userQuote,
        pageNumber: userPage,
        pageContextText: pageContextText,
        documentTitle: documentTitle,
      );

      _currentStreamSubscription = stream.listen(
        (chunk) {
          if (chunk.error != null) {
            assistantMessage.error = chunk.error;
            assistantMessage.isStreaming = false;
            assistantMessage.isThinking = false;
            _isGenerating = false;
            notifyListeners();
            return;
          }

          // 1. Thinking / Reasoning chunks
          if (chunk.reasoningDelta != null && chunk.reasoningDelta!.isNotEmpty) {
            if (!thinkStopwatch.isRunning) {
              thinkStopwatch.start();
              assistantMessage.isThinking = true;
              assistantMessage.isThinkingExpanded = true;
            }
            assistantMessage.thinkingContent = (assistantMessage.thinkingContent ?? '') + chunk.reasoningDelta!;
            notifyListeners();
          }

          // 2. Formal answer content chunks
          if (chunk.contentDelta != null && chunk.contentDelta!.isNotEmpty) {
            if (!hasStartedFormalAnswer) {
              hasStartedFormalAnswer = true;
              if (thinkStopwatch.isRunning) {
                thinkStopwatch.stop();
                assistantMessage.thinkingDurationMs = thinkStopwatch.elapsedMilliseconds;
              }
              // Auto-fold the thinking block once the real answer starts streaming!
              assistantMessage.isThinking = false;
              assistantMessage.isThinkingExpanded = false;
            }
            assistantMessage.content += chunk.contentDelta!;
            notifyListeners();
          }

          if (chunk.isDone) {
            if (thinkStopwatch.isRunning) {
              thinkStopwatch.stop();
              assistantMessage.thinkingDurationMs = thinkStopwatch.elapsedMilliseconds;
            }
            assistantMessage.isStreaming = false;
            assistantMessage.isThinking = false;
            if (assistantMessage.content.isNotEmpty) {
              assistantMessage.isThinkingExpanded = false;
            }
            _isGenerating = false;
            notifyListeners();
          }
        },
        onError: (err) {
          assistantMessage.error = '传输中断: $err';
          assistantMessage.isStreaming = false;
          assistantMessage.isThinking = false;
          _isGenerating = false;
          notifyListeners();
        },
        onDone: () {
          assistantMessage.isStreaming = false;
          assistantMessage.isThinking = false;
          _isGenerating = false;
          notifyListeners();
        },
      );
    } catch (e) {
      assistantMessage.error = '发送失败: $e';
      assistantMessage.isStreaming = false;
      assistantMessage.isThinking = false;
      _isGenerating = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _currentStreamSubscription?.cancel();
    aiService.cancelStream();
    super.dispose();
  }
}

