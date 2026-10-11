import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/annotation_model.dart';
import '../../../providers/reader_settings_provider.dart';
import '../../../theme/app_theme.dart';
import 'page_jump_dialog.dart';
import 'reader_sidebar.dart';

/// 移动端综合抽屉面板 (目录、检索、高亮、批注、卡片、AI 伴读)
class ReaderMobileBottomSheet {
  static Future<void> show({
    required BuildContext context,
    required ReaderSidebarTab initialTab,
    required List<OutlineItem> outlineItems,
    bool isOutlineLoading = false,
    required String searchQuery,
    required List<SearchResultItem> searchResults,
    bool isSearching = false,
    required ValueChanged<String> onSearchChanged,
    required VoidCallback onClearSearch,
    required ValueChanged<int> onJumpToPage,
    required int currentPage,
    required int totalPages,
    required VoidCallback onZoomIn,
    required VoidCallback onZoomOut,
    required VoidCallback onResetZoom,
    VoidCallback? onFitWidth,
    void Function(PdfAnnotation anno)? onDeleteAnnotation,
    String documentTitle = '',
    String docId = '',
    Future<String?> Function(int pageNumber)? onGetPageContext,
    void Function(int pageNumber)? onAddNewNote,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (sheetContext) {
        final settings = sheetContext.watch<ReaderSettingsProvider>();
        final activeTheme = settings.readingMode == ReadingMode.dark
            ? AppTheme.darkTheme
            : (settings.readingMode == ReadingMode.sepia ? AppTheme.sepiaTheme : AppTheme.lightTheme);

        return Theme(
          data: activeTheme,
          child: FractionallySizedBox(
            heightFactor: 0.85,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: ReaderSidebar(
                isMobileSheet: true,
                initialTab: initialTab,
                outlineItems: outlineItems,
                isOutlineLoading: isOutlineLoading,
                searchQuery: searchQuery,
                searchResults: searchResults,
                isSearching: isSearching,
                onSearchChanged: onSearchChanged,
                onClearSearch: onClearSearch,
                onJumpToPage: (page) {
                  Navigator.of(sheetContext).pop();
                  onJumpToPage(page);
                },
                currentPage: currentPage,
                totalPages: totalPages,
                onZoomIn: onZoomIn,
                onZoomOut: onZoomOut,
                onResetZoom: onResetZoom,
                onFitWidth: onFitWidth,
                onDeleteAnnotation: onDeleteAnnotation,
                documentTitle: documentTitle,
                docId: docId,
                onGetPageContext: onGetPageContext,
                onAddNewNote: onAddNewNote != null
                    ? (page) {
                        Navigator.of(sheetContext).pop();
                        onAddNewNote(page);
                      }
                    : null,
                onClose: () => Navigator.of(sheetContext).pop(),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 移动端翻页与进度调节抽屉面板
class ReaderMobileProgressSheet extends StatefulWidget {
  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onJumpToPage;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onResetZoom;
  final VoidCallback? onFitWidth;
  final bool isMarkdownMode;
  final VoidCallback? onToggleImmersive;

  const ReaderMobileProgressSheet({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.onJumpToPage,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onResetZoom,
    this.onFitWidth,
    this.isMarkdownMode = false,
    this.onToggleImmersive,
  });

  static Future<void> show({
    required BuildContext context,
    required int currentPage,
    required int totalPages,
    required ValueChanged<int> onJumpToPage,
    required VoidCallback onZoomIn,
    required VoidCallback onZoomOut,
    required VoidCallback onResetZoom,
    VoidCallback? onFitWidth,
    bool isMarkdownMode = false,
    VoidCallback? onToggleImmersive,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (ctx) {
        final settings = ctx.watch<ReaderSettingsProvider>();
        final activeTheme = settings.readingMode == ReadingMode.dark
            ? AppTheme.darkTheme
            : (settings.readingMode == ReadingMode.sepia ? AppTheme.sepiaTheme : AppTheme.lightTheme);

        return Theme(
          data: activeTheme,
          child: ReaderMobileProgressSheet(
            currentPage: currentPage,
            totalPages: totalPages,
            onJumpToPage: onJumpToPage,
            onZoomIn: onZoomIn,
            onZoomOut: onZoomOut,
            onResetZoom: onResetZoom,
            onFitWidth: onFitWidth,
            isMarkdownMode: isMarkdownMode,
            onToggleImmersive: onToggleImmersive,
          ),
        );
      },
    );
  }

  @override
  State<ReaderMobileProgressSheet> createState() => _ReaderMobileProgressSheetState();
}

class _ReaderMobileProgressSheetState extends State<ReaderMobileProgressSheet> {
  late double _sliderVal;

  @override
  void initState() {
    super.initState();
    final safeTotal = max(1, widget.totalPages);
    _sliderVal = widget.currentPage.toDouble().clamp(1.0, safeTotal.toDouble());
  }

  @override
  void didUpdateWidget(covariant ReaderMobileProgressSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentPage != widget.currentPage || oldWidget.totalPages != widget.totalPages) {
      final safeTotal = max(1, widget.totalPages);
      _sliderVal = widget.currentPage.toDouble().clamp(1.0, safeTotal.toDouble());
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<ReaderSettingsProvider>();
    final theme = Theme.of(context);
    final isDark = settings.readingMode == ReadingMode.dark;
    final total = max(1, widget.totalPages);
    final current = _sliderVal.round().clamp(1, total);
    final progressPercent = ((current / total) * 100).toInt().clamp(0, 100);

    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Drag Handle
              Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white24
                      : (settings.readingMode == ReadingMode.sepia
                          ? const Color(0x40B45309)
                          : Colors.black26),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // 2. Header with Page Indicator & Direct Jump
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: isDark ? 0.25 : 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.auto_stories_rounded,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '第 $current 页 / 共 $total 页',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '($progressPercent%)',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.onToggleImmersive != null) ...[
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          ),
                          icon: const Icon(Icons.fullscreen_rounded, size: 16),
                          label: const Text('沉浸', style: TextStyle(fontSize: 12)),
                          onPressed: () {
                            Navigator.of(context).pop();
                            widget.onToggleImmersive?.call();
                          },
                        ),
                        const SizedBox(width: 4),
                      ],
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        ),
                        icon: const Icon(Icons.pin_rounded, size: 15),
                        label: const Text('指定跳页', style: TextStyle(fontSize: 12)),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (_) => PageJumpDialog(
                              totalPages: total,
                              currentPage: current,
                              onJump: (page) {
                                setState(() => _sliderVal = page.toDouble());
                                widget.onJumpToPage(page);
                              },
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 3. Slider
              Row(
                children: [
                  Text(
                    '1',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                      ),
                      child: Slider(
                        value: _sliderVal,
                        min: 1.0,
                        max: total.toDouble(),
                        divisions: total > 1 ? total - 1 : null,
                        label: '$current',
                        onChanged: (val) {
                          setState(() => _sliderVal = val);
                        },
                        onChangeEnd: (val) {
                          widget.onJumpToPage(val.round());
                        },
                      ),
                    ),
                  ),
                  Text(
                    '$total',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 4. Steppers & Zoom Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Prev / Next Page Buttons
                  Row(
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.arrow_back_rounded, size: 14),
                        label: const Text('上一页', style: TextStyle(fontSize: 12)),
                        onPressed: current > 1
                            ? () {
                                final p = current - 1;
                                setState(() => _sliderVal = p.toDouble());
                                widget.onJumpToPage(p);
                              }
                            : null,
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                        label: const Text('下一页', style: TextStyle(fontSize: 12)),
                        onPressed: current < total
                            ? () {
                                final p = current + 1;
                                setState(() => _sliderVal = p.toDouble());
                                widget.onJumpToPage(p);
                              }
                            : null,
                      ),
                    ],
                  ),

                  // Zoom & Fit Width controls (primarily for PDF mode)
                  Row(
                    children: [
                      if (!widget.isMarkdownMode) ...[
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline_rounded, size: 18),
                          tooltip: '缩小',
                          visualDensity: VisualDensity.compact,
                          onPressed: widget.onZoomOut,
                        ),
                        InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: widget.onResetZoom,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                            child: Text(
                              '${(settings.zoomScale * 100).toInt()}%',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                          tooltip: '放大',
                          visualDensity: VisualDensity.compact,
                          onPressed: widget.onZoomIn,
                        ),
                        if (widget.onFitWidth != null) ...[
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.fit_screen_rounded, size: 18),
                            tooltip: '适应页面宽度',
                            visualDensity: VisualDensity.compact,
                            onPressed: widget.onFitWidth,
                          ),
                        ],
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ...[
                Divider(height: 1, color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                const SizedBox(height: 10),

                // 5. Stylus Mode Switch Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: settings.isStylusMode
                                ? Theme.of(context).colorScheme.primary.withValues(alpha: isDark ? 0.25 : 0.12)
                                : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            settings.isStylusMode ? Icons.draw_rounded : Icons.draw_outlined,
                            size: 18,
                            color: settings.isStylusMode
                                ? Theme.of(context).colorScheme.primary
                                : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '手写笔模式 (手笔分离)',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              settings.isStylusMode ? '笔划选批注 · 指移动缩放 · 防手掌误触' : '手笔未分离 (默认触摸模式)',
                              style: TextStyle(
                                fontSize: 10,
                                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Switch(
                      value: settings.isStylusMode,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (val) {
                        settings.setStylusMode(val);
                      },
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
