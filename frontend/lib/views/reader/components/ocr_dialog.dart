import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/document_model.dart';
import '../../../providers/document_provider.dart';

class OcrDialog extends StatefulWidget {
  final DocumentModel document;
  final VoidCallback onOcrCompleted;
  final VoidCallback? onOcrStarted;

  const OcrDialog({
    super.key,
    required this.document,
    required this.onOcrCompleted,
    this.onOcrStarted,
  });

  @override
  State<OcrDialog> createState() => _OcrDialogState();
}

class _OcrDialogState extends State<OcrDialog> {
  String _selectedLanguage = "chi_sim+eng+equ";
  bool _isProcessing = false;
  double _progress = 0.0;
  int _currentPage = 0;
  int _totalPages = 0;
  String _statusMessage = "";
  String? _errorMessage;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  void _startOcr() async {
    setState(() {
      _isProcessing = true;
      _progress = 0.05;
      _statusMessage = "正在初始化 OCR 引擎与数学公式解析器...";
      _errorMessage = null;
    });

    widget.onOcrStarted?.call();

    final docProvider = context.read<DocumentProvider>();
    final success = await docProvider.triggerOcr(
      widget.document.id,
      languages: _selectedLanguage,
    );

    if (!success) {
      setState(() {
        _isProcessing = false;
        _errorMessage = docProvider.errorMessage ?? "启动 OCR 失败，请检查网络或后端状态";
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
      final totalP = (res['total_pages'] as num?)?.toInt() ?? widget.document.pageCount;
      final msg = res['message'] as String? ?? "";
      final err = res['error'] as String?;

      if (!mounted) return;

      setState(() {
        _progress = prog.clamp(0.05, 1.0);
        _currentPage = currP;
        _totalPages = totalP;
        _statusMessage = msg.isNotEmpty ? msg : "正在进行双层可检索文本层生成...";
      });

      if (status == "completed") {
        timer.cancel();
        setState(() {
          _isProcessing = false;
          _progress = 1.0;
          _statusMessage = "转换完成！已生成双层可检索 PDF。";
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
          _errorMessage = err ?? "OCR 转换未完成，请重试";
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: theme.cardTheme.color,
      child: Container(
        width: 480,
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
                  child: const Icon(Icons.auto_fix_high_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '生成双层可检索 PDF (OCR)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '支持数学公式、希腊字母与中英文划词高亮',
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
            const SizedBox(height: 18),

            // Feature Explanation Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle_rounded, color: Colors.green.shade400, size: 16),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '100% 保持原始扫描画质，零排版畸变',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.check_circle_rounded, color: Colors.green.shade400, size: 16),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '在底层生成精准坐标文本层，实现光标自由划词',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.check_circle_rounded, color: Colors.green.shade400, size: 16),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '公式符号（∑, ∫, α, β, 矩阵）精准覆盖与高亮',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (!_isProcessing) ...[
              // Language Selector
              const Text(
                '识别语言与模型',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedLanguage,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                        value: "chi_sim+eng+equ",
                        child: Text('中英双语 + 数学公式符号 (推荐)'),
                      ),
                      DropdownMenuItem(
                        value: "chi_sim+eng",
                        child: Text('中英文混合识别 (chi_sim + eng)'),
                      ),
                      DropdownMenuItem(
                        value: "eng+equ",
                        child: Text('纯英文论文与公式 (eng + equ)'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedLanguage = val);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ] else ...[
              // Processing Progress Card
              const SizedBox(height: 6),
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
                    _totalPages > 0 && _currentPage > 0
                        ? '$_currentPage/$_totalPages页 (${(_progress * 100).toInt()}%)'
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
                  valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                ),
              ),
              const SizedBox(height: 20),
            ],

            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
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

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!_isProcessing)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('稍后再说'),
                  ),
                const SizedBox(width: 8),
                if (!_isProcessing)
                  ElevatedButton.icon(
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('立即转换'),
                    onPressed: _startOcr,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

