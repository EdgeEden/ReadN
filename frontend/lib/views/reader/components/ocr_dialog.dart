import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../models/document_model.dart';
import '../../../providers/document_provider.dart';
import '../../../services/ocr/client_ocr_service.dart';
import '../../../services/ocr/mineru_ocr_service.dart';

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
  // Engine selection: 'mineru' (default) | 'paddleocr_vl'
  String _engine = "mineru";

  // Scope: 'current' | 'all' | 'custom'
  String _pageScope = "current";
  late TextEditingController _customPagesController;

  // Execution channel: 'client' (Direct) | 'server' (Backend Cloud)
  String _executionChannel = kIsWeb ? "server" : "client";
  bool _isCancelled = false;

  // Advanced Options Drawer
  bool _showAdvanced = false;

  // MinerU Configurations
  late TextEditingController _mineruTokenController;
  String _mineruModelVersion = "vlm"; // "vlm" | "pipeline"
  String _mineruLanguage = "auto"; // "auto", "ch", "en", "ja", "ko", etc.
  bool _enableFormula = true;
  bool _enableTable = true;
  bool _ossAccelerate = true;

  // Baidu PaddleOCR Configurations (Legacy support)
  late TextEditingController _baiduTokenController;
  bool _useDocOrientationClassify = false;
  bool _useDocUnwarping = false;
  final bool _useChartRecognition = false;

  // Processing State & Progress Metrics
  bool _isProcessing = false;
  double _progress = 0.0;
  String _phase = "idle";
  double _uploadSpeedMbS = 0.0;
  int _totalTargetPages = 0;
  String _statusMessage = "";
  String? _errorMessage;
  Timer? _pollTimer;


  static const String _defaultMineruToken = MineruOcrService.defaultMineruToken;
  static const String _defaultBaiduToken = ClientOcrService.defaultBaiduToken;

  @override
  void initState() {
    super.initState();
    if (!widget.document.hasTextLayer) {
      _pageScope = "all";
    } else {
      _pageScope = "current";
    }

    _customPagesController = TextEditingController(text: "${widget.currentPage}");
    _mineruTokenController = TextEditingController(text: _defaultMineruToken);
    _baiduTokenController = TextEditingController(text: _defaultBaiduToken);

    _loadPreferences();

    if (widget.document.ocrStatus == "processing") {
      _isProcessing = true;
      _progress = 0.1;
      _statusMessage = "Markdown 解析任务正在运行...";
      _startPolling();
    }
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedEngine = prefs.getString('pref_ocr_engine');
      if (savedEngine != null && mounted) {
        setState(() => _engine = savedEngine);
      }
      final savedChannel = prefs.getString('pref_ocr_channel');
      if (savedChannel != null && !kIsWeb && mounted) {
        setState(() => _executionChannel = savedChannel);
      }
      final savedMineruToken = prefs.getString('pref_mineru_token');
      if (savedMineruToken != null && savedMineruToken.trim().isNotEmpty && mounted) {
        setState(() => _mineruTokenController.text = savedMineruToken.trim());
      }
      final savedBaiduToken = prefs.getString('pref_baidu_ocr_token');
      if (savedBaiduToken != null && savedBaiduToken.trim().isNotEmpty && mounted) {
        setState(() => _baiduTokenController.text = savedBaiduToken.trim());
      }
      final savedModel = prefs.getString('pref_mineru_model');
      if (savedModel != null && mounted) {
        setState(() => _mineruModelVersion = savedModel);
      }
      final savedLang = prefs.getString('pref_mineru_lang');
      if (savedLang != null && mounted) {
        setState(() => _mineruLanguage = savedLang);
      }
    } catch (_) {}
  }

  Future<void> _savePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pref_ocr_engine', _engine);
      await prefs.setString('pref_ocr_channel', _executionChannel);
      await prefs.setString('pref_mineru_token', _mineruTokenController.text.trim());
      await prefs.setString('pref_baidu_ocr_token', _baiduTokenController.text.trim());
      await prefs.setString('pref_mineru_model', _mineruModelVersion);
      await prefs.setString('pref_mineru_lang', _mineruLanguage);
    } catch (_) {}
  }

  @override
  void dispose() {
    _isCancelled = true;
    _pollTimer?.cancel();
    _customPagesController.dispose();
    _mineruTokenController.dispose();
    _baiduTokenController.dispose();
    super.dispose();
  }

  List<int>? _parseTargetPages() {
    if (_pageScope == "all") return null;
    if (_pageScope == "current") {
      return [widget.currentPage.clamp(1, max(1, widget.document.pageCount))];
    }

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

  void _startConversion() {
    _savePreferences();
    if (!kIsWeb && _executionChannel == "client") {
      _startClientConversion();
    } else {
      _startServerConversion();
    }
  }

  Future<void> _startClientConversion() async {
    final targets = _parseTargetPages();
    final targetCount = targets?.length ?? widget.document.pageCount;

    setState(() {
      _isProcessing = true;
      _progress = 0.05;
      _phase = "preparing";
      _uploadSpeedMbS = 0.0;
      _totalTargetPages = targetCount;
      _statusMessage = "正在准备 PDF 文档数据...";
      _errorMessage = null;
    });


    widget.onOcrStarted?.call();

    try {
      final docProvider = context.read<DocumentProvider>();
      Uint8List? pdfBytes;

      // 1. Cache-first check
      final cachedBytes = await docProvider.docCacheService.getPdf(
        widget.document.id,
        expectedChecksum: widget.document.checksum,
      );
      if (cachedBytes != null && cachedBytes.isNotEmpty) {
        pdfBytes = cachedBytes;
      } else {
        if (mounted) {
          setState(() => _statusMessage = "正在从服务器读取 PDF 文档...");
        }
        final fileUrl = '${docProvider.apiService.baseUrl}/api/documents/${widget.document.id}/file';
        final res = await http.get(Uri.parse(fileUrl));
        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
          pdfBytes = res.bodyBytes;
          await docProvider.docCacheService.savePdf(
            widget.document.id,
            pdfBytes,
            checksum: widget.document.checksum,
          );
        }
      }

      if (pdfBytes == null || pdfBytes.isEmpty) {
        throw Exception("未能获取 PDF 文档字节流，请检查网络连接");
      }

      if (_isCancelled || !mounted) return;

      // 2. Fetch existing markdown
      String? existingMd;
      final cachedMd = await docProvider.docCacheService.getMarkdown(widget.document.id);
      if (cachedMd != null && cachedMd.isNotEmpty) {
        existingMd = cachedMd;
      } else {
        final serverMdRes = await docProvider.getMarkdown(widget.document.id);
        if (serverMdRes['has_markdown'] == true) {
          existingMd = serverMdRes['markdown'] as String?;
        }
      }

      String mergedMarkdown = "";

      if (_engine == "mineru") {
        final mineruService = MineruOcrService();
        final token = _mineruTokenController.text.trim();
        if (token.isEmpty) {
          throw Exception("请在下方【高级选项】中填写 MinerU API Token（可在 mineru.net 免费申请）");
        }

        mergedMarkdown = await mineruService.executeMineruOcr(
          fullPdfBytes: pdfBytes,
          totalDocPages: widget.document.pageCount,
          targetPages: targets,
          docId: widget.document.id,
          apiService: docProvider.apiService,
          apiToken: token,
          modelVersion: _mineruModelVersion,
          language: _mineruLanguage,
          enableFormula: _enableFormula,
          enableTable: _enableTable,
          ossAccelerate: _ossAccelerate,
          existingMarkdown: existingMd,
          onProgress: (prog, msg, phase, speed, currP, totalP) {
            if (!mounted || _isCancelled) return;
            setState(() {
              _progress = prog;
              _statusMessage = msg;
              _phase = phase;
              _uploadSpeedMbS = speed;
              if (totalP > 0) _totalTargetPages = totalP;
            });

          },
          isCancelled: () => _isCancelled || !mounted,
        );
      } else {
        final clientOcr = ClientOcrService();
        final token = _baiduTokenController.text.trim();
        if (token.isEmpty) {
          throw Exception("请在下方【高级选项】中填写百度飞桨 API Token（可在 aistudio.baidu.com 获取）");
        }

        mergedMarkdown = await clientOcr.executeClientOcr(
          fullPdfBytes: pdfBytes,
          totalDocPages: widget.document.pageCount,
          targetPages: targets,
          apiToken: token,
          useDocOrientationClassify: _useDocOrientationClassify,
          useDocUnwarping: _useDocUnwarping,
          useChartRecognition: _useChartRecognition,
          existingMarkdown: existingMd,
          onProgress: (prog, msg, currP, totalP) {
            if (!mounted || _isCancelled) return;
            setState(() {
              _progress = prog;
              _statusMessage = msg;
              _phase = "processing";
              if (totalP > 0) _totalTargetPages = totalP;
            });

          },
          isCancelled: () => _isCancelled || !mounted,
        );
      }

      if (_isCancelled || !mounted) return;

      setState(() {
        _statusMessage = "正在同步 Markdown 结果至云端服务器...";
        _phase = "merging";
        _progress = 0.98;
      });

      final syncSuccess = await docProvider.syncClientOcrResult(widget.document.id, mergedMarkdown);
      if (!syncSuccess) {
        throw Exception(docProvider.errorMessage ?? "同步 Markdown 至云端失败");
      }

      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _progress = 1.0;
        _phase = "completed";
        _statusMessage = "解析完成！Markdown 已同步就绪。";
      });

      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        widget.onOcrCompleted();
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _phase = "idle";
        _errorMessage = e.toString().replaceFirst("Exception: ", "");
      });
    }
  }

  void _startServerConversion() async {
    final targets = _parseTargetPages();
    final targetCount = targets?.length ?? widget.document.pageCount;

    setState(() {
      _isProcessing = true;
      _progress = 0.05;
      _phase = "preparing";
      _uploadSpeedMbS = 0.0;
      _totalTargetPages = targetCount;
      _statusMessage = _engine == "mineru"
          ? "正在连接 MinerU VLM 服务..."
          : "正在连接百度 AI Studio 服务...";
      _errorMessage = null;
    });

    widget.onOcrStarted?.call();

    final docProvider = context.read<DocumentProvider>();
    final success = await docProvider.triggerOcr(
      widget.document.id,
      engine: _engine,
      mineruToken: _mineruTokenController.text.trim(),
      mineruModelVersion: _mineruModelVersion,
      mineruLanguage: _mineruLanguage,
      enableFormula: _enableFormula,
      enableTable: _enableTable,
      ossAccelerate: _ossAccelerate,
      apiToken: _baiduTokenController.text.trim(),
      pageScope: _pageScope,
      targetPages: targets,
      useDocOrientationClassify: _useDocOrientationClassify,
      useDocUnwarping: _useDocUnwarping,
      useChartRecognition: _useChartRecognition,
    );

    if (!success) {
      setState(() {
        _isProcessing = false;
        _phase = "idle";
        _errorMessage = docProvider.errorMessage ?? "启动解析失败，请检查网络或配置";
      });
      return;
    }

    _startPolling();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    final docProvider = context.read<DocumentProvider>();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 900), (timer) async {
      final res = await docProvider.checkOcrProgress(widget.document.id);
      final status = res['status'] as String? ?? "none";
      final prog = (res['progress'] as num?)?.toDouble() ?? 0.0;
      final phase = res['phase'] as String? ?? "processing";
      final speed = (res['upload_speed_mb_s'] as num?)?.toDouble() ?? 0.0;
      final totalP = (res['total_pages'] as num?)?.toInt() ?? _totalTargetPages;
      final msg = res['message'] as String? ?? "";
      final err = res['error'] as String?;


      if (!mounted) return;

      setState(() {
        _progress = prog.clamp(0.05, 1.0);
        _phase = phase;
        _uploadSpeedMbS = speed;
        if (totalP > 0) _totalTargetPages = totalP;
        _statusMessage = msg.isNotEmpty ? msg : "正在解析排版与数学公式，生成结构化 Markdown...";
      });


      if (status == "completed") {
        timer.cancel();
        setState(() {
          _isProcessing = false;
          _progress = 1.0;
          _phase = "completed";
          _statusMessage = "Markdown 转换已完成！";
        });
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          widget.onOcrCompleted();
          Navigator.of(context).pop();
        }
      } else if (status == "failed") {
        timer.cancel();
        setState(() {
          _isProcessing = false;
          _phase = "idle";
          _errorMessage = err ?? "解析任务未完成，请检查配置后重试";
        });
      }
    });
  }

  Future<void> _confirmAndRevert() async {
    final isCurrentScope = _pageScope == "current";

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.amber, size: 22),
            SizedBox(width: 10),
            Text('清除 Markdown 结果', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          isCurrentScope
              ? '确定清除当前第 ${widget.currentPage} 页的 Markdown 内容？'
              : _pageScope == "all"
                  ? '确定清除全篇文档的所有 Markdown 内容？'
                  : '确定清除所选页面 (${_customPagesController.text}) 的 Markdown 内容？',
          style: const TextStyle(fontSize: 13, height: 1.5),
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
      _statusMessage = "正在清除 Markdown 结果...";
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
    } else {
      setState(() {
        _isProcessing = false;
        _errorMessage = docProvider.errorMessage ?? "清除 Markdown 结果失败";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      backgroundColor: theme.cardTheme.color,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Clean Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.auto_awesome_rounded, color: theme.colorScheme.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '转换 Markdown',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.document.title} • 共 ${widget.document.pageCount} 页',
                          style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (!_isProcessing)
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // 2. Body Area
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!_isProcessing) ...[
                        // Scope selection
                        const Text('转换范围', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: Text('当前第 ${widget.currentPage} 页'),
                              selected: _pageScope == "current",
                              onSelected: (val) => setState(() => _pageScope = "current"),
                            ),
                            ChoiceChip(
                              label: Text('全篇文档 (${widget.document.pageCount}页)'),
                              selected: _pageScope == "all",
                              onSelected: (val) => setState(() => _pageScope = "all"),
                            ),
                            ChoiceChip(
                              label: const Text('自定义页码'),
                              selected: _pageScope == "custom",
                              onSelected: (val) => setState(() => _pageScope = "custom"),
                            ),
                          ],
                        ),

                        if (_pageScope == "custom") ...[
                          const SizedBox(height: 10),
                          TextField(
                            controller: _customPagesController,
                            decoration: InputDecoration(
                              hintText: '如: 1, 3, 5-10',
                              labelText: '目标页码',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),

                        // Engine selection
                        const Text('解析引擎', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('MinerU 大模型 (推荐)'),
                              avatar: const Icon(Icons.bolt_rounded, size: 15),
                              selected: _engine == "mineru",
                              onSelected: (val) {
                                if (val) setState(() => _engine = "mineru");
                              },
                            ),
                            ChoiceChip(
                              label: const Text('百度 PaddleOCR'),
                              avatar: const Icon(Icons.font_download_outlined, size: 15),
                              selected: _engine == "paddleocr_vl",
                              onSelected: (val) {
                                if (val) setState(() => _engine = "paddleocr_vl");
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Execution channel (Desktop/Mobile only)
                        if (!kIsWeb) ...[
                          const Text('执行通道', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ChoiceChip(
                                label: const Text('客户端直连 (免服务器中转)'),
                                avatar: const Icon(Icons.devices_rounded, size: 15),
                                selected: _executionChannel == "client",
                                onSelected: (val) {
                                  if (val) setState(() => _executionChannel = "client");
                                },
                              ),
                              ChoiceChip(
                                label: const Text('服务器云端解析'),
                                avatar: const Icon(Icons.cloud_outlined, size: 15),
                                selected: _executionChannel == "server",
                                onSelected: (val) {
                                  if (val) setState(() => _executionChannel = "server");
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Advanced Options Accordion
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => setState(() => _showAdvanced = !_showAdvanced),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Icon(
                                  _showAdvanced ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
                                  size: 18,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '高级选项',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.primary),
                                ),
                              ],
                            ),
                          ),
                        ),

                        if (_showAdvanced) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.6) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_engine == "mineru") ...[
                                  // MinerU Token
                                  TextField(
                                    controller: _mineruTokenController,
                                    decoration: InputDecoration(
                                      labelText: 'MinerU API Token',
                                      hintText: 'sk-...',
                                      isDense: true,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      suffixIcon: IconButton(
                                        icon: const Icon(Icons.restore_rounded, size: 16),
                                        tooltip: '恢复默认官方 Token',
                                        onPressed: () => setState(() => _mineruTokenController.text = _defaultMineruToken),
                                      ),
                                    ),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  const SizedBox(height: 12),

                                  // Model & Language Row
                                  Row(
                                    children: [
                                      Expanded(
                                        child: DropdownButtonFormField<String>(
                                          initialValue: _mineruModelVersion,
                                          decoration: InputDecoration(
                                            labelText: '模型版本',
                                            isDense: true,
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          style: TextStyle(fontSize: 12, color: theme.textTheme.bodyMedium?.color),
                                          items: const [
                                            DropdownMenuItem(value: 'vlm', child: Text('VLM 多模态大模型')),
                                            DropdownMenuItem(value: 'pipeline', child: Text('Pipeline 极速模型')),
                                          ],
                                          onChanged: (v) {
                                            if (v != null) setState(() => _mineruModelVersion = v);
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: DropdownButtonFormField<String>(
                                          initialValue: _mineruLanguage,
                                          decoration: InputDecoration(
                                            labelText: '识别语种',
                                            isDense: true,
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          style: TextStyle(fontSize: 12, color: theme.textTheme.bodyMedium?.color),
                                          items: const [
                                            DropdownMenuItem(value: 'auto', child: Text('自动检测 (智能识别)')),
                                            DropdownMenuItem(value: 'ch', child: Text('中文 / 多语言')),
                                            DropdownMenuItem(value: 'en', child: Text('英文 (English)')),
                                            DropdownMenuItem(value: 'ja', child: Text('日文 (Japanese)')),
                                            DropdownMenuItem(value: 'ko', child: Text('韩文 (Korean)')),
                                            DropdownMenuItem(value: 'fr', child: Text('法文 (French)')),
                                            DropdownMenuItem(value: 'de', child: Text('德文 (German)')),
                                            DropdownMenuItem(value: 'ru', child: Text('俄文 (Russian)')),
                                          ],
                                          onChanged: (v) {
                                            if (v != null) setState(() => _mineruLanguage = v);
                                          },
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 8),

                                  // Toggles
                                  CheckboxListTile(
                                    title: const Text('识别 LaTeX 数学公式', style: TextStyle(fontSize: 12)),
                                    value: _enableFormula,
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    controlAffinity: ListTileControlAffinity.leading,
                                    onChanged: (v) => setState(() => _enableFormula = v ?? true),
                                  ),
                                  CheckboxListTile(
                                    title: const Text('识别表格与排版结构', style: TextStyle(fontSize: 12)),
                                    value: _enableTable,
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    controlAffinity: ListTileControlAffinity.leading,
                                    onChanged: (v) => setState(() => _enableTable = v ?? true),
                                  ),
                                  CheckboxListTile(
                                    title: const Text('OSS 海外/全球专线传输加速 (推荐)', style: TextStyle(fontSize: 12)),
                                    value: _ossAccelerate,
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    controlAffinity: ListTileControlAffinity.leading,
                                    onChanged: (v) => setState(() => _ossAccelerate = v ?? true),
                                  ),
                                ] else ...[
                                  // PaddleOCR Token
                                  TextField(
                                    controller: _baiduTokenController,
                                    decoration: InputDecoration(
                                      labelText: 'PaddleOCR API Token',
                                      isDense: true,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  const SizedBox(height: 8),
                                  CheckboxListTile(
                                    title: const Text('文档方向自动校正', style: TextStyle(fontSize: 12)),
                                    value: _useDocOrientationClassify,
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    controlAffinity: ListTileControlAffinity.leading,
                                    onChanged: (v) => setState(() => _useDocOrientationClassify = v ?? false),
                                  ),
                                  CheckboxListTile(
                                    title: const Text('页面弯曲文字展平', style: TextStyle(fontSize: 12)),
                                    value: _useDocUnwarping,
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    controlAffinity: ListTileControlAffinity.leading,
                                    onChanged: (v) => setState(() => _useDocUnwarping = v ?? false),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ] else ...[
                        // 3. Dynamic Progress View (During Processing)
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.6) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      value: _progress > 0.05 ? _progress : null,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _phase == 'uploading'
                                          ? '正在上传文档...'
                                          : _phase == 'downloading'
                                              ? '正在下载结果...'
                                              : _phase == 'merging'
                                                  ? '正在合并结构化文档...'
                                                  : '正在云端智能解析...',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                  ),
                                  Text(
                                    '${(_progress * 100).toInt()}%',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: _progress,
                                  minHeight: 6,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _statusMessage,
                                style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color, height: 1.4),
                              ),
                              if (_uploadSpeedMbS > 0 && _phase == 'uploading') ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Icon(Icons.speed_rounded, size: 14, color: Colors.green),
                                    const SizedBox(width: 4),
                                    Text(
                                      '实时上传带宽: ${_uploadSpeedMbS.toStringAsFixed(1)} MB/s (${(_uploadSpeedMbS * 8).toStringAsFixed(1)} Mbps)',
                                      style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],

                      // Error message view
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, size: 18, color: Colors.redAccent),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(fontSize: 12, color: Colors.redAccent),
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
              const SizedBox(height: 16),

              // 4. Footer Actions
              Row(
                children: [
                  if (widget.document.hasMarkdown && !_isProcessing)
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline_rounded, size: 16),
                      label: const Text('清除已存 MD', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                      onPressed: _confirmAndRevert,
                    ),
                  const Spacer(),
                  if (!_isProcessing) ...[
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('开始转换'),
                      onPressed: _startConversion,
                    ),
                  ] else ...[
                    OutlinedButton(
                      onPressed: () {
                        _isCancelled = true;
                        _pollTimer?.cancel();
                        setState(() {
                          _isProcessing = false;
                          _errorMessage = "任务已取消";
                        });
                      },
                      child: const Text('取消任务'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
