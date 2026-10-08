import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:uuid/uuid.dart';

import '../../../models/ai_message_model.dart';
import '../../../models/annotation_model.dart';
import '../../../services/ai_service.dart';
import '../../../theme/app_theme.dart';
import 'latex_interactive_view.dart';
import 'markdown_html_support.dart';
import 'markdown_reader_view.dart';

/// Modal dialog that prompts the AI to summarize prior dialogue / answers into a structured Markdown Knowledge Card
class AiCardSummaryDialog extends StatefulWidget {
  final AiConfig config;
  final List<ChatMessage> conversationHistory;
  final ChatMessage? targetMessage;
  final String? initialQuote;
  final int pageNumber;
  final String docId;
  final String documentTitle;
  final ValueChanged<PdfAnnotation>? onSave;

  const AiCardSummaryDialog({
    super.key,
    required this.config,
    required this.conversationHistory,
    this.targetMessage,
    this.initialQuote,
    required this.pageNumber,
    required this.docId,
    required this.documentTitle,
    this.onSave,
  });

  @override
  State<AiCardSummaryDialog> createState() => _AiCardSummaryDialogState();
}

class _AiCardSummaryDialogState extends State<AiCardSummaryDialog> {
  final AiService _aiService = AiService();
  final Uuid _uuid = const Uuid();

  late TextEditingController _contentController;
  late TextEditingController _quoteController;
  StreamSubscription<AiStreamChunk>? _streamSubscription;

  bool _isGenerating = false;
  bool _isEditing = false;
  String _selectedColor = '#8B5CF6';
  String? _error;

  static const List<String> _cardColorPresets = [
    '#8B5CF6', // Purple
    '#6366F1', // Indigo
    '#3B82F6', // Blue
    '#10B981', // Emerald
    '#F59E0B', // Amber
    '#EC4899', // Pink
  ];

  @override
  void initState() {
    super.initState();
    _quoteController = TextEditingController(text: widget.initialQuote ?? widget.targetMessage?.quotedText ?? '');
    _contentController = TextEditingController();
    _startAiSummary();
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _aiService.cancelStream();
    _contentController.dispose();
    _quoteController.dispose();
    super.dispose();
  }

  void _startAiSummary() {
    _streamSubscription?.cancel();
    _aiService.cancelStream();

    setState(() {
      _isGenerating = true;
      _error = null;
      _contentController.clear();
      _isEditing = false;
    });

    final promptBuilder = StringBuffer();
    promptBuilder.writeln('请针对我们先前的对话讨论内容，进行系统性提炼与总结，生成一份结构清晰、重点突出、包含核心论点/推导公式/结论的 Markdown 格式知识卡片。');
    
    final quote = _quoteController.text.trim();
    if (quote.isNotEmpty) {
      promptBuilder.writeln('【核心引文】: $quote');
    }
    if (widget.targetMessage != null && widget.targetMessage!.content.isNotEmpty) {
      promptBuilder.writeln('【重点参考回答】:\n${widget.targetMessage!.content}');
    }

    promptBuilder.writeln('\n请遵循以下结构生成：');
    promptBuilder.writeln('## 核心概念与主旨');
    promptBuilder.writeln('[简要阐述该知识点的核心概念与背景]');
    promptBuilder.writeln('\n### 关键要点解析');
    promptBuilder.writeln('- **要点一**: ...');
    promptBuilder.writeln('- **要点二**: ...');
    promptBuilder.writeln('\n### 核心公式与推导（若涉及公式，请使用标准的 LaTeX 格式如 \$...\$ 或 \$\$...\$\$）');
    promptBuilder.writeln('\n### 总结与启示');
    promptBuilder.writeln('- [关键结论或启示]');

    try {
      final stream = _aiService.streamChat(
        config: widget.config,
        history: widget.conversationHistory,
        currentPrompt: promptBuilder.toString(),
        quotedText: quote.isNotEmpty ? quote : null,
        pageNumber: widget.pageNumber,
        documentTitle: widget.documentTitle,
      );

      _streamSubscription = stream.listen(
        (chunk) {
          if (chunk.error != null) {
            setState(() {
              _error = chunk.error;
              _isGenerating = false;
            });
            return;
          }

          if (chunk.contentDelta != null && chunk.contentDelta!.isNotEmpty) {
            setState(() {
              _contentController.text = _contentController.text + chunk.contentDelta!;
            });
          }

          if (chunk.isDone) {
            setState(() {
              _isGenerating = false;
            });
          }
        },
        onError: (err) {
          setState(() {
            _error = '生成中断: $err';
            _isGenerating = false;
          });
        },
        onDone: () {
          setState(() {
            _isGenerating = false;
          });
        },
      );
    } catch (e) {
      setState(() {
        _error = '启动生成失败: $e';
        _isGenerating = false;
      });
    }
  }

  void _stopGeneration() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
    _aiService.cancelStream();
    setState(() {
      _isGenerating = false;
    });
  }

  void _handleSave() {
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('卡片内容不能为空'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final quote = _quoteController.text.trim();
    final now = DateTime.now();

    final card = PdfAnnotation(
      id: _uuid.v4(),
      docId: widget.docId,
      type: "card",
      pageNumber: widget.pageNumber,
      colorHex: _selectedColor,
      rects: const [],
      selectedText: quote,
      noteContent: content,
      createdAt: now,
      updatedAt: now,
    );

    widget.onSave?.call(card);
    Navigator.of(context).pop(card);
  }

  void _copyMarkdown() {
    final quote = _quoteController.text.trim();
    final content = _contentController.text.trim();

    final sb = StringBuffer();
    sb.writeln('### 知识卡片 (第 ${widget.pageNumber} 页)');
    if (quote.isNotEmpty) {
      sb.writeln();
      sb.writeln('> 引用: $quote');
    }
    sb.writeln();
    sb.writeln(content);

    Clipboard.setData(ClipboardData(text: sb.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF86EFAC), size: 18),
            SizedBox(width: 8),
            Text('已复制知识卡片 Markdown 原文'),
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
    final accentColor = AppTheme.parseHexColor(_selectedColor);

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Header Bar
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 14),
              decoration: BoxDecoration(
                color: isDark
                    ? accentColor.withValues(alpha: 0.15)
                    : accentColor.withValues(alpha: 0.08),
                border: Border(
                  bottom: BorderSide(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    width: 0.8,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.auto_awesome_rounded, size: 20, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'AI 总结与提炼知识卡片',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '第 ${widget.pageNumber} 页',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: accentColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isGenerating ? 'AI 正在对多轮对话进行深度提炼与结构化组织...' : '已完成结构化提炼，可随时调整或保存',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Regenerate / Stop button
                  if (_isGenerating)
                    Tooltip(
                      message: '停止生成',
                      child: IconButton(
                        icon: const Icon(Icons.stop_circle_rounded, color: Colors.red, size: 22),
                        onPressed: _stopGeneration,
                      ),
                    )
                  else
                    Tooltip(
                      message: '重新总结提炼',
                      child: IconButton(
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        onPressed: _startAiSummary,
                      ),
                    ),

                  // Edit toggle
                  Tooltip(
                    message: _isEditing ? '预览卡片' : '编辑正文',
                    child: IconButton(
                      icon: Icon(
                        _isEditing ? Icons.visibility_rounded : Icons.edit_rounded,
                        size: 20,
                        color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                      ),
                      onPressed: () => setState(() => _isEditing = !_isEditing),
                    ),
                  ),

                  IconButton(
                    tooltip: '关闭',
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // 2. Content Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Referenced Quote Box (引文 / 图标停泊锚点)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                          width: 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                width: 4,
                                color: accentColor,
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.location_on_rounded, size: 14, color: accentColor),
                                          const SizedBox(width: 4),
                                          Text(
                                            '引文与图标停泊锚点 (第 ${widget.pageNumber} 页):',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      if (_isEditing)
                                        TextField(
                                          controller: _quoteController,
                                          maxLines: 2,
                                          style: const TextStyle(fontSize: 12),
                                          decoration: InputDecoration(
                                            hintText: '输入引文句子或公式（作为卡片在正文中的停泊锚点）...',
                                            hintStyle: TextStyle(
                                              fontSize: 11.5,
                                              color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
                                            ),
                                            isDense: true,
                                            contentPadding: EdgeInsets.zero,
                                            border: InputBorder.none,
                                          ),
                                        )
                                      else
                                        Text(
                                          _quoteController.text.trim().isNotEmpty
                                              ? '“${_quoteController.text.trim()}”'
                                              : '(未绑定特定引文，知识卡片图标停泊于本页开头)',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontStyle: FontStyle.italic,
                                            height: 1.5,
                                            color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Error Message
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, size: 16, color: Colors.red),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(fontSize: 12, color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Loading Indicator
                    if (_isGenerating && _contentController.text.trim().isEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 36,
                              height: 36,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text('AI 正在归纳总结对话与公式要点...', style: TextStyle(fontSize: 13, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ] else if (_isEditing) ...[
                      TextField(
                        controller: _contentController,
                        maxLines: 12,
                        minLines: 8,
                        style: const TextStyle(fontSize: 13, height: 1.6, fontFamily: 'monospace'),
                        decoration: InputDecoration(
                          labelText: '卡片正文 (Markdown & LaTeX 公式)',
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Theme Color Selector
                      Row(
                        children: [
                          Text(
                            '卡片主题色:',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(width: 10),
                          ..._cardColorPresets.map((hex) {
                            final isChosen = _selectedColor.toUpperCase() == hex.toUpperCase();
                            final color = AppTheme.parseHexColor(hex);
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: InkWell(
                                onTap: () => setState(() => _selectedColor = hex),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isChosen ? (isDark ? Colors.white : Colors.black87) : Colors.transparent,
                                      width: isChosen ? 2.5 : 1,
                                    ),
                                  ),
                                  child: isChosen ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ] else ...[
                      // Formatted Markdown Preview
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.6) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: MarkdownBody(
                          data: _contentController.text.trim().isNotEmpty
                              ? _contentController.text.trim()
                              : '*（等待生成或内容为空）*',
                          selectable: true,
                          extensionSet: md.ExtensionSet(
                            md.ExtensionSet.gitHubFlavored.blockSyntaxes,
                            [
                              LatexBlockInlineSyntax(),
                              LatexBracketInlineSyntax(),
                              LatexInlineSyntax(),
                              LatexParenInlineSyntax(),
                              MarkdownHighlightInlineSyntax(),
                              HtmlMarkInlineSyntax(),
                              ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
                            ],
                          ),
                          builders: {
                            'latex': _SummaryLatexBuilder(
                              isDark: isDark,
                              textColor: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
                            ),
                            'mark': CommonMarkElementBuilder(
                              isDark: isDark,
                              fontSize: 13.5,
                            ),
                          },
                          styleSheet: MarkdownStyleSheet(
                            p: TextStyle(
                              fontSize: 13.5,
                              height: 1.7,
                              color: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
                            ),
                            h1: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A),
                            ),
                            h2: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A),
                            ),
                            h3: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              color: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A),
                            ),
                            code: TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFEEF2F6),
                              color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                            ),
                            codeblockDecoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEEF2F6),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            codeblockPadding: const EdgeInsets.all(12),
                            listBullet: TextStyle(
                              fontSize: 13.5,
                              color: accentColor,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // 3. Footer Action Bar
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.3) : const Color(0xFFF8FAFC),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                border: Border(
                  top: BorderSide(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    width: 0.8,
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Copy Markdown button
                  IconButton(
                    tooltip: '复制卡片 Markdown',
                    icon: const Icon(Icons.content_copy_rounded, size: 18),
                    onPressed: _copyMarkdown,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: accentColor,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _isGenerating ? null : _handleSave,
                    icon: const Icon(Icons.style_rounded, size: 16),
                    label: const Text('保存为知识卡片', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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

class _SummaryLatexBuilder extends MarkdownElementBuilder {
  final bool isDark;
  final Color textColor;

  _SummaryLatexBuilder({required this.isDark, required this.textColor});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final text = element.textContent.trim();
    if (text.isEmpty) return null;
    final isDisplay = element.attributes['display'] == 'true';

    final latexView = InteractiveLatexView(
      rawLatex: text,
      isDisplay: isDisplay,
      textColor: textColor,
      baseFontSize: 13.5,
      codeBg: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
      isDark: isDark,
      pageNumber: 1,
    );

    if (isDisplay) {
      return latexView;
    }

    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            baseline: TextBaseline.alphabetic,
            child: latexView,
          ),
        ],
      ),
    );
  }
}

