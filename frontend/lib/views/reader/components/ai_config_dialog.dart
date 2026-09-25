import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/ai_message_model.dart';
import '../../../providers/ai_provider.dart';

class AiConfigDialog extends StatefulWidget {
  const AiConfigDialog({super.key});

  @override
  State<AiConfigDialog> createState() => _AiConfigDialogState();
}

class _AiConfigDialogState extends State<AiConfigDialog> {
  late TextEditingController _baseUrlController;
  late TextEditingController _apiKeyController;
  late TextEditingController _modelController;
  late TextEditingController _systemPromptController;
  late double _temperature;
  bool _includePageContext = true;

  bool _obscureApiKey = true;
  bool _isTesting = false;
  String? _testResultMsg;
  bool? _testResultSuccess;

  bool _isFetchingModels = false;
  List<String> _availableModels = [];
  String? _selectedModel;
  String? _modelFetchMsg;
  bool? _modelFetchSuccess;
  bool _isCustomModelInput = false;

  bool _isAdvancedExpanded = false;

  @override
  void initState() {
    super.initState();
    final config = context.read<AiProvider>().config;
    _baseUrlController = TextEditingController(text: config.baseUrl);
    _apiKeyController = TextEditingController(text: config.apiKey);
    _modelController = TextEditingController(text: config.model);
    _selectedModel = config.model.trim().isNotEmpty ? config.model.trim() : null;
    _systemPromptController = TextEditingController(text: config.systemPrompt);
    _temperature = config.temperature;
    _includePageContext = config.includePageContext;

    if (_selectedModel != null && _selectedModel!.isNotEmpty) {
      _availableModels = [_selectedModel!];
    }
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _systemPromptController.dispose();
    super.dispose();
  }

  Future<void> _fetchModelList() async {
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();

    if (baseUrl.isEmpty) {
      setState(() {
        _modelFetchSuccess = false;
        _modelFetchMsg = '请先填写 API 基础地址 (Base URL)';
      });
      return;
    }

    setState(() {
      _isFetchingModels = true;
      _modelFetchMsg = null;
      _modelFetchSuccess = null;
    });

    final aiService = context.read<AiProvider>().aiService;
    final result = await aiService.fetchModelList(baseUrl: baseUrl, apiKey: apiKey);

    if (mounted) {
      setState(() {
        _isFetchingModels = false;
        _modelFetchSuccess = result.success;
        _modelFetchMsg = result.message;

        if (result.success && result.models.isNotEmpty) {
          _availableModels = result.models;
          _isCustomModelInput = false;

          // If current selection is in list, keep it; otherwise reset to null or first
          if (_selectedModel != null && !_availableModels.contains(_selectedModel)) {
            _availableModels.insert(0, _selectedModel!);
          }
        }
      });
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testResultMsg = null;
      _testResultSuccess = null;
    });

    final testConfig = AiConfig(
      baseUrl: _baseUrlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      model: _modelController.text.trim(),
      systemPrompt: _systemPromptController.text.trim(),
      temperature: _temperature,
      includePageContext: _includePageContext,
    );

    final aiService = context.read<AiProvider>().aiService;
    final result = await aiService.testConnection(testConfig);

    if (mounted) {
      setState(() {
        _isTesting = false;
        _testResultSuccess = result.success;
        _testResultMsg = result.message;
      });
    }
  }

  void _save() {
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    final model = _modelController.text.trim();

    if (baseUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 18),
              SizedBox(width: 8),
              Text('请填写 API 基础地址 (Base URL)'),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    // Validation: If API Key is provided but Model is empty, prevent saving and prompt user
    if (apiKey.isNotEmpty && model.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 18),
              SizedBox(width: 8),
              Text('已配置 API Key，请选择或输入要使用的 AI 模型'),
            ],
          ),
          backgroundColor: const Color(0xFFC2410C),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    final newConfig = AiConfig(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      systemPrompt: _systemPromptController.text.trim(),
      temperature: _temperature,
      includePageContext: _includePageContext,
    );

    context.read<AiProvider>().updateConfig(newConfig);
    Navigator.of(context).pop();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF86EFAC), size: 18),
            const SizedBox(width: 8),
            Text(model.isNotEmpty ? '已保存 AI 模型配置 ($model)' : '已保存 AI 配置'),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 20, 10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.auto_awesome_rounded, size: 20, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI 助手服务配置',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A),
                  ),
                ),
                Text(
                  '支持 DeepSeek 及任意 OpenAI 兼容的 API 端点',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            splashRadius: 18,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 580),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Base URL Input
              TextField(
                controller: _baseUrlController,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'API 基础地址 (Base URL)',
                  hintText: 'https://api.deepseek.com',
                  prefixIcon: const Icon(Icons.link_rounded, size: 18),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 14),

              // 2. API Key Input (Obscured with toggle)
              TextField(
                controller: _apiKeyController,
                obscureText: _obscureApiKey,
                style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  labelText: 'API Key',
                  hintText: 'sk-...',
                  prefixIcon: const Icon(Icons.key_rounded, size: 18),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureApiKey ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                      size: 18,
                    ),
                    onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
                  ),
                  helperText: '🔐 API Key 仅保存在本地客户端，绝不上传到服务器',
                  helperStyle: const TextStyle(fontSize: 11, color: Color(0xFF10B981)),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 14),

              // 3. Model Selector & "获取模型列表" Button
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Model Dropdown or Text input
                  Expanded(
                    child: _availableModels.isNotEmpty && !_isCustomModelInput
                        ? DropdownButtonFormField<String>(
                            initialValue: _availableModels.contains(_selectedModel) ? _selectedModel : null,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: '选择模型 (Model)',
                              hintText: '请选择模型...',
                              prefixIcon: const Icon(Icons.smart_toy_rounded, size: 18),
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            items: [
                              ..._availableModels.map((m) {
                                return DropdownMenuItem<String>(
                                  value: m,
                                  child: Text(
                                    m,
                                    style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }),
                            ],
                            onChanged: (val) {
                              setState(() {
                                _selectedModel = val;
                                _modelController.text = val ?? '';
                              });
                            },
                          )
                        : TextField(
                            controller: _modelController,
                            style: const TextStyle(fontSize: 13),
                            onChanged: (val) {
                              _selectedModel = val.trim();
                            },
                            decoration: InputDecoration(
                              labelText: '模型名称 (Model)',
                              hintText: '请选择模型...',
                              prefixIcon: const Icon(Icons.smart_toy_rounded, size: 18),
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                  ),
                  const SizedBox(width: 8),

                  // "获取模型列表" button
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                      foregroundColor: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    onPressed: _isFetchingModels ? null : _fetchModelList,
                    icon: _isFetchingModels
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_sync_rounded, size: 16, color: Color(0xFF6366F1)),
                    label: Text(
                      _isFetchingModels ? '获取中...' : '获取模型列表',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),

                  // Toggle custom input if models are loaded
                  if (_availableModels.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: _isCustomModelInput ? '切换为下拉选择' : '手动输入自定义模型',
                      icon: Icon(
                        _isCustomModelInput ? Icons.list_rounded : Icons.edit_note_rounded,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      onPressed: () {
                        setState(() {
                          _isCustomModelInput = !_isCustomModelInput;
                          if (!_isCustomModelInput && _selectedModel != null) {
                            _modelController.text = _selectedModel!;
                          }
                        });
                      },
                    ),
                  ],
                ],
              ),

              // Model fetch result banner
              if (_modelFetchMsg != null) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      Icon(
                        _modelFetchSuccess == true ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
                        size: 14,
                        color: _modelFetchSuccess == true ? const Color(0xFF10B981) : Colors.orangeAccent,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _modelFetchMsg!,
                          style: TextStyle(
                            fontSize: 11,
                            color: _modelFetchSuccess == true
                                ? (isDark ? const Color(0xFF86EFAC) : const Color(0xFF15803D))
                                : (isDark ? Colors.orange.shade300 : Colors.orange.shade800),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),

              // 4. Collapsible Advanced Settings (System Prompt & Temperature)
              Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.5) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InkWell(
                      onTap: () => setState(() => _isAdvancedExpanded = !_isAdvancedExpanded),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            Icon(Icons.tune_rounded, size: 18, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              '高级参数设置 (系统提示词 & 采样温度)',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
                              ),
                            ),
                            const Spacer(),
                            Icon(
                              _isAdvancedExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                              size: 20,
                              color: Colors.grey,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_isAdvancedExpanded) ...[
                      Divider(height: 1, color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // System Prompt
                            TextField(
                              controller: _systemPromptController,
                              maxLines: 3,
                              style: const TextStyle(fontSize: 12, height: 1.4),
                              decoration: InputDecoration(
                                labelText: '系统提示词 (System Prompt)',
                                alignLabelWithHint: true,
                                isDense: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Temperature Slider
                            Row(
                              children: [
                                Text(
                                  '采样温度 (Temperature): ${_temperature.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  _temperature <= 0.3 ? '严谨精准' : (_temperature >= 0.8 ? '发散创造' : '均衡适中'),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            Slider(
                              value: _temperature,
                              min: 0.0,
                              max: 1.5,
                              divisions: 15,
                              activeColor: const Color(0xFF6366F1),
                              onChanged: (val) => setState(() => _temperature = val),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // 5. Test Connection Result Banner
              if (_testResultMsg != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: (_testResultSuccess == true ? const Color(0xFF10B981) : Colors.red)
                        .withValues(alpha: isDark ? 0.2 : 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: (_testResultSuccess == true ? const Color(0xFF10B981) : Colors.red)
                          .withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _testResultSuccess == true ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                        size: 16,
                        color: _testResultSuccess == true ? const Color(0xFF10B981) : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _testResultMsg!,
                          style: TextStyle(
                            fontSize: 12,
                            color: _testResultSuccess == true
                                ? (isDark ? const Color(0xFF86EFAC) : const Color(0xFF15803D))
                                : Colors.red,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        // Test Connection Button
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _isTesting ? null : _testConnection,
          icon: _isTesting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.bolt_rounded, size: 16),
          label: Text(_isTesting ? '正在测试...' : '测试连接', style: const TextStyle(fontSize: 12)),
        ),
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF6366F1),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _save,
          icon: const Icon(Icons.save_rounded, size: 16),
          label: const Text('保存配置', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ),
      ],
    );
  }
}
