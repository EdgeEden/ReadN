import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/document_model.dart';
import '../../../providers/annotation_provider.dart';
import '../../../providers/reader_settings_provider.dart';
import '../../../theme/app_theme.dart';
import 'page_jump_dialog.dart';

class ReaderTopBar extends StatelessWidget {
  final DocumentModel document;
  final OcrStatusInfo? ocrProgress;
  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onJumpToPage;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onResetZoom;
  final VoidCallback onPrevPage;
  final VoidCallback onNextPage;
  final VoidCallback? onOpenOcr;

  const ReaderTopBar({
    super.key,
    required this.document,
    this.ocrProgress,
    required this.currentPage,
    required this.totalPages,
    required this.onJumpToPage,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onResetZoom,
    required this.onPrevPage,
    required this.onNextPage,
    this.onOpenOcr,
  });

  void _showJumpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => PageJumpDialog(
        currentPage: currentPage,
        totalPages: totalPages > 0 ? totalPages : 1,
        onJump: onJumpToPage,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<ReaderSettingsProvider>();
    final annoProvider = context.watch<AnnotationProvider>();
    final theme = Theme.of(context);
    final isDark = settings.readingMode == ReadingMode.dark;

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: theme.appBarTheme.backgroundColor,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Back to bookshelf button
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: theme.cardTheme.color,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back_rounded, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  const Text(
                    '书架',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Document Title with Gradient Tag
          Expanded(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFEF4444), Color(0xFFF97316)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.description_rounded, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    document.title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      letterSpacing: -0.2,
                      color: theme.colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Center Page Navigator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: theme.cardTheme.color,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  tooltip: '上一页 (Left Arrow)',
                  onPressed: currentPage > 1 ? onPrevPage : null,
                ),
                InkWell(
                  onTap: () => _showJumpDialog(context),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$currentPage / ${totalPages > 0 ? totalPages : "-"}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  tooltip: '下一页 (Right Arrow)',
                  onPressed: currentPage < totalPages ? onNextPage : null,
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),

          // Zoom Controls
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: theme.cardTheme.color,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_rounded, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  tooltip: '缩小',
                  onPressed: onZoomOut,
                ),
                InkWell(
                  onTap: onResetZoom,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Text(
                      '${(settings.zoomScale * 100).toInt()}%',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_rounded, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  tooltip: '放大',
                  onPressed: onZoomIn,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // Pinned OCR Status & Action Button
          _buildOcrButton(context, theme, isDark),
          const SizedBox(width: 8),

          // Reading Mode Switcher Button
          PopupMenuButton<ReadingMode>(
            tooltip: '切换阅读主题',
            offset: const Offset(0, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: theme.cardTheme.color,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
              child: Icon(
                settings.readingMode == ReadingMode.dark
                    ? Icons.dark_mode_rounded
                    : settings.readingMode == ReadingMode.sepia
                        ? Icons.menu_book_rounded
                        : Icons.light_mode_rounded,
                size: 18,
                color: settings.readingMode == ReadingMode.sepia
                    ? const Color(0xFFD97706)
                    : theme.colorScheme.primary,
              ),
            ),
            onSelected: (mode) => settings.setReadingMode(mode),
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: ReadingMode.light,
                child: Row(
                  children: [
                    Icon(Icons.light_mode_rounded, color: Color(0xFF4F46E5), size: 18),
                    SizedBox(width: 10),
                    Text('明亮日间模式'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: ReadingMode.sepia,
                child: Row(
                  children: [
                    Icon(Icons.menu_book_rounded, color: Color(0xFFD97706), size: 18),
                    SizedBox(width: 10),
                    Text('羊皮纸护眼模式'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: ReadingMode.dark,
                child: Row(
                  children: [
                    Icon(Icons.dark_mode_rounded, color: Color(0xFF818CF8), size: 18),
                    SizedBox(width: 10),
                    Text('深色夜间模式 (反色阅读)'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),

          // Sidebar Toggle Button
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => settings.toggleSidebar(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: settings.isSidebarOpen
                    ? theme.colorScheme.primary.withValues(alpha: 0.15)
                    : theme.cardTheme.color,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: settings.isSidebarOpen
                      ? theme.colorScheme.primary
                      : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.edit_note_rounded,
                    size: 18,
                    color: settings.isSidebarOpen ? theme.colorScheme.primary : null,
                  ),
                  const SizedBox(width: 4),
                  const Text('批注', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  if (annoProvider.annotations.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade700,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${annoProvider.annotations.length}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOcrButton(BuildContext context, ThemeData theme, bool isDark) {
    final isCompleted = document.ocrStatus == "completed" || (ocrProgress != null && ocrProgress!.isCompleted);
    final isProcessing = document.ocrStatus == "processing" || (ocrProgress != null && ocrProgress!.isProcessing);
    final isNativeText = document.hasTextLayer && !isCompleted;

    // State 1: OCR Completed (Disabled with Checkmark)
    if (isCompleted) {
      return Tooltip(
        message: '双层可检索 PDF 已就绪，已支持鼠标划词与荧光高亮',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.18 : 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: const Color(0xFF10B981).withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF10B981)),
              SizedBox(width: 5),
              Text(
                '已完成',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF10B981),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // State 2: OCR Processing (Active Live Progress Pill with Page Count)
    if (isProcessing) {
      final currPage = ocrProgress?.currentPage ?? 0;
      final totalP = (ocrProgress?.totalPages != null && ocrProgress!.totalPages > 0)
          ? ocrProgress!.totalPages
          : (document.pageCount > 0 ? document.pageCount : totalPages);
      final progPercent = ((ocrProgress?.progress ?? 0.05) * 100).toInt().clamp(1, 99);

      String progressLabel;
      if (currPage > 0 && totalP > 0) {
        progressLabel = '识别中 $currPage/$totalP页 ($progPercent%)';
      } else {
        progressLabel = '识别中 $progPercent%';
      }

      return Tooltip(
        message: '正在进行 OCR 识别 ($progressLabel)，点击查看详情',
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onOpenOcr,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF4F46E5).withValues(alpha: isDark ? 0.25 : 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFF6366F1).withValues(alpha: 0.8),
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isDark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  progressLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark ? const Color(0xFF818CF8) : const Color(0xFF4338CA),
                  ),
                ),
                const SizedBox(width: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    width: 32,
                    height: 5,
                    child: LinearProgressIndicator(
                      value: (ocrProgress?.progress ?? 0.05).clamp(0.05, 1.0),
                      backgroundColor: (isDark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5)).withValues(alpha: 0.2),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isDark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // State 3: Native Text Layer (Disabled / Greyed Out)
    if (isNativeText) {
      return Tooltip(
        message: '文档已内嵌原生文字层，无需进行 OCR',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.text_fields_rounded,
                size: 16,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
              const SizedBox(width: 5),
              Text(
                '原生文字',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // State 4: Scanned / Image PDF Not Started (Active Clickable Button)
    return Tooltip(
      message: '一键生成双层可检索 PDF，支持文字划词高亮与数学公式识别',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onOpenOcr,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF4F46E5), Color(0xFF0EA5E9)],
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4F46E5).withValues(alpha: 0.35),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_fix_high_rounded, size: 16, color: Colors.white),
              const SizedBox(width: 5),
              Text(
                document.ocrStatus == 'failed' ? 'OCR 重试' : '双层 OCR',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

