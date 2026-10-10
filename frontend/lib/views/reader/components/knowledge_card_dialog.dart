import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:uuid/uuid.dart';

import '../../../models/annotation_model.dart';
import '../../../theme/app_theme.dart';
import 'latex_interactive_view.dart';
import 'markdown_html_support.dart';
import 'markdown_reader_view.dart';

/// Interactive Modal Dialog to view, edit, or create a rich Markdown Knowledge Card
class KnowledgeCardDialog extends StatefulWidget {
  final PdfAnnotation? annotation;
  final String? initialQuote;
  final String? initialContent;
  final int pageNumber;
  final String docId;
  final ValueChanged<PdfAnnotation>? onSave;
  final VoidCallback? onDelete;
  final ValueChanged<int>? onJumpToPage;
  final bool startInEditMode;

  const KnowledgeCardDialog({
    super.key,
    this.annotation,
    this.initialQuote,
    this.initialContent,
    required this.pageNumber,
    required this.docId,
    this.onSave,
    this.onDelete,
    this.onJumpToPage,
    this.startInEditMode = false,
  });

  @override
  State<KnowledgeCardDialog> createState() => _KnowledgeCardDialogState();
}

class _KnowledgeCardDialogState extends State<KnowledgeCardDialog> {
  late TextEditingController _contentController;
  late TextEditingController _quoteController;
  late String _selectedColor;
  late bool _isEditing;
  final Uuid _uuid = const Uuid();

  static const List<String> _cardColorPresets = [
    '#8B5CF6', // Purple / AI
    '#6366F1', // Indigo
    '#3B82F6', // Blue
    '#10B981', // Emerald
    '#F59E0B', // Amber
    '#EC4899', // Pink
  ];

  @override
  void initState() {
    super.initState();
    final initialContent = widget.annotation?.noteContent ?? widget.initialContent ?? '';
    final initialQuote = widget.annotation?.selectedText ?? widget.initialQuote ?? '';
    _contentController = TextEditingController(text: initialContent);
    _quoteController = TextEditingController(text: initialQuote);
    _selectedColor = widget.annotation?.colorHex ?? '#8B5CF6';
    _isEditing = widget.startInEditMode || initialContent.trim().isEmpty;
  }

  @override
  void dispose() {
    _contentController.dispose();
    _quoteController.dispose();
    super.dispose();
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

    final card = widget.annotation?.copyWith(
          colorHex: _selectedColor,
          selectedText: quote,
          noteContent: content,
          type: "card",
          updatedAt: now,
        ) ??
        PdfAnnotation(
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
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 680),
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
                      color: accentColor.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.style_rounded, size: 20, color: accentColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '知识卡片',
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
                          widget.annotation?.updatedAt != null
                              ? '更新于: ${widget.annotation!.updatedAt.toLocal().toString().substring(0, 16)}'
                              : 'AI 总结与要点提炼卡片 (Markdown 格式)',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Mode Toggle (View / Edit)
                  IconButton(
                    tooltip: _isEditing ? '预览卡片' : '编辑卡片',
                    icon: Icon(
                      _isEditing ? Icons.visibility_rounded : Icons.edit_rounded,
                      size: 20,
                      color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                    ),
                    onPressed: () => setState(() => _isEditing = !_isEditing),
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

                    // Markdown Content Editor or Formatted Viewer
                    if (_isEditing) ...[
                      TextField(
                        controller: _contentController,
                        maxLines: 12,
                        minLines: 6,
                        style: const TextStyle(fontSize: 13, height: 1.6, fontFamily: 'monospace'),
                        decoration: InputDecoration(
                          labelText: '卡片正文 (支持 Markdown & LaTeX 公式)',
                          alignLabelWithHint: true,
                          hintText: '输入要点、概念解析、代码或 LaTeX 数学公式...\n例如: \n## 核心原理\n- 公式: \$\$E = mc^2\$\$\n- 要点提炼...',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Color Preset Selector in Edit Mode
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
                                      color: isChosen
                                          ? (isDark ? Colors.white : Colors.black87)
                                          : Colors.transparent,
                                      width: isChosen ? 2.5 : 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: color.withValues(alpha: 0.4),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                  child: isChosen
                                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                                      : null,
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ] else ...[
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
                              : '*（卡片内容为空）*',
                          selectable: true,
                          softLineBreak: true,
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
                            'latex': _CardLatexBuilder(
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
                  // Jump to page in reader
                  if (widget.onJumpToPage != null)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.location_on_rounded, size: 16),
                      label: Text('跳转第 ${widget.pageNumber} 页', style: const TextStyle(fontSize: 12)),
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onJumpToPage?.call(widget.pageNumber);
                      },
                    ),

                  const SizedBox(width: 8),
                  // Copy Markdown button
                  IconButton(
                    tooltip: '复制卡片 Markdown',
                    icon: const Icon(Icons.content_copy_rounded, size: 18),
                    onPressed: _copyMarkdown,
                  ),

                  // Delete button (if existing annotation)
                  if (widget.annotation != null && widget.onDelete != null)
                    IconButton(
                      tooltip: '删除卡片',
                      icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onDelete?.call();
                      },
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
                    onPressed: _handleSave,
                    icon: const Icon(Icons.save_rounded, size: 16),
                    label: const Text('保存卡片', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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

class _CardLatexBuilder extends MarkdownElementBuilder {
  final bool isDark;
  final Color textColor;

  _CardLatexBuilder({required this.isDark, required this.textColor});

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

