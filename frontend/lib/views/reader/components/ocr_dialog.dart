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
  String _pageScope = "current"; // "current" | "all" | "custom"
  late TextEditingController _customPagesController;
  
  // Baidu PaddleOCR-VL configuration
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
    _apiTokenController = TextEditingController(text: _defaultBaiduToken);

    if (widget.document.ocrStatus == "processing") {
      _isProcessing = true;
      _progress = 0.1;
      _statusMessage = "OCR 解析中...";
      _startPolling();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _customPagesController.dispose();
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

    setState(() {
      _isProcessing = true;
      _progress = 0.05;
      _totalTargetPages = targetCount;
      _currentRecognizedPage = 0;
      _statusMessage = "正在连接百度 AI Studio PaddleOCR-VL API...";
      _errorMessage = null;
    });

    widget.onOcrStarted?.call();

    final docProvider = context.read<DocumentProvider>();
    final success = await docProvider.triggerOcr(
      widget.document.id,
      apiToken: _apiTokenController.text.trim().isNotEmpty ? _apiTokenController.text.trim() : _defaultBaiduToken,
      pageScope: _pageScope,
      targetPages: targets,
      useDocOrientationClassify: _useDocOrientationClassify,
      useDocUnwarping: _useDocUnwarping,
      useChartRecognition: _useChartRecognition,
    );

    if (!success) {
      setState(() {
        _isProcessing = false;
        _errorMessage = docProvider.errorMessage ?? "启动 OCR 失败，请检查网络或 API Token 配置";
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
        _statusMessage = msg.isNotEmpty ? msg : "正在解析排版、表格与数学公式，生成 Markdown 文档...";
      });

      if (status == "completed") {
        timer.cancel();
        setState(() {
          _isProcessing = false;
          _progress = 1.0;
          _statusMessage = "OCR 解析完成！已就绪结构化 Markdown 文档。";
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
            const Text('清除 OCR 结果', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isCurrentScope
                  ? '确定清除当前第 ${widget.currentPage} 页的 OCR Markdown 识别结果？'
                  : _pageScope == "all"
                      ? '确定清除全文档的所有 OCR Markdown 识别结果？'
                      : '确定清除所选页面 (${_customPagesController.text}) 的 OCR 结果？',
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
                      '此操作将清除生成的 Markdown 内容，您已创建的批注与原生 PDF 保持不变。',
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
            child: const Text('确认清除'),
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
      _statusMessage = "正在清除 OCR 结果...";
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
                    ? '已清除第 ${widget.currentPage} 页 OCR Markdown'
                    : '已清除 OCR Markdown 识别结果',
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
        _errorMessage = docProvider.errorMessage ?? "清除 OCR 结果失败";
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
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
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
                        colors: [Color(0xFF4F46E5), Color(0xFF0EA5E9)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '百度 PaddleOCR-VL 智能解析',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'AI Studio 官方多模态引擎 • 提取排版、LaTeX 公式与结构化 Markdown',
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
                        // 1. Feature Highlights Banner
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isDark
                                  ? [const Color(0xFF312E81).withValues(alpha: 0.35), const Color(0xFF1E3A8A).withValues(alpha: 0.25)]
                                  : [const Color(0xFFEEF2FF), const Color(0xFFE0F2FE)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFF6366F1).withValues(alpha: isDark ? 0.35 : 0.25),
                            ),
                          ),
                          child: Column(
                            children: [
                              _buildFeatureRow(
                                icon: Icons.description_outlined,
                                color: const Color(0xFF6366F1),
                                title: 'Markdown 结构化解析',
                                desc: '自动提取多级标题、段落排版与 HTML 表格，支持 MD 视图阅读',
                              ),
                              const SizedBox(height: 8),
                              _buildFeatureRow(
                                icon: Icons.functions_rounded,
                                color: const Color(0xFF0EA5E9),
                                title: 'LaTeX 数学公式识别',
                                desc: '精准识别行内与独立数学公式，使用 KaTeX 高清排版渲染',
                              ),
                              const SizedBox(height: 8),
                              _buildFeatureRow(
                                icon: Icons.table_chart_outlined,
                                color: const Color(0xFF10B981),
                                title: '表格与版面多模态理解',
                                desc: '保留多列排版与跨行表格结构，完美兼容复杂论文与技术文档',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // 2. Scope Selection (Full Doc, Current Page, Custom Range)
                        const Text(
                          '识别与解析页面范围',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: Text('当前第 ${widget.currentPage} 页 (单页解析)'),
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
                              helperText: '仅对指定页码执行 OCR 并合并进 Markdown，其余页面保留',
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),

                        // 3. Baidu API Settings (Collapsible)
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
                                      '清除 OCR Markdown 识别结果',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _pageScope == "current"
                                          ? '清除当前第 ${widget.currentPage} 页的 OCR Markdown 结果'
                                          : _pageScope == "all"
                                              ? '清除全文档的 OCR Markdown 内容'
                                              : '清除所选范围的 OCR Markdown 结果',
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
                                  _pageScope == "current" ? '清除本页' : '清除全部',
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
                              theme.colorScheme.primary,
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
                        _pageScope == "current" ? '清除本页OCR' : '清除全部OCR',
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
                            backgroundColor: const Color(0xFF4F46E5),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                          label: Text(
                            _pageScope == "current"
                                ? '解析第 ${widget.currentPage} 页 (提取 Markdown)'
                                : '开始 PaddleOCR-VL 全文解析',
                            style: const TextStyle(fontWeight: FontWeight.bold),
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

  Widget _buildFeatureRow({
    required IconData icon,
    required Color color,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                desc,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
