import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/document_model.dart';
import '../../../providers/reader_settings_provider.dart';
import '../../../theme/app_theme.dart';

enum ReaderViewMode {
  pdf,
  markdown,
}

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
  final ReaderViewMode viewMode;
  final ValueChanged<ReaderViewMode>? onViewModeChanged;
  final bool hasMarkdown;
  final bool isMobile;

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
    this.viewMode = ReaderViewMode.pdf,
    this.onViewModeChanged,
    this.hasMarkdown = false,
    this.isMobile = false,
  });

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<ReaderSettingsProvider>();
    final theme = Theme.of(context);
    final isDark = settings.readingMode == ReadingMode.dark;

    return Container(
      height: 56,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 14),
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
          // 1. Back to Bookshelf
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 10, vertical: 6),
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
                  Icon(Icons.arrow_back_rounded, size: 16, color: theme.colorScheme.primary),
                  if (!isMobile) ...[
                    const SizedBox(width: 4),
                    const Text(
                      '书架',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SizedBox(width: isMobile ? 6 : 12),

          // 2. Document Title
          Expanded(
            child: Row(
              children: [
                if (!isMobile) ...[
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFEF4444), Color(0xFFF97316)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: const Icon(Icons.description_rounded, color: Colors.white, size: 14),
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    document.title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: isMobile ? 13 : 14,
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
          SizedBox(width: isMobile ? 6 : 10),

          // 3. View Mode Switcher: [ 📄 PDF | 📝 MD ]
          _buildViewModeSwitcher(context, theme, isDark),
          SizedBox(width: isMobile ? 6 : 10),

          // 4. OCR Status & Action Button
          _buildOcrButton(context, theme, isDark),
          SizedBox(width: isMobile ? 6 : 10),

          // 5. Theme Switcher Menu
          PopupMenuButton<ReadingMode>(
            tooltip: '切换阅读主题',
            offset: const Offset(0, 44),
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
                size: 16,
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
        ],
      ),
    );
  }

  Widget _buildOcrButton(BuildContext context, ThemeData theme, bool isDark) {
    final isCompleted = document.ocrStatus == "completed" || (ocrProgress != null && ocrProgress!.isCompleted);
    final isProcessing = document.ocrStatus == "processing" || (ocrProgress != null && ocrProgress!.isProcessing);
    final isNativeText = document.hasTextLayer && !isCompleted;

    if (isCompleted) {
      return Tooltip(
        message: 'OCR Markdown 已就绪。点击可对指定页面使用 PaddleOCR-VL 重新识别并合并',
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onOpenOcr,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.18 : 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFF10B981).withValues(alpha: 0.4),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_rounded, size: 15, color: Color(0xFF10B981)),
                if (!isMobile) ...[
                  const SizedBox(width: 5),
                  const Text(
                    'MD 已就绪',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF10B981),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    if (isProcessing) {
      final currPage = ocrProgress?.currentPage ?? 0;
      final totalP = (ocrProgress?.totalPages != null && ocrProgress!.totalPages > 0)
          ? ocrProgress!.totalPages
          : (document.pageCount > 0 ? document.pageCount : totalPages);
      final progPercent = ((ocrProgress?.progress ?? 0.05) * 100).toInt().clamp(1, 99);

      String progressLabel;
      if (currPage > 0 && totalP > 0) {
        progressLabel = '$currPage/$totalP页 ($progPercent%)';
      } else {
        progressLabel = '$progPercent%';
      }

      return Tooltip(
        message: '正在进行 PaddleOCR-VL 识别 ($progressLabel)，点击查看详情',
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onOpenOcr,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 7 : 9, vertical: 5),
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
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isDark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5),
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  isMobile ? '$progPercent%' : progressLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isDark ? const Color(0xFF818CF8) : const Color(0xFF4338CA),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (isNativeText) {
      return Tooltip(
        message: '文档含原生文字层。点击可使用 PaddleOCR-VL 提取结构化 Markdown 与 LaTeX 公式',
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onOpenOcr,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 9, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 14,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
                if (!isMobile) ...[
                  const SizedBox(width: 4),
                  Text(
                    '提取MD',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Tooltip(
      message: '一键使用 PaddleOCR-VL 提取结构化 Markdown、数学公式与表格',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onOpenOcr,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 10, vertical: 6),
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
              const Icon(Icons.auto_awesome_rounded, size: 15, color: Colors.white),
              if (!isMobile) ...[
                const SizedBox(width: 4),
                Text(
                  document.ocrStatus == 'failed' ? 'OCR 重试' : 'OCR 解析',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildViewModeSwitcher(BuildContext context, ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModeTab(
            title: 'PDF',
            icon: Icons.picture_as_pdf_rounded,
            isSelected: viewMode == ReaderViewMode.pdf,
            onTap: () => onViewModeChanged?.call(ReaderViewMode.pdf),
            isDark: isDark,
          ),
          const SizedBox(width: 3),
          _buildModeTab(
            title: 'MD',
            icon: Icons.menu_book_rounded,
            isSelected: viewMode == ReaderViewMode.markdown,
            hasBadge: hasMarkdown,
            badgeTooltip: '已提取 Markdown 结构与公式',
            onTap: () => onViewModeChanged?.call(ReaderViewMode.markdown),
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildModeTab({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
    bool hasBadge = false,
    String? badgeTooltip,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF4F46E5) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected
                  ? Colors.white
                  : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
            ),
            const SizedBox(width: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected
                    ? Colors.white
                    : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569)),
              ),
            ),
            if (hasBadge) ...[
              const SizedBox(width: 4),
              Tooltip(
                message: badgeTooltip ?? '',
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.greenAccent : const Color(0xFF10B981),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
