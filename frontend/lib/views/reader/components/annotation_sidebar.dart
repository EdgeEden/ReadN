import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/annotation_model.dart';
import '../../../providers/annotation_provider.dart';
import '../../../providers/document_provider.dart';
import '../../../providers/reader_settings_provider.dart';
import '../../../theme/app_theme.dart';
import 'note_editor_dialog.dart';

class AnnotationSidebar extends StatefulWidget {
  final ValueChanged<int> onJumpToPage;

  const AnnotationSidebar({
    super.key,
    required this.onJumpToPage,
  });

  @override
  State<AnnotationSidebar> createState() => _AnnotationSidebarState();
}

class _AnnotationSidebarState extends State<AnnotationSidebar> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _editAnnotation(BuildContext context, PdfAnnotation anno) {
    final annoProvider = context.read<AnnotationProvider>();
    showDialog(
      context: context,
      builder: (_) => NoteEditorDialog(
        annotation: anno,
        onSave: (updated) {
          annoProvider.updateAnnotation(
            updated.id,
            colorHex: updated.colorHex,
            noteContent: updated.noteContent,
          );
        },
        onDelete: () {
          annoProvider.deleteAnnotation(anno.id);
          final activeDoc = context.read<DocumentProvider>().activeDocument;
          if (activeDoc != null) {
            context.read<DocumentProvider>().updateAnnotationCount(activeDoc.id, -1);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final annoProvider = context.watch<AnnotationProvider>();
    final settings = context.watch<ReaderSettingsProvider>();
    final theme = Theme.of(context);
    final isDark = settings.readingMode == ReadingMode.dark;
    final annotations = annoProvider.filteredAnnotations;

    return Container(
      width: 360,
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        border: Border(
          left: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.06),
            blurRadius: 16,
            offset: const Offset(-4, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4F46E5), Color(0xFF06B6D4)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.edit_note_rounded, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Text(
                  '高亮与批注 (${annoProvider.annotations.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '关闭侧边栏',
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => settings.setSidebarOpen(false),
                ),
              ],
            ),
          ),

          // Search & Filter
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (val) => annoProvider.setFilterQuery(val),
                  decoration: InputDecoration(
                    hintText: '搜索高亮或笔记内容...',
                    hintStyle: const TextStyle(fontSize: 12),
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              annoProvider.setFilterQuery('');
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                      ),
                    ),
                    filled: true,
                    fillColor: theme.scaffoldBackgroundColor,
                  ),
                ),
                const SizedBox(height: 12),
                // Color filter chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      InkWell(
                        onTap: () => annoProvider.setFilterColorHex(null),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: annoProvider.filterColorHex == null
                                ? theme.colorScheme.primary.withValues(alpha: 0.15)
                                : theme.scaffoldBackgroundColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: annoProvider.filterColorHex == null
                                  ? theme.colorScheme.primary
                                  : Colors.transparent,
                            ),
                          ),
                          child: Text(
                            '全部 (${annoProvider.annotations.length})',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: annoProvider.filterColorHex == null
                                  ? theme.colorScheme.primary
                                  : Colors.grey,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ...AppTheme.highlightColors.map((colorItem) {
                        final isSelected = annoProvider.filterColorHex?.toLowerCase() == colorItem.hex.toLowerCase();
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InkWell(
                            onTap: () {
                              if (isSelected) {
                                annoProvider.setFilterColorHex(null);
                              } else {
                                annoProvider.setFilterColorHex(colorItem.hex);
                              }
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: colorItem.color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected
                                      ? (isDark ? Colors.white : Colors.black87)
                                      : Colors.transparent,
                                  width: isSelected ? 2.0 : 1.0,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: colorItem.color.withValues(alpha: 0.5),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : [],
                              ),
                              child: isSelected
                                  ? const Icon(Icons.check_rounded, size: 14, color: Colors.black87)
                                  : null,
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),

          // Annotations List
          Expanded(
            child: annotations.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.draw_rounded,
                            size: 44,
                            color: Colors.grey.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            annoProvider.annotations.isEmpty
                                ? '暂无高亮或批注\n划选 PDF 文字即可一键添加'
                                : '无匹配的批注内容',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(14),
                    itemCount: annotations.length,
                    itemBuilder: (context, index) {
                      final anno = annotations[index];
                      final isFocused = annoProvider.focusedAnnotationId == anno.id;

                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: isFocused
                              ? theme.colorScheme.primary.withValues(alpha: 0.12)
                              : theme.scaffoldBackgroundColor,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isFocused
                                ? theme.colorScheme.primary
                                : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                            width: isFocused ? 1.8 : 1.0,
                          ),
                          boxShadow: isFocused
                              ? [
                                  BoxShadow(
                                    color: theme.colorScheme.primary.withValues(alpha: 0.15),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ]
                              : [],
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            annoProvider.setFocusedAnnotationId(anno.id);
                            widget.onJumpToPage(anno.pageNumber);
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Top line: Page badge, color pill, and actions
                                Row(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: AppTheme.parseHexColor(anno.colorHex),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '第 ${anno.pageNumber} 页',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, size: 16),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      tooltip: '编辑批注',
                                      onPressed: () => _editAnnotation(context, anno),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.red),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      tooltip: '删除',
                                      onPressed: () {
                                        annoProvider.deleteAnnotation(anno.id);
                                        final activeDoc = context.read<DocumentProvider>().activeDocument;
                                        if (activeDoc != null) {
                                          context.read<DocumentProvider>().updateAnnotationCount(activeDoc.id, -1);
                                        }
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                // Highlighted quote text
                                if (anno.selectedText.isNotEmpty)
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: AppTheme.parseHexColor(anno.colorHex, alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border(
                                        left: BorderSide(
                                          color: AppTheme.parseHexColor(anno.colorHex),
                                          width: 3.5,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      '“${anno.selectedText}”',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic,
                                        height: 1.4,
                                        color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
                                      ),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                // Note content if present
                                if (anno.noteContent.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.chat_bubble_outline_rounded, size: 14, color: Color(0xFF818CF8)),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          anno.noteContent,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: theme.colorScheme.onSurface,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
