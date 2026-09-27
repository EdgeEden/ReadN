import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:provider/provider.dart';

import '../../../models/annotation_model.dart';
import '../../../providers/annotation_provider.dart';
import '../../../providers/reader_settings_provider.dart';
import '../../../theme/app_theme.dart';
import 'knowledge_card_dialog.dart';
import 'latex_interactive_view.dart';
import 'markdown_html_support.dart';
import 'markdown_reader_view.dart';

class CardsSidebarTab extends StatefulWidget {
  final int currentPage;
  final ValueChanged<int> onJumpToPage;
  final String docId;
  final void Function(PdfAnnotation anno)? onDeleteAnnotation;

  const CardsSidebarTab({
    super.key,
    required this.currentPage,
    required this.onJumpToPage,
    required this.docId,
    this.onDeleteAnnotation,
  });

  @override
  State<CardsSidebarTab> createState() => _CardsSidebarTabState();
}

class _CardsSidebarTabState extends State<CardsSidebarTab> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openCardDialog(BuildContext context, PdfAnnotation card) {
    showDialog(
      context: context,
      builder: (_) => KnowledgeCardDialog(
        annotation: card,
        pageNumber: card.pageNumber,
        docId: widget.docId,
        onSave: (updated) {
          context.read<AnnotationProvider>().updateAnnotationModel(updated);
        },
        onDelete: () {
          widget.onDeleteAnnotation?.call(card);
        },
        onJumpToPage: widget.onJumpToPage,
      ),
    );
  }

  void _createNewCard(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => KnowledgeCardDialog(
        pageNumber: widget.currentPage,
        docId: widget.docId,
        startInEditMode: true,
        onSave: (newCard) {
          context.read<AnnotationProvider>().addAnnotation(newCard);
        },
        onJumpToPage: widget.onJumpToPage,
      ),
    );
  }

  void _copyCardMarkdown(BuildContext context, PdfAnnotation card) {
    final sb = StringBuffer();
    sb.writeln('### 知识卡片 (第 ${card.pageNumber} 页)');
    if (card.selectedText.trim().isNotEmpty) {
      sb.writeln();
      sb.writeln('> 引用: ${card.selectedText.trim()}');
    }
    sb.writeln();
    sb.writeln(card.noteContent.trim());

    Clipboard.setData(ClipboardData(text: sb.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF86EFAC), size: 18),
            SizedBox(width: 8),
            Text('已复制该知识卡片 Markdown'),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final annoProvider = context.watch<AnnotationProvider>();
    final settings = context.watch<ReaderSettingsProvider>();
    final isDark = settings.readingMode == ReadingMode.dark;
    final isSepia = settings.readingMode == ReadingMode.sepia;

    final cards = annoProvider.annotations.where((a) => a.isCard).toList();

    // Filter cards
    final filtered = cards.where((c) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return c.selectedText.toLowerCase().contains(q) ||
          c.noteContent.toLowerCase().contains(q) ||
          c.pageNumber.toString().contains(q);
    }).toList();

    return Column(
      children: [
        // 1. Search Bar & "新建卡片" Action Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _searchController,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: '搜索知识卡片 (内容 / 引用)...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withValues(alpha: isDark ? 0.25 : 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '共 ${cards.length} 张知识卡片',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF8B5CF6),
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('新建卡片', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    onPressed: () => _createNewCard(context),
                  ),
                ],
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        // 2. Card List View
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6).withValues(alpha: isDark ? 0.2 : 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.style_rounded,
                            size: 36,
                            color: Color(0xFF8B5CF6),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          cards.isEmpty ? '暂无知识卡片' : '未找到匹配卡片',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          cards.isEmpty
                              ? '在 AI 问答后，可点击“保存为知识卡片”或“总结并保存”，将要点提炼为结构化卡片随时复习。'
                              : '尝试更换搜索关键词',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                          ),
                        ),
                        if (cards.isEmpty) ...[
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF8B5CF6),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: const Text('手动新建卡片', style: TextStyle(fontSize: 12)),
                            onPressed: () => _createNewCard(context),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final card = filtered[index];
                    final isCurrentPage = card.pageNumber == widget.currentPage;
                    final cardColor = AppTheme.parseHexColor(card.colorHex);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E293B)
                            : (isSepia ? const Color(0xFFF7EED9) : Colors.white),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isCurrentPage
                              ? const Color(0xFF8B5CF6)
                              : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                          width: isCurrentPage ? 1.6 : 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: InkWell(
                        onTap: () => _openCardDialog(context, card),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Top Bar: Page Badge + Time
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: cardColor.withValues(alpha: isDark ? 0.35 : 0.2),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '第 ${card.pageNumber} 页',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                        color: cardColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      card.displayTitle,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: '复制 Markdown',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                    icon: const Icon(Icons.content_copy_rounded, size: 15),
                                    onPressed: () => _copyCardMarkdown(context, card),
                                  ),
                                  IconButton(
                                    tooltip: '编辑卡片',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                    icon: const Icon(Icons.edit_rounded, size: 15),
                                    onPressed: () => _openCardDialog(context, card),
                                  ),
                                ],
                              ),

                              // Quoted Excerpt Box
                              if (card.selectedText.trim().isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(5),
                                    child: IntrinsicHeight(
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          Container(
                                            width: 3.5,
                                            color: cardColor,
                                          ),
                                          Expanded(
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                              child: Text(
                                                '“${card.selectedText.trim()}”',
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  fontStyle: FontStyle.italic,
                                                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],

                              // Card Markdown Preview Snippet
                              const SizedBox(height: 8),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 90),
                                child: ClipRect(
                                  child: MarkdownBody(
                                    data: card.noteContent.trim(),
                                    selectable: false,
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
                                      'latex': _CardsSidebarLatexBuilder(
                                        isDark: isDark,
                                        textColor: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
                                      ),
                                      'mark': CommonMarkElementBuilder(
                                        isDark: isDark,
                                        fontSize: 12,
                                      ),
                                    },
                                    styleSheet: MarkdownStyleSheet(
                                      p: TextStyle(
                                        fontSize: 12,
                                        height: 1.5,
                                        color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
                                      ),
                                      code: TextStyle(
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                        backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFEEF2F6),
                                        color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 8),
                              // Bottom Jump Action
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    icon: const Icon(Icons.near_me_rounded, size: 14),
                                    label: Text(
                                      '跳转第 ${card.pageNumber} 页',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                    onPressed: () => widget.onJumpToPage(card.pageNumber),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _CardsSidebarLatexBuilder extends MarkdownElementBuilder {
  final bool isDark;
  final Color textColor;

  _CardsSidebarLatexBuilder({required this.isDark, required this.textColor});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final text = element.textContent.trim();
    if (text.isEmpty) return null;
    final isDisplay = element.attributes['display'] == 'true';

    return InteractiveLatexView(
      rawLatex: text,
      isDisplay: isDisplay,
      textColor: textColor,
      baseFontSize: 12,
      codeBg: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
      isDark: isDark,
      pageNumber: 1,
    );
  }
}
