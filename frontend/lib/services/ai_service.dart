import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/ai_message_model.dart';

/// Chunk of text or reasoning stream received from the AI model
class AiStreamChunk {
  final String? contentDelta;
  final String? reasoningDelta;
  final bool isDone;
  final String? error;

  const AiStreamChunk({
    this.contentDelta,
    this.reasoningDelta,
    this.isDone = false,
    this.error,
  });
}

class AiService {
  http.Client? _activeClient;

  static String normalizeEndpoint(String baseUrl) {
    var clean = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (clean.endsWith('/chat/completions')) {
      return clean;
    }
    if (clean.endsWith('/v1')) {
      return '$clean/chat/completions';
    }
    return '$clean/chat/completions';
  }

  /// Cancels any in-flight stream generation
  void cancelStream() {
    _activeClient?.close();
    _activeClient = null;
  }

  /// Fetches available model list from the OpenAI/DeepSeek-compatible /models endpoint
  Future<({bool success, List<String> models, String message})> fetchModelList({
    required String baseUrl,
    required String apiKey,
  }) async {
    final cleanBase = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (cleanBase.isEmpty) {
      return (success: false, models: <String>[], message: '请先填写 API 基础地址 (Base URL)');
    }

    var base = cleanBase;
    if (base.endsWith('/chat/completions')) {
      base = base.substring(0, base.length - '/chat/completions'.length).replaceAll(RegExp(r'/+$'), '');
    }

    final candidateEndpoints = <String>[];
    if (base.endsWith('/v1')) {
      candidateEndpoints.add('$base/models');
      final withoutV1 = base.substring(0, base.length - 3).replaceAll(RegExp(r'/+$'), '');
      if (withoutV1.isNotEmpty) {
        candidateEndpoints.add('$withoutV1/models');
      }
    } else {
      candidateEndpoints.add('$base/models');
      candidateEndpoints.add('$base/v1/models');
    }

    final client = http.Client();
    final headers = <String, String>{
      'Accept': 'application/json',
    };
    if (apiKey.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${apiKey.trim()}';
    }

    String lastError = '未知错误';

    try {
      for (final endpoint in candidateEndpoints) {
        try {
          final response = await client
              .get(Uri.parse(endpoint), headers: headers)
              .timeout(const Duration(seconds: 12));

          if (response.statusCode >= 200 && response.statusCode < 300) {
            final dynamic json = jsonDecode(response.body);
            final List<String> modelList = [];

            if (json is Map && json['data'] is List) {
              for (final item in json['data']) {
                if (item is Map && item['id'] != null) {
                  final idStr = item['id'].toString().trim();
                  if (idStr.isNotEmpty && !modelList.contains(idStr)) {
                    modelList.add(idStr);
                  }
                } else if (item is String && item.trim().isNotEmpty && !modelList.contains(item.trim())) {
                  modelList.add(item.trim());
                }
              }
            } else if (json is List) {
              for (final item in json) {
                if (item is Map && item['id'] != null) {
                  final idStr = item['id'].toString().trim();
                  if (idStr.isNotEmpty && !modelList.contains(idStr)) {
                    modelList.add(idStr);
                  }
                } else if (item is String && item.trim().isNotEmpty && !modelList.contains(item.trim())) {
                  modelList.add(item.trim());
                }
              }
            }

            if (modelList.isNotEmpty) {
              modelList.sort((a, b) => a.compareTo(b));
              return (
                success: true,
                models: modelList,
                message: '成功获取 ${modelList.length} 个可用模型',
              );
            } else {
              return (
                success: true,
                models: <String>[],
                message: '接口连接正常，但未返回模型列表',
              );
            }
          } else {
            try {
              final errJson = jsonDecode(response.body);
              if (errJson is Map && errJson.containsKey('error')) {
                final err = errJson['error'];
                if (err is Map && err.containsKey('message')) {
                  lastError = err['message'].toString();
                } else {
                  lastError = err.toString();
                }
              } else {
                lastError = 'HTTP ${response.statusCode}';
              }
            } catch (_) {
              lastError = 'HTTP ${response.statusCode}: ${response.body}';
            }
          }
        } catch (e) {
          lastError = e.toString();
        }
      }

      return (
        success: false,
        models: <String>[],
        message: '获取模型列表失败: $lastError',
      );
    } finally {
      client.close();
    }
  }

  /// Tests the API connection with the provided configuration
  Future<({bool success, String message})> testConnection(AiConfig config) async {
    if (!config.hasValidKey && !config.baseUrl.contains('localhost') && !config.baseUrl.contains('127.0.0.1')) {
      return (success: false, message: '请先填写 API Key');
    }

    final endpoint = normalizeEndpoint(config.baseUrl);
    final client = http.Client();

    try {
      final headers = <String, String>{
        'Content-Type': 'application/json; charset=utf-8',
      };
      if (config.apiKey.trim().isNotEmpty) {
        headers['Authorization'] = 'Bearer ${config.apiKey.trim()}';
      }

      final body = jsonEncode({
        'model': config.model,
        'messages': [
          {'role': 'user', 'content': 'Hello'},
        ],
        'max_tokens': 10,
        'temperature': 0.1,
      });

      final response = await client
          .post(
            Uri.parse(endpoint),
            headers: headers,
            body: body,
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return (success: true, message: '连接成功！模型响应正常 (${response.statusCode})');
      } else {
        String errMsg = 'HTTP ${response.statusCode}';
        try {
          final errJson = jsonDecode(response.body);
          if (errJson is Map && errJson.containsKey('error')) {
            final err = errJson['error'];
            if (err is Map && err.containsKey('message')) {
              errMsg = err['message'].toString();
            } else {
              errMsg = err.toString();
            }
          }
        } catch (_) {
          errMsg = response.body.isNotEmpty ? response.body : errMsg;
        }
        return (success: false, message: 'API 返回错误: $errMsg');
      }
    } catch (e) {
      return (success: false, message: '连接失败: $e');
    } finally {
      client.close();
    }
  }

  /// Streams chat completions using Server-Sent Events (SSE)
  Stream<AiStreamChunk> streamChat({
    required AiConfig config,
    required List<ChatMessage> history,
    required String currentPrompt,
    String? quotedText,
    int? pageNumber,
    String? pageContextText,
    String? documentTitle,
  }) async* {
    if (!config.hasValidKey && !config.baseUrl.contains('localhost') && !config.baseUrl.contains('127.0.0.1')) {
      yield const AiStreamChunk(
        error: '未配置 API Key。请点击右上角设置图标填写 DeepSeek 或 OpenAI 兼容 API Key。',
        isDone: true,
      );
      return;
    }

    final endpoint = normalizeEndpoint(config.baseUrl);
    _activeClient?.close();
    final client = http.Client();
    _activeClient = client;

    // Construct full system prompt
    final systemPrompt = StringBuffer(config.systemPrompt);
    if (documentTitle != null && documentTitle.isNotEmpty) {
      systemPrompt.write('\n\n【当前阅读文档】: 《$documentTitle》');
    }

    // Construct API messages array
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': systemPrompt.toString()},
    ];

    // Append prior history (excluding errors or empty responses)
    for (final msg in history) {
      if (msg.isSystem || msg.error != null) continue;
      if (msg.content.trim().isEmpty && (msg.thinkingContent == null || msg.thinkingContent!.isEmpty)) continue;

      if (msg.isUser) {
        final sb = StringBuffer();
        if (msg.quotedText != null && msg.quotedText!.trim().isNotEmpty) {
          sb.writeln('【引用的段落/公式 (第 ${msg.pageNumber ?? "?"} 页)】:');
          sb.writeln('```');
          sb.writeln(msg.quotedText!.trim());
          sb.writeln('```');
          sb.writeln();
        }
        sb.write(msg.content);
        messages.add({'role': 'user', 'content': sb.toString()});
      } else if (msg.isAssistant) {
        messages.add({'role': 'assistant', 'content': msg.content});
      }
    }

    // Construct current user prompt with quote and page context
    final userPromptBuffer = StringBuffer();
    if (quotedText != null && quotedText.trim().isNotEmpty) {
      userPromptBuffer.writeln('【引用的文本/公式 (第 ${pageNumber ?? "?"} 页)】:');
      userPromptBuffer.writeln('```');
      userPromptBuffer.writeln(quotedText.trim());
      userPromptBuffer.writeln('```');
      userPromptBuffer.writeln();
    }

    if (config.includePageContext && pageContextText != null && pageContextText.trim().isNotEmpty) {
      userPromptBuffer.writeln('【所在页面（第 ${pageNumber ?? "?"} 页）完整上下文参考】:');
      userPromptBuffer.writeln('```');
      userPromptBuffer.writeln(pageContextText.trim());
      userPromptBuffer.writeln('```');
      userPromptBuffer.writeln();
    }

    userPromptBuffer.write(currentPrompt.trim());
    messages.add({'role': 'user', 'content': userPromptBuffer.toString()});

    final requestBody = {
      'model': config.model,
      'messages': messages,
      'stream': true,
      'temperature': config.temperature,
    };

    try {
      final request = http.Request('POST', Uri.parse(endpoint));
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      if (config.apiKey.trim().isNotEmpty) {
        request.headers['Authorization'] = 'Bearer ${config.apiKey.trim()}';
      }
      request.body = jsonEncode(requestBody);

      final streamedResponse = await client.send(request);

      if (streamedResponse.statusCode != 200) {
        final errorText = await streamedResponse.stream.bytesToString();
        String parsedMsg = 'HTTP ${streamedResponse.statusCode}';
        try {
          final errJson = jsonDecode(errorText);
          if (errJson is Map && errJson.containsKey('error')) {
            final err = errJson['error'];
            if (err is Map && err.containsKey('message')) {
              parsedMsg = err['message'].toString();
            } else {
              parsedMsg = err.toString();
            }
          }
        } catch (_) {
          parsedMsg = errorText.isNotEmpty ? errorText : parsedMsg;
        }
        yield AiStreamChunk(error: 'API 错误 ($parsedMsg)', isDone: true);
        return;
      }

      bool insideThinkTag = false;

      await for (final line in streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || !trimmed.startsWith('data:')) continue;

        final jsonStr = trimmed.substring(5).trim();
        if (jsonStr == '[DONE]') {
          yield const AiStreamChunk(isDone: true);
          break;
        }

        try {
          final data = jsonDecode(jsonStr);
          if (data is! Map) continue;

          final choices = data['choices'] as List?;
          if (choices == null || choices.isEmpty) continue;

          final delta = choices[0]['delta'] as Map<String, dynamic>?;
          if (delta == null) continue;

          // 1. Direct reasoning_content (DeepSeek-R1, SiliconFlow, OpenAI o-series)
          final reasoningChunk = delta['reasoning_content'] as String?;
          final contentChunk = delta['content'] as String?;

          if (reasoningChunk != null && reasoningChunk.isNotEmpty) {
            yield AiStreamChunk(reasoningDelta: reasoningChunk);
          }

          // 2. Handle <think>...</think> tags if present in content
          if (contentChunk != null && contentChunk.isNotEmpty) {
            var raw = contentChunk;

            if (!insideThinkTag && raw.contains('<think>')) {
              insideThinkTag = true;
              final parts = raw.split('<think>');
              if (parts[0].isNotEmpty) {
                yield AiStreamChunk(contentDelta: parts[0]);
              }
              raw = parts.length > 1 ? parts[1] : '';
            }

            if (insideThinkTag) {
              if (raw.contains('</think>')) {
                insideThinkTag = false;
                final parts = raw.split('</think>');
                if (parts[0].isNotEmpty) {
                  yield AiStreamChunk(reasoningDelta: parts[0]);
                }
                if (parts.length > 1 && parts[1].isNotEmpty) {
                  yield AiStreamChunk(contentDelta: parts[1]);
                }
              } else {
                if (raw.isNotEmpty) {
                  yield AiStreamChunk(reasoningDelta: raw);
                }
              }
            } else {
              if (raw.isNotEmpty) {
                yield AiStreamChunk(contentDelta: raw);
              }
            }
          }
        } catch (e) {
          debugPrint('Error parsing SSE json chunk: $e');
        }
      }

      yield const AiStreamChunk(isDone: true);
    } catch (e) {
      if (e is http.ClientException || e.toString().contains('Connection closed')) {
        // Normal cancellation or disconnect
        yield const AiStreamChunk(isDone: true);
      } else {
        yield AiStreamChunk(error: '请求异常: $e', isDone: true);
      }
    } finally {
      if (_activeClient == client) {
        _activeClient = null;
      }
      client.close();
    }
  }
}

