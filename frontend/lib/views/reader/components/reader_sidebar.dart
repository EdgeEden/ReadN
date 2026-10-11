import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/annotation_model.dart';
import '../../../providers/annotation_provider.dart';
import '../../../providers/document_provider.dart';
import '../../../providers/reader_settings_provider.dart';
import '../../../theme/app_theme.dart';
import 'ai_chat_sidebar_tab.dart';
import 'cards_sidebar_tab.dart';
import 'note_editor_dialog.dart';
import 'page_jump_dialog.dart';

class OutlineItem {
  final String title;
  final int pageNumber;
  final int level;
  final List<OutlineItem> children;

  const OutlineItem({
    required this.title,
    required this.pageNumber,
    this.level = 1,
    this.children = const [],
  });
}

class SearchResultItem {
  final int pageNumber;
  final int matchCount;
  final String snippet;

  const SearchResultItem({
    required this.pageNumber,
    required this.matchCount,
    required this.snippet,
  });
}

class ReaderSidebar extends StatefulWidget {
  final SidebarDockPosition position;
  final bool isMobileSheet;
  final ReaderSidebarTab? initialTab;
  final VoidCallback? onClose;
  final List<OutlineItem> outlineItems;
  final bool isOutlineLoading;
  final String searchQuery;
  final List<SearchResultItem> searchResults;
  final bool isSearching;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<int> onJumpToPage;
  final int currentPage;
  final int totalPages;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onResetZoom;
  final VoidCallback? onFitWidth;
  final void Function(PdfAnnotation anno)? onDeleteAnnotation;
  final String documentTitle;
  final String docId;
  final Future<String?> Function(int pageNumber)? onGetPageContext;
  final void Function(int pageNumber)? onAddNewNote;

  const ReaderSidebar({
    super.key,
    this.position = SidebarDockPosition.left,
    this.isMobileSheet = false,
    this.initialTab,
    this.onClose,
    required this.outlineItems,
    this.isOutlineLoading = false,
    required this.searchQuery,
    required this.searchResults,
    this.isSearching = false,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onJumpToPage,
    required this.currentPage,
    required this.totalPages,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onResetZoom,
    this.onFitWidth,
    this.onDeleteAnnotation,
    this.documentTitle = '',
    this.docId = '',
    this.onGetPageContext,
    this.onAddNewNote,
  });

  @override
  State<ReaderSidebar> createState() => _ReaderSidebarState();
}

class _ReaderSidebarState extends State<ReaderSidebar> {
  final TextEditingController _localSearchController = TextEditingController();
  final TextEditingController _annoSearchController = TextEditingController();
  final TextEditingController _outlineFilterController = TextEditingController();
  String _outlineFilterText = '';
  ReaderSidebarTab? _mobileActiveTab;

  @override
  void initState() {
    super.initState();
    _localSearchController.text = widget.searchQuery;
    if (widget.isMobileSheet) {
      _mobileActiveTab = widget.initialTab ?? ReaderSidebarTab.outline;
    }
  }

  @override
  void didUpdateWidget(covariant ReaderSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery && _localSearchController.text != widget.searchQuery) {
      _localSearchController.text = widget.searchQuery;
    }
    if (widget.isMobileSheet && widget.initialTab != null && widget.initialTab != oldWidget.initialTab) {
      setState(() {
        _mobileActiveTab = widget.initialTab;
      });
    }
  }

  @override
  void dispose() {
    _localSearchController.dispose();
    _annoSearchController.dispose();
    _outlineFilterController.dispose();
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
          if (widget.onDeleteAnnotation != null) {
            widget.onDeleteAnnotation!(anno);
          } else {
            annoProvider.deleteAnnotation(anno.id);
            final activeDoc = context.read<DocumentProvider>().activeDocument;
            if (activeDoc != null) {
              context.read<DocumentProvider>().updateAnnotationCount(activeDoc.id, -1);
            }
          }
        },
      ),
    );
  }

  Widget _buildMobileDragHandle(BuildContext context, ThemeData theme, bool isDark, bool isSepia) {
    Color handleBg;
    Color barColor;
    if (isDark) {
      handleBg = const Color(0xFF1E293B);
      barColor = Colors.white24;
    } else if (isSepia) {
      handleBg = const Color(0xFFF4ECD8);
      barColor = const Color(0x40B45309);
    } else {
      handleBg = const Color(0xFFF8FAFC);
      barColor = Colors.black26;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      color: handleBg,
      alignment: Alignment.center,
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: barColor,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<ReaderSettingsProvider>();
    final theme = Theme.of(context);
    final isDark = settings.readingMode == ReadingMode.dark;
    final isSepia = settings.readingMode == ReadingMode.sepia;
    final isLeft = widget.position == SidebarDockPosition.left;

    final dockedTabs = widget.isMobileSheet
        ? ReaderSidebarTab.values
        : (isLeft ? settings.leftDockedTabs : settings.rightDockedTabs);
    final activeTab = widget.isMobileSheet
        ? (_mobileActiveTab ?? widget.initialTab ?? ReaderSidebarTab.outline)
        : (isLeft ? settings.activeLeftTab : settings.activeRightTab);

    if (dockedTabs.isEmpty) {
      return const SizedBox.shrink();
    }

    final borderColor = isDark
        ? const Color(0xFF334155)
        : (isSepia ? const Color(0xFFD6C8AF) : const Color(0xFFE2E8F0));

    return Container(
      width: widget.isMobileSheet ? double.infinity : 340,
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        border: widget.isMobileSheet
            ? null
            : Border(
                left: !isLeft
                    ? BorderSide(
                        color: borderColor,
                        width: 1,
                      )
                    : BorderSide.none,
                right: isLeft
                    ? BorderSide(
                        color: borderColor,
                        width: 1,
                      )
                    : BorderSide.none,
              ),
        boxShadow: widget.isMobileSheet
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.05),
                  blurRadius: 14,
                  offset: Offset(isLeft ? 4 : -4, 0),
                ),
              ],
      ),
      child: Column(
        children: [
          if (widget.isMobileSheet)
            _buildMobileDragHandle(context, theme, isDark, isSepia),

          // 1. Sidebar Tab Header
          _buildTabHeader(context, theme, isDark, isSepia, isLeft, dockedTabs, activeTab, settings),

          // 2. Active Tab Body
          Expanded(
            child: _buildActiveTabContent(context, theme, isDark, isLeft, activeTab),
          ),

          // 3. Fixed Bottom Controls (Left Sidebar Only: Page & Zoom)
          if (isLeft && !widget.isMobileSheet)
            _buildLeftBottomBar(context, theme, isDark, isSepia, settings),
        ],
      ),
    );
  }

  Widget _buildTabHeader(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    bool isSepia,
    bool isLeft,
    List<ReaderSidebarTab> dockedTabs,
    ReaderSidebarTab activeTab,
    ReaderSettingsProvider settings,
  ) {
    final annoProvider = context.watch<AnnotationProvider>();

    Color headerBg;
    Color headerBorder;
    if (isDark) {
      headerBg = const Color(0xFF1E293B);
      headerBorder = const Color(0xFF334155);
    } else if (isSepia) {
      headerBg = const Color(0xFFF4ECD8);
      headerBorder = const Color(0xFFD6C8AF);
    } else {
      headerBg = const Color(0xFFF8FAFC);
      headerBorder = const Color(0xFFE2E8F0);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: headerBg,
        border: Border(
          bottom: BorderSide(
            color: headerBorder,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Docked Tab Chips
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: dockedTabs.map((tab) {
                  final isSelected = activeTab == tab;
                  int? badgeCount;
                  if (tab == ReaderSidebarTab.highlights) {
                    badgeCount = annoProvider.annotations.where((a) => a.isHighlight).length;
                  } else if (tab == ReaderSidebarTab.notes) {
                    badgeCount = annoProvider.annotations.where((a) => a.isNote).length;
                  } else if (tab == ReaderSidebarTab.cards) {
                    badgeCount = annoProvider.annotations.where((a) => a.isCard).length;
                  } else if (tab == ReaderSidebarTab.search && widget.searchResults.isNotEmpty) {
                    badgeCount = widget.searchResults.length;
                  } else if (tab == ReaderSidebarTab.outline && widget.outlineItems.isNotEmpty) {
                    badgeCount = widget.outlineItems.length;
                  }

                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        if (widget.isMobileSheet) {
                          setState(() {
                            _mobileActiveTab = tab;
                          });
                        } else if (isLeft) {
                          settings.setActiveLeftTab(tab);
                        } else {
                          settings.setActiveRightTab(tab);
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? theme.colorScheme.primary.withValues(alpha: isDark ? 0.25 : 0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? theme.colorScheme.primary.withValues(alpha: 0.5)
                                : Colors.transparent,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              tab.icon,
                              size: 16,
                              color: isSelected ? theme.colorScheme.primary : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              tab.label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? theme.colorScheme.primary : (isDark ? Colors.grey.shade300 : Colors.grey.shade700),
                              ),
                            ),
                            if (badgeCount != null && badgeCount > 0) ...[
                              const SizedBox(width: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? theme.colorScheme.primary
                                      : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$badgeCount',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected ? Colors.white : (isDark ? Colors.grey.shade300 : Colors.grey.shade700),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // Dock Move Button (Move current tab to the other sidebar) - Hidden in mobile sheet mode
          if (!widget.isMobileSheet)
            Tooltip(
              message: isLeft ? '停靠到右边栏' : '停靠到左边栏',
              child: IconButton(
                icon: Icon(
                  isLeft ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded,
                  size: 18,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () {
                  if (isLeft) {
                    settings.dockTabToRight(activeTab);
                  } else {
                    settings.dockTabToLeft(activeTab);
                  }
                },
              ),
            ),

          // Close / Collapse Sidebar Button
          if (widget.isMobileSheet)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: '关闭',
              onPressed: () {
                if (widget.onClose != null) {
                  widget.onClose!();
                } else {
                  Navigator.of(context).pop();
                }
              },
            )
          else
            Tooltip(
              message: isLeft ? '收起左边栏' : '收起右边栏',
              child: IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () {
                  if (isLeft) {
                    settings.setLeftSidebarOpen(false);
                  } else {
                    settings.setRightSidebarOpen(false);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActiveTabContent(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    bool isLeft,
    ReaderSidebarTab activeTab,
  ) {
    switch (activeTab) {
      case ReaderSidebarTab.outline:
        return _buildOutlineTab(context, theme, isDark);
      case ReaderSidebarTab.search:
        return _buildSearchTab(context, theme, isDark);
      case ReaderSidebarTab.highlights:
        return _buildHighlightsTab(context, theme, isDark);
      case ReaderSidebarTab.notes:
        return _buildNotesTab(context, theme, isDark);
      case ReaderSidebarTab.cards:
        return CardsSidebarTab(
          currentPage: widget.currentPage,
          onJumpToPage: widget.onJumpToPage,
          docId: widget.docId,
          onDeleteAnnotation: widget.onDeleteAnnotation,
        );
      case ReaderSidebarTab.aiChat:
        return AiChatSidebarTab(
          currentPage: widget.currentPage,
          totalPages: widget.totalPages,
          documentTitle: widget.documentTitle,
          onGetPageContext: widget.onGetPageContext,
        );
    }
  }

  // -------------------------------------------------------------
  // Tab 1: 目录 (Outline / Table of Contents)
  // -------------------------------------------------------------
  Widget _buildOutlineTab(BuildContext context, ThemeData theme, bool isDark) {
    if (widget.isOutlineLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (widget.outlineItems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_book_rounded, size: 44, color: Colors.grey.withValues(alpha: 0.4)),
              const SizedBox(height: 12),
              const Text(
                '暂未检测到目录书签',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                '如为扫描件或无目录 PDF，可通过顶部“生成双层PDF”提取标题大纲',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      );
    }

    // Filter outline by keyword if provided
    final filtered = _outlineFilterText.isEmpty
        ? widget.outlineItems
        : widget.outlineItems.where((item) => item.title.toLowerCase().contains(_outlineFilterText.toLowerCase())).toList();

    return Column(
      children: [
        // Quick filter input
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: TextField(
            controller: _outlineFilterController,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              hintText: '筛选章节标题...',
              hintStyle: const TextStyle(fontSize: 12),
              prefixIcon: const Icon(Icons.filter_list_rounded, size: 16),
              suffixIcon: _outlineFilterText.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 14),
                      onPressed: () {
                        _outlineFilterController.clear();
                        setState(() => _outlineFilterText = '');
                      },
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                ),
              ),
              filled: true,
              fillColor: theme.scaffoldBackgroundColor,
            ),
            onChanged: (val) => setState(() => _outlineFilterText = val.trim()),
          ),
        ),

        // Outline Items List
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            itemCount: filtered.length,
            separatorBuilder: (_, _) => const SizedBox(height: 2),
            itemBuilder: (ctx, index) {
              final item = filtered[index];
              final isCurrent = widget.currentPage == item.pageNumber;

              return InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => widget.onJumpToPage(item.pageNumber),
                child: Container(
                  padding: EdgeInsets.only(
                    left: (item.level - 1) * 14.0 + 8.0,
                    right: 8.0,
                    top: 8.0,
                    bottom: 8.0,
                  ),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? theme.colorScheme.primary.withValues(alpha: isDark ? 0.2 : 0.08)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: isCurrent
                        ? Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.4))
                        : null,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        item.level == 1
                            ? Icons.bookmark_rounded
                            : (item.level == 2 ? Icons.label_important_outline_rounded : Icons.subdirectory_arrow_right_rounded),
                        size: 14,
                        color: isCurrent ? theme.colorScheme.primary : (item.level == 1 ? theme.colorScheme.primary : Colors.grey),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.title,
                          style: TextStyle(
                            fontSize: item.level == 1 ? 13 : 12,
                            fontWeight: (item.level == 1 || isCurrent) ? FontWeight.bold : FontWeight.normal,
                            color: isCurrent
                                ? theme.colorScheme.primary
                                : (isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B)),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? theme.colorScheme.primary
                              : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'P.${item.pageNumber}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isCurrent ? Colors.white : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------
  // Tab 2: 检索 (Search / Full Text)
  // -------------------------------------------------------------
  Widget _buildSearchTab(BuildContext context, ThemeData theme, bool isDark) {
    return Column(
      children: [
        // Search Input Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _localSearchController,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: '全文关键词检索...',
                  hintStyle: const TextStyle(fontSize: 12),
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  suffixIcon: _localSearchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 16),
                          onPressed: () {
                            _localSearchController.clear();
                            widget.onClearSearch();
                          },
                        )
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                    ),
                  ),
                  filled: true,
                  fillColor: theme.scaffoldBackgroundColor,
                ),
                onSubmitted: widget.onSearchChanged,
                onChanged: (val) {
                  setState(() {});
                  widget.onSearchChanged(val);
                },
              ),
              if (widget.searchQuery.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.searchResults.isNotEmpty
                          ? '检索到 ${widget.searchResults.fold<int>(0, (sum, r) => sum + r.matchCount)} 处匹配 (${widget.searchResults.length} 个页面)'
                          : (widget.isSearching ? '正在检索文档...' : '未找到匹配结果'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: widget.searchResults.isNotEmpty ? theme.colorScheme.primary : Colors.grey,
                      ),
                    ),
                    if (widget.isSearching)
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),

        // Search Results List
        Expanded(
          child: widget.searchResults.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off_rounded, size: 40, color: Colors.grey.withValues(alpha: 0.4)),
                        const SizedBox(height: 10),
                        Text(
                          widget.searchQuery.isEmpty ? '输入关键词即可在全书检索' : '无匹配结果',
                          style: const TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: widget.searchResults.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (ctx, index) {
                    final item = widget.searchResults[index];
                    final isCurrent = widget.currentPage == item.pageNumber;

                    return InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => widget.onJumpToPage(item.pageNumber),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? theme.colorScheme.primary.withValues(alpha: isDark ? 0.2 : 0.08)
                              : theme.scaffoldBackgroundColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isCurrent
                                ? theme.colorScheme.primary
                                : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '第 ${item.pageNumber} 页',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${item.matchCount} 处匹配',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                                const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Colors.grey),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              item.snippet,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------
  // Tab 3: 高亮 (Highlights List)
  // -------------------------------------------------------------
  Widget _buildHighlightsTab(BuildContext context, ThemeData theme, bool isDark) {
    final annoProvider = context.watch<AnnotationProvider>();
    final highlights = annoProvider.filteredAnnotations.where((a) => !a.isNote).toList();

    return Column(
      children: [
        _buildAnnotationSearchAndFilter(context, theme, isDark, annoProvider, isNotesOnly: false),
        const Divider(height: 1),
        Expanded(
          child: highlights.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.brush_rounded, size: 40, color: Colors.grey.withValues(alpha: 0.4)),
                        const SizedBox(height: 10),
                        const Text(
                          '暂无荧光高亮\n在阅读界面划选文字即可一键高亮',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: highlights.length,
                  itemBuilder: (ctx, index) {
                    final anno = highlights[index];
                    final isFocused = annoProvider.focusedAnnotationId == anno.id;

                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: isFocused
                            ? theme.colorScheme.primary.withValues(alpha: 0.12)
                            : theme.scaffoldBackgroundColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isFocused
                              ? theme.colorScheme.primary
                              : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                          width: isFocused ? 1.6 : 1.0,
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          annoProvider.setFocusedAnnotationId(anno.id);
                          widget.onJumpToPage(anno.pageNumber);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
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
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '第 ${anno.pageNumber} 页',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  // Edit into Note / Delete
                                  IconButton(
                                    icon: const Icon(Icons.edit_note_rounded, size: 16),
                                    tooltip: '转为批注 / 添加笔记',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                    onPressed: () => _editAnnotation(context, anno),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                                    tooltip: '删除高亮',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                    onPressed: () {
                                      if (widget.onDeleteAnnotation != null) {
                                        widget.onDeleteAnnotation!(anno);
                                      } else {
                                        annoProvider.deleteAnnotation(anno.id);
                                        final activeDoc = context.read<DocumentProvider>().activeDocument;
                                        if (activeDoc != null) {
                                          context.read<DocumentProvider>().updateAnnotationCount(activeDoc.id, -1);
                                        }
                                      }
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Container(
                                decoration: BoxDecoration(
                                  color: AppTheme.parseHexColor(anno.colorHex).withValues(alpha: isDark ? 0.15 : 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: AppTheme.parseHexColor(anno.colorHex).withValues(alpha: 0.35),
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
                                          width: 3,
                                          color: AppTheme.parseHexColor(anno.colorHex),
                                        ),
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                            child: Text(
                                              anno.selectedText,
                                              style: TextStyle(
                                                fontSize: 12,
                                                height: 1.4,
                                                color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
                                              ),
                                              maxLines: 4,
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

  // -------------------------------------------------------------
  // Tab 4: 批注 (Notes / Comments List)
  // -------------------------------------------------------------
  Widget _buildNotesTab(BuildContext context, ThemeData theme, bool isDark) {
    final annoProvider = context.watch<AnnotationProvider>();
    final notes = annoProvider.filteredAnnotations.where((a) => a.isNote).toList();

    return Column(
      children: [
        if (widget.onAddNewNote != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: Text(
                  '在第 ${widget.currentPage} 页添加批注',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                onPressed: () => widget.onAddNewNote?.call(widget.currentPage),
              ),
            ),
          ),
        _buildAnnotationSearchAndFilter(context, theme, isDark, annoProvider, isNotesOnly: true),
        const Divider(height: 1),
        Expanded(
          child: notes.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_note_rounded, size: 40, color: Colors.grey.withValues(alpha: 0.4)),
                        const SizedBox(height: 10),
                        const Text(
                          '暂无批注笔记\n可在任意位置右键/长按或点击上方按钮添加',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                        if (widget.onAddNewNote != null) ...[
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.add_rounded, size: 15),
                            label: Text('在第 ${widget.currentPage} 页写批注'),
                            onPressed: () => widget.onAddNewNote?.call(widget.currentPage),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: notes.length,
                  itemBuilder: (ctx, index) {
                    final anno = notes[index];
                    final isFocused = annoProvider.focusedAnnotationId == anno.id;

                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: isFocused
                            ? theme.colorScheme.primary.withValues(alpha: 0.12)
                            : theme.scaffoldBackgroundColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isFocused
                              ? theme.colorScheme.primary
                              : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                          width: isFocused ? 1.6 : 1.0,
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          annoProvider.setFocusedAnnotationId(anno.id);
                          widget.onJumpToPage(anno.pageNumber);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
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
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '第 ${anno.pageNumber} 页',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    icon: const Icon(Icons.edit_rounded, size: 16),
                                    tooltip: '编辑笔记',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                    onPressed: () => _editAnnotation(context, anno),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                                    tooltip: '删除笔记',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                    onPressed: () {
                                      if (widget.onDeleteAnnotation != null) {
                                        widget.onDeleteAnnotation!(anno);
                                      } else {
                                        annoProvider.deleteAnnotation(anno.id);
                                        final activeDoc = context.read<DocumentProvider>().activeDocument;
                                        if (activeDoc != null) {
                                          context.read<DocumentProvider>().updateAnnotationCount(activeDoc.id, -1);
                                        }
                                      }
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // Note Content Card
                              Text(
                                anno.noteContent,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  height: 1.4,
                                ),
                              ),
                              if (anno.selectedText.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '引文: “${anno.selectedText}”',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic,
                                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
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
    );
  }

  Widget _buildAnnotationSearchAndFilter(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    AnnotationProvider annoProvider, {
    required bool isNotesOnly,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        children: [
          TextField(
            controller: _annoSearchController,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              hintText: isNotesOnly ? '搜索批注内容与引文...' : '搜索高亮引文...',
              hintStyle: const TextStyle(fontSize: 12),
              prefixIcon: const Icon(Icons.search_rounded, size: 16),
              suffixIcon: _annoSearchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 14),
                      onPressed: () {
                        _annoSearchController.clear();
                        annoProvider.setFilterQuery('');
                      },
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                ),
              ),
              filled: true,
              fillColor: theme.scaffoldBackgroundColor,
            ),
            onChanged: (val) => annoProvider.setFilterQuery(val),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                InkWell(
                  onTap: () => annoProvider.setFilterColorHex(null),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: annoProvider.filterColorHex == null
                          ? theme.colorScheme.primary.withValues(alpha: 0.15)
                          : theme.scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: annoProvider.filterColorHex == null
                            ? theme.colorScheme.primary
                            : Colors.transparent,
                      ),
                    ),
                    child: Text(
                      '全部',
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
                const SizedBox(width: 6),
                ...AppTheme.highlightColors.map((colorItem) {
                  final isSelected = annoProvider.filterColorHex?.toLowerCase() == colorItem.hex.toLowerCase();
                  return Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: InkWell(
                      onTap: () {
                        if (isSelected) {
                          annoProvider.setFilterColorHex(null);
                        } else {
                          annoProvider.setFilterColorHex(colorItem.hex);
                        }
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: colorItem.color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? (isDark ? Colors.white : Colors.black87)
                                : Colors.transparent,
                            width: isSelected ? 2.0 : 1.0,
                          ),
                        ),
                        child: isSelected
                            ? const Icon(Icons.check_rounded, size: 12, color: Colors.black87)
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
    );
  }

  // -------------------------------------------------------------
  // 3. Fixed Bottom Bar (Page Navigator & Zoom Control on Left Sidebar)
  // -------------------------------------------------------------
  Widget _buildLeftBottomBar(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    bool isSepia,
    ReaderSettingsProvider settings,
  ) {
    final totalPages = widget.totalPages > 0 ? widget.totalPages : 1;

    Color barBg;
    Color barBorder;
    if (isDark) {
      barBg = const Color(0xFF1E293B);
      barBorder = const Color(0xFF334155);
    } else if (isSepia) {
      barBg = const Color(0xFFF4ECD8);
      barBorder = const Color(0xFFD6C8AF);
    } else {
      barBg = const Color(0xFFF8FAFC);
      barBorder = const Color(0xFFE2E8F0);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: barBg,
        border: Border(
          top: BorderSide(
            color: barBorder,
            width: 1,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Page Navigation
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: '上一页 (P.${widget.currentPage > 1 ? widget.currentPage - 1 : 1})',
                onPressed: widget.currentPage > 1 ? () => widget.onJumpToPage(widget.currentPage - 1) : null,
              ),
              Tooltip(
                message: '点击跳转页面 (共 $totalPages 页)',
                child: InkWell(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (_) => PageJumpDialog(
                        currentPage: widget.currentPage,
                        totalPages: totalPages,
                        onJump: widget.onJumpToPage,
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: isDark ? 0.2 : 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: theme.colorScheme.primary.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_stories_rounded, size: 14, color: theme.colorScheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          '第 ${widget.currentPage} / $totalPages 页',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: '下一页 (P.${widget.currentPage < totalPages ? widget.currentPage + 1 : totalPages})',
                onPressed: widget.currentPage < totalPages ? () => widget.onJumpToPage(widget.currentPage + 1) : null,
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Row 2: Zoom Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_rounded, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: '缩小 (20%)',
                onPressed: widget.onZoomOut,
              ),
              Tooltip(
                message: '点击重置缩放 (100%)',
                child: InkWell(
                  onTap: widget.onResetZoom,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      '${(settings.zoomScale * 100).toInt()}%',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_rounded, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: '放大 (20%)',
                onPressed: widget.onZoomIn,
              ),
              if (widget.onFitWidth != null)
                IconButton(
                  icon: const Icon(Icons.fit_screen_rounded, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: '适应页面宽度',
                  onPressed: widget.onFitWidth,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
