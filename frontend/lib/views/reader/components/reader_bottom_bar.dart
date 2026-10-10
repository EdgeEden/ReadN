import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/annotation_provider.dart';
import '../../../providers/reader_settings_provider.dart';
import '../../../theme/app_theme.dart';

class ReaderBottomBar extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final ValueChanged<ReaderSidebarTab> onTabSelected;
  final VoidCallback onOpenProgress;
  final bool isMarkdownMode;

  const ReaderBottomBar({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.onTabSelected,
    required this.onOpenProgress,
    this.isMarkdownMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<ReaderSettingsProvider>();
    final annoProvider = context.watch<AnnotationProvider>();
    final theme = Theme.of(context);
    final isDark = settings.readingMode == ReadingMode.dark;

    final totalAnnotations = annoProvider.annotations.length;

    return Container(
      decoration: BoxDecoration(
        color: theme.appBarTheme.backgroundColor ?? theme.cardTheme.color,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // 1. 目录 (Outline)
              _buildBarItem(
                context,
                theme: theme,
                isDark: isDark,
                icon: Icons.menu_book_rounded,
                label: '目录',
                onTap: () => onTabSelected(ReaderSidebarTab.outline),
              ),

              // 2. 检索 (Search)
              _buildBarItem(
                context,
                theme: theme,
                isDark: isDark,
                icon: Icons.search_rounded,
                label: '检索',
                onTap: () => onTabSelected(ReaderSidebarTab.search),
              ),

              // 3. 笔记 (Annotations / Highlights / Notes / Cards)
              _buildBarItem(
                context,
                theme: theme,
                isDark: isDark,
                icon: Icons.edit_note_rounded,
                label: '笔记',
                badgeCount: totalAnnotations > 0 ? totalAnnotations : null,
                onTap: () => onTabSelected(ReaderSidebarTab.highlights),
              ),

              // 4. AI 伴读 (AI Chat Assistant)
              _buildBarItem(
                context,
                theme: theme,
                isDark: isDark,
                icon: Icons.auto_awesome_rounded,
                label: 'AI 伴读',
                highlightColor: const Color(0xFF818CF8),
                onTap: () => onTabSelected(ReaderSidebarTab.aiChat),
              ),

              // 5. 进度与调控 (Progress & Controls)
              _buildBarItem(
                context,
                theme: theme,
                isDark: isDark,
                icon: Icons.tune_rounded,
                label: '$currentPage / $totalPages',
                onTap: onOpenProgress,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBarItem(
    BuildContext context, {
    required ThemeData theme,
    required bool isDark,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? highlightColor,
    int? badgeCount,
  }) {
    final defaultColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final activeColor = highlightColor ?? theme.colorScheme.primary;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 20, color: defaultColor),
                  if (badgeCount != null)
                    Positioned(
                      top: -4,
                      right: -10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: activeColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: defaultColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

