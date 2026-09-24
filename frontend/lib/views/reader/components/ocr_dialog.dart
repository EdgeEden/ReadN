import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/document_model.dart';
import '../../../providers/document_provider.dart';

class OcrDialog extends StatefulWidget {
  final DocumentModel document;
  final int currentPage;
  final VoidCallback onOcrCompleted;
  final VoidCallback? onOcrStarted;

  const OcrDialog({
    super.key,
    required this.document,
    this.currentPage = 1,
    required this.onOcrCompleted,
    this.onOcrStarted,
  });

  @override
  State<OcrDialog> createState() => _OcrDialogState();
}

class _OcrDialogState extends State<OcrDialog> {
  String _selectedEngine = "adobe"; // "adobe" | "rapidocr" | "paddleocr_vl"
  String _pageScope = "current"; // "current" | "all" | "custom"
  late TextEditingController _customPagesController;
  
  // Adobe configuration
  late TextEditingController _adobeClientIdController;
  late TextEditingController _adobeClientSecretController;
  String _adobeLocale = "zh-CN";
  final String _adobeType = "searchable_image_exact";
  bool _showAdobeConfig = false;

  // Baidu configuration
  late TextEditingController _apiTokenController;
  bool _useDocOrientationClassify = false;
  bool _useDocUnwarping = false;
  bool _useChartRecognition = false;
  bool _showBaiduConfig = false;

  bool _isProcessing = false;
  double _progress = 0.0;
  int _currentRecognizedPage = 0;
  int _totalTargetPages = 0;
  String _statusMessage = "";
  String? _errorMessage;
  Timer? _pollTimer;

  static const String _defaultAdobeClientId = "REDACTED_ADOBE_CLIENT_ID";
  static const String _defaultAdobeClientSecret = "REDACTED_ADOBE_CLIENT_SECRET";
  static const String _defaultBaiduToken = "REDACTED_BAIDU_TOKEN";

  @override
  void initState() {
    super.initState();
    // If document has no text layer at all, default to recognizing all pages
    if (!widget.document.hasTextLayer) {
      _pageScope = "all";
    } else {
      _pageScope = "current";
    }

    _customPagesController = TextEditingController(text: "${widget.currentPage}");
    _adobeClientIdController = TextEditingController(text: _defaultAdobeClientId);
    _adobeClientSecretController = TextEditingController(text: _defaultAdobeClientSecret);
    _apiTokenController = TextEditingController(text: _defaultBaiduToken);

    if (widget.document.ocrStatus == "processing") {
      _isProcessing = true;
      _progress = 0.1;
      _statusMessage = "OCR 处理中...";
      _startPolling();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _customPagesController.dispose();
    _adobeClientIdController.dispose();
    _adobeClientSecretController.dispose();
    _apiTokenController.dispose();
    super.dispose();
  }

  List<int>? _parseTargetPages() {
    if (_pageScope == "all") {
      return null;
    }
    if (_pageScope == "current") {
      return [widget.currentPage.clamp(1, max(1, widget.document.pageCount))];
    }
    
    // Parse custom range e.g. "1, 3, 5-8"
    final text = _customPagesController.text.trim();
    if (text.isEmpty) return [widget.currentPage];

    final Set<int> pages = {};
    final parts = text.split(RegExp(r'[,，\s]+'));
    final maxP = max(1, widget.document.pageCount);

    for (final part in parts) {
      if (part.contains('-')) {
        final sub = part.split('-');
        if (sub.length == 2) {
          final start = int.tryParse(sub[0].trim());
          final end = int.tryParse(sub[1].trim());
          if (start != null && end != null) {
            for (int p = min(start, end); p <= max(start, end); p++) {
              if (p >= 1 && p <= maxP) pages.add(p);
            }
          }
        }
      } else {
        final p = int.tryParse(part.trim());
        if (p != null && p >= 1 && p <= maxP) {
          pages.add(p);
        }
      }
    }

    if (pages.isEmpty) {
      return [widget.currentPage.clamp(1, maxP)];
    }
    return pages.toList()..sort();
  }

  void _startOcr() async {
    final targets = _parseTargetPages();
    final targetCount = targets?.length ?? widget.document.pageCount;

    String initialMsg = "正在启动 OCR 处理...";
    if (_selectedEngine == "adobe") {
      initialMsg = "正在连接 Adobe PDF Services 云端官方引擎...";
    } else if (_selectedEngine == "paddleocr_vl") {
      initialMsg = "正在连接百度 AI Studio PaddleOCR-VL API...";
    } else {
      initialMsg = "正在启动本地 RapidOCR 引擎...";
    }

    setState(() {
      _isProcessing = true;
      _progress = 0.05;
      _totalTargetPages = targetCount;
      _currentRecognizedPage = 0;
      _statusMessage = initialMsg;
      _errorMessage = null;
    });

    widget.onOcrStarted?.call();

    final docProvider = context.read<DocumentProvider>();
    final success = await docProvider.triggerOcr(
      widget.document.id,
      engine: _selectedEngine,
      adobeClientId: _adobeClientIdController.text.trim().isNotEmpty ? _adobeClientIdController.text.trim() : _defaultAdobeClientId,
      adobeClientSecret: _adobeClientSecretController.text.trim().isNotEmpty ? _adobeClientSecretController.text.trim() : _defaultAdobeClientSecret,
      adobeLocale: _adobeLocale,
      adobeType: _adobeType,
      apiToken: _apiTokenController.text.trim().isNotEmpty ? _apiTokenController.text.trim() : _defaultBaiduToken,
      pageScope: _pageScope,
      targetPages: targets,
      languages: "chi_sim+eng+equ",
      useDocOrientationClassify: _useDocOrientationClassify,
      useDocUnwarping: _useDocUnwarping,
      useChartRecognition: _useChartRecognition,
    );

    if (!success) {
      setState(() {
        _isProcessing = false;
        _errorMessage = docProvider.errorMessage ?? "启动 OCR 失败，请检查网络或配置状态";
      });
      return;
    }

    _startPolling();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    final docProvider = context.read<DocumentProvider>();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 800), (timer) async {
      final res = await docProvider.checkOcrProgress(widget.document.id);
      final status = res['status'] as String? ?? "none";
      final prog = (res['progress'] as num?)?.toDouble() ?? 0.0;
      final currP = (res['current_page'] as num?)?.toInt() ?? 0;
      final totalP = (res['total_pages'] as num?)?.toInt() ?? _totalTargetPages;
      final msg = res['message'] as String? ?? "";
      final err = res['error'] as String?;

      if (!mounted) return;

      setState(() {
        _progress = prog.clamp(0.05, 1.0);
        _currentRecognizedPage = currP;
        if (totalP > 0) _totalTargetPages = totalP;
        _statusMessage = msg.isNotEmpty ? msg : "正在进行双层可检索文本层生成与合并...";
      });

      if (status == "completed") {
        timer.cancel();
        setState(() {
          _isProcessing = false;
          _progress = 1.0;
          _statusMessage = "OCR 识别完成！已精准合并至原 PDF。";
        });
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) {
          widget.onOcrCompleted();
          Navigator.of(context).pop();
        }
      } else if (status == "failed") {
        timer.cancel();
        setState(() {
          _isProcessing = false;
          _errorMessage = err ?? "OCR 任务未完成，请检查配置后重试";
        });
      }
    });
  }

  Future<void> _confirmAndRevert() async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isCurrentScope = _pageScope == "current";

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.history_rounded, color: Colors.amber, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('恢复原本文字层', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isCurrentScope
                  ? '确定清除当前第 ${widget.currentPage} 页的 OCR 识别结果，并启用该页原本内嵌的文字与排版？'
                  : _pageScope == "all"
                      ? '确定清除全文档的所有 OCR 识别结果，恢复初始上传的原始 PDF 与原生文字层？'
                      : '确定清除所选页面 (${_customPagesController.text}) 的 OCR 结果并恢复原本文字层？',
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: Colors.blueAccent),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '此操作将恢复原版文档文字层，并保留您已创建的批注。',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认恢复'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _executeRevert();
    }
  }

  Future<void> _executeRevert() async {
    setState(() {
      _isProcessing = true;
      _progress = 0.5;
      _statusMessage = "正在清除 OCR 结果并启用原本文字层...";
      _errorMessage = null;
    });

    final targets = _parseTargetPages();
    final docProvider = context.read<DocumentProvider>();
    final success = await docProvider.revertOcr(
      widget.document.id,
      pageScope: _pageScope,
      targetPages: targets,
    );

    if (!mounted) return;

    if (success) {
      widget.onOcrCompleted();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
              const SizedBox(width: 8),
              Text(
                _pageScope == "current"
                    ? '已清除第 ${widget.currentPage} 页 OCR 结果，已启用原本文字层'
                    : '已清除 OCR 结果并启用原本文字层',
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1E293B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } else {
      setState(() {
        _isProcessing = false;
        _errorMessage = docProvider.errorMessage ?? "恢复原本文字层失败";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: theme.cardTheme.color,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE11D48), Color(0xFF4F46E5)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.auto_fix_high_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '智能 OCR 双层可检索 PDF 构建',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Adobe 官方云端 / 本地 RapidOCR • 精准划词选中',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                  if (!_isProcessing)
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!_isProcessing) ...[
                        // 1. Engine Selection
                        const Text(
                          '选择 OCR 识别引擎',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        
                        // 3 Engine Cards
                        _buildEngineOption(
                          title: 'Adobe PDF Services OCR',
                          subtitle: 'Adobe 官方云端引擎 • 100% 原生双层 PDF 生成 • 高精度极稳定',
                          tagText: '官方推荐',
                          tagColor: const Color(0xFF10B981),
                          isSelected: _selectedEngine == "adobe",
                          icon: Icons.verified_rounded,
                          color: const Color(0xFFE11D48),
                          onTap: () => setState(() => _selectedEngine = "adobe"),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _buildEngineOption(
                                title: '本地 RapidOCR',
                                subtitle: '离线 ONNX 引擎 (免 Token)',
                                tagText: '离线免配置',
                                tagColor: const Color(0xFF0D9488),
                                isSelected: _selectedEngine == "rapidocr",
                                icon: Icons.memory_rounded,
                                color: const Color(0xFF0D9488),
                                onTap: () => setState(() => _selectedEngine = "rapidocr"),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildEngineOption(
                                title: '百度 PaddleOCR-VL',
                                subtitle: '解析为 Markdown (公式/表格/排版)',
                                tagText: '生成MD',
                                tagColor: const Color(0xFF6366F1),
                                isSelected: _selectedEngine == "paddleocr_vl",
                                icon: Icons.description_outlined,
                                color: const Color(0xFF6366F1),
                                onTap: () => setState(() => _selectedEngine = "paddleocr_vl"),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // 2. Scope Selection (Full Doc, Current Page, Custom Range)
                        const Text(
                          '识别与替换页面范围',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: Text('当前第 ${widget.currentPage} 页 (单页重构)'),
                              selected: _pageScope == "current",
                              avatar: const Icon(Icons.article_rounded, size: 16),
                              onSelected: (val) => setState(() => _pageScope = "current"),
                            ),
                            ChoiceChip(
                              label: Text('全篇文档 (共 ${widget.document.pageCount} 页)'),
                              selected: _pageScope == "all",
                              avatar: const Icon(Icons.library_books_rounded, size: 16),
                              onSelected: (val) => setState(() => _pageScope = "all"),
                            ),
                            ChoiceChip(
                              label: const Text('自定义页码范围'),
                              selected: _pageScope == "custom",
                              avatar: const Icon(Icons.tune_rounded, size: 16),
                              onSelected: (val) => setState(() => _pageScope = "custom"),
                            ),
                          ],
                        ),

                        if (_pageScope == "custom") ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: _customPagesController,
                            decoration: InputDecoration(
                              hintText: '如: 1, 3, 5-8 (页码以逗号或连字符分隔)',
                              labelText: '输入目标页码',
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              helperText: '仅对上述指定页码执行 OCR 并无缝替换进原 PDF，其余页面完全保留',
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),

                        // 3. Adobe OCR Settings (Collapsible)
                        if (_selectedEngine == "adobe") ...[
                          InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => setState(() => _showAdobeConfig = !_showAdobeConfig),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Icon(
                                    _showAdobeConfig ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
                                    size: 20,
                                    color: const Color(0xFFE11D48),
                                  ),
                                  const SizedBox(width: 4),
                                  const Text(
                                    'Adobe PDF Services 凭据与语言选项设置',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFE11D48),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_showAdobeConfig) ...[
                            const SizedBox(height: 8),
                            TextField(
                              controller: _adobeClientIdController,
                              decoration: InputDecoration(
                                labelText: 'Adobe Client ID',
                                hintText: '输入 Adobe PDF Services Client ID',
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _adobeClientSecretController,
                              obscureText: true,
                              decoration: InputDecoration(
                                labelText: 'Adobe Client Secret',
                                hintText: '输入 Adobe PDF Services Client Secret',
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.restore_rounded, size: 18),
                                  tooltip: '重置为默认官方凭据',
                                  onPressed: () => setState(() {
                                    _adobeClientIdController.text = _defaultAdobeClientId;
                                    _adobeClientSecretController.text = _defaultAdobeClientSecret;
                                  }),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Text('文档语言: ', style: TextStyle(fontSize: 12)),
                                const SizedBox(width: 8),
                                DropdownButton<String>(
                                  value: _adobeLocale,
                                  isDense: true,
                                  items: const [
                                    DropdownMenuItem(value: 'zh-CN', child: Text('简体中文 (zh-CN)')),
                                    DropdownMenuItem(value: 'en-US', child: Text('英语 (en-US)')),
                                    DropdownMenuItem(value: 'zh-HK', child: Text('繁体中文 (zh-HK)')),
                                    DropdownMenuItem(value: 'ja-JP', child: Text('日语 (ja-JP)')),
                                    DropdownMenuItem(value: 'ko-KR', child: Text('韩语 (ko-KR)')),
                                    DropdownMenuItem(value: 'de-DE', child: Text('德语 (de-DE)')),
                                    DropdownMenuItem(value: 'fr-FR', child: Text('法语 (fr-FR)')),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) setState(() => _adobeLocale = val);
                                  },
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 12),
                        ],

                        // 4. Baidu API Settings (Collapsible)
                        if (_selectedEngine == "paddleocr_vl") ...[
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6366F1).withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.2)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.info_outline_rounded, color: Color(0xFF6366F1), size: 16),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '百度 AI Studio PaddleOCR-VL 专注于将文档解析为结构化 Markdown（支持公式与复杂表格）。',
                                    style: TextStyle(fontSize: 11, color: Color(0xFF4F46E5)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => setState(() => _showBaiduConfig = !_showBaiduConfig),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Icon(
                                    _showBaiduConfig ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
                                    size: 20,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '百度 AI Studio API Token 与多模态参数设置',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_showBaiduConfig) ...[
                            const SizedBox(height: 8),
                            TextField(
                              controller: _apiTokenController,
                              decoration: InputDecoration(
                                labelText: 'PaddleOCR-VL Bearer Token',
                                hintText: '输入 AI Studio Access Token',
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.restore_rounded, size: 18),
                                  tooltip: '重置为默认官方 Token',
                                  onPressed: () => setState(() => _apiTokenController.text = _defaultBaiduToken),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                SizedBox(
                                  width: 170,
                                  child: CheckboxListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('文本方向自动分类', style: TextStyle(fontSize: 12)),
                                    value: _useDocOrientationClassify,
                                    onChanged: (v) => setState(() => _useDocOrientationClassify = v ?? false),
                                  ),
                                ),
                                SizedBox(
                                  width: 170,
                                  child: CheckboxListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('文档形变自动矫正', style: TextStyle(fontSize: 12)),
                                    value: _useDocUnwarping,
                                    onChanged: (v) => setState(() => _useDocUnwarping = v ?? false),
                                  ),
                                ),
                                SizedBox(
                                  width: 170,
                                  child: CheckboxListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('图表区域识别', style: TextStyle(fontSize: 12)),
                                    value: _useChartRecognition,
                                    onChanged: (v) => setState(() => _useChartRecognition = v ?? false),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 12),
                        ],

                        // Feature Assurance Card
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.check_circle_rounded, color: Colors.green.shade400, size: 15),
                                  const SizedBox(width: 6),
                                  const Expanded(
                                    child: Text(
                                      '原扫描画质与公式排版 100% 视觉保真，零畸变',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.check_circle_rounded, color: Colors.green.shade400, size: 15),
                                  const SizedBox(width: 6),
                                  const Expanded(
                                    child: Text(
                                      '直接生成标准可检索双层 PDF，光标支持划词高亮与文本批注',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Restore / Clear OCR Option Card
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Icon(Icons.history_rounded, size: 16, color: Colors.amber),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '清除 OCR 结果 / 启用原本文字层',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _pageScope == "current"
                                          ? '清除当前第 ${widget.currentPage} 页的 OCR 图层，启用原本内嵌文字'
                                          : _pageScope == "all"
                                              ? '清除全文档 OCR 结果，恢复初始上传的原版 PDF'
                                              : '清除所选范围的 OCR 结果并启用原本文字层',
                                      style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  foregroundColor: const Color(0xFFEF4444),
                                  side: const BorderSide(color: Color(0xFFEF4444), width: 0.8),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                ),
                                icon: const Icon(Icons.undo_rounded, size: 14),
                                label: Text(
                                  _pageScope == "current" ? '恢复当前页' : '恢复原生层',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                                onPressed: _confirmAndRevert,
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        // Processing Progress Card
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                _statusMessage,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _totalTargetPages > 0 && _currentRecognizedPage > 0
                                  ? '$_currentRecognizedPage/$_totalTargetPages页 (${(_progress * 100).toInt()}%)'
                                  : '${(_progress * 100).toInt()}%',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: _progress,
                            minHeight: 8,
                            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _selectedEngine == "adobe" ? const Color(0xFFE11D48) : theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      if (_errorMessage != null)
                        Container(
                          margin: const EdgeInsets.only(top: 12),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(color: Colors.red, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (!_isProcessing)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      ),
                      icon: const Icon(Icons.history_rounded, size: 16),
                      label: Text(
                        _pageScope == "current" ? '清除本页OCR' : '恢复原始文字',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onPressed: _confirmAndRevert,
                    )
                  else
                    const SizedBox(),
                  Row(
                    children: [
                      if (!_isProcessing)
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('稍后再说'),
                        ),
                      const SizedBox(width: 8),
                      if (!_isProcessing)
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _selectedEngine == "adobe"
                                ? const Color(0xFFE11D48)
                                : _selectedEngine == "paddleocr_vl"
                                    ? const Color(0xFFD97706)
                                    : const Color(0xFF0D9488),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          ),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: Text(
                            _selectedEngine == "paddleocr_vl"
                                ? (_pageScope == "current"
                                    ? '解析第 ${widget.currentPage} 页生成 Markdown'
                                    : '解析全文并生成 Markdown 文档')
                                : _pageScope == "current"
                                    ? '识别并覆盖第 ${widget.currentPage} 页'
                                    : '立即开始 OCR 识别',
                          ),
                          onPressed: _startOcr,
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEngineOption({
    required String title,
    required String subtitle,
    String? tagText,
    Color? tagColor,
    required bool isSelected,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: isDark ? 0.2 : 0.08)
              : (isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: isSelected ? 0.25 : 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? color : null,
                        ),
                      ),
                      if (tagText != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: (tagColor ?? color).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: (tagColor ?? color).withValues(alpha: 0.4),
                              width: 0.6,
                            ),
                          ),
                          child: Text(
                            tagText,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: tagColor ?? color,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
