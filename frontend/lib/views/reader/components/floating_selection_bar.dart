import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../providers/reader_settings_provider.dart';
import '../../../theme/app_theme.dart';

class FloatingSelectionBar extends StatelessWidget {
  final String selectedText;
  final ValueChanged<String> onHighlight;
  final VoidCallback onAddNote;
  final VoidCallback onDismiss;
  final VoidCallback? onAskAi;
  final ReadingMode? readingMode;

  const FloatingSelectionBar({
    super.key,
    required this.selectedText,
    required this.onHighlight,
    required this.onAddNote,
    required this.onDismiss,
    this.onAskAi,
    this.readingMode,
  });

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: selectedText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制选中文本到剪贴板'),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
    onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final mode = readingMode ?? context.watch<ReaderSettingsProvider>().readingMode;
    final isDark = mode == ReadingMode.dark;
    final isSepia = mode == ReadingMode.sepia;

    Color barBg;
    Color borderColor;
    Color textColor;
    Color iconColor;
    Color dividerColor;
    Color shadowColor;

    if (isDark) {
      barBg = const Color(0xFF0F172A);
      borderColor = const Color(0xFF334155);
      textColor = Colors.white;
      iconColor = Colors.white70;
      dividerColor = const Color(0xFF334155);
      shadowColor = Colors.black.withValues(alpha: 0.45);
    } else if (isSepia) {
      barBg = const Color(0xFFF7EFE1);
      borderColor = const Color(0xFFDCC8AA);
      textColor = const Color(0xFF4A3525);
      iconColor = const Color(0xFF6B4C35);
      dividerColor = const Color(0xFFDCC8AA);
      shadowColor = const Color(0x334A3525);
    } else {
      barBg = Colors.white;
      borderColor = const Color(0xFFCBD5E1);
      textColor = const Color(0xFF0F172A);
      iconColor = const Color(0xFF475569);
      dividerColor = const Color(0xFFE2E8F0);
      shadowColor = Colors.black.withValues(alpha: 0.12);
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: barBg,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: borderColor, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: shadowColor,
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Color bubbles (Always vibrant and true colored)
            ...AppTheme.highlightColors.map((item) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: InkWell(
                  onTap: () => onHighlight(item.hex),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: item.color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark ? Colors.white : Colors.black.withValues(alpha: 0.2),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: item.color.withValues(alpha: 0.5),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 1,
              height: 20,
              color: dividerColor,
            ),
            // Ask AI button
            if (onAskAi != null) ...[
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF8B5CF6),
                  backgroundColor: const Color(0xFF8B5CF6).withValues(alpha: isDark ? 0.22 : 0.1),
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: onAskAi,
                icon: const Icon(Icons.auto_awesome_rounded, size: 15, color: Color(0xFF8B5CF6)),
                label: const Text('问AI', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF8B5CF6))),
              ),
              const SizedBox(width: 4),
            ],
            // Add Note button
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: textColor,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: onAddNote,
              icon: const Icon(Icons.edit_note_rounded, size: 18, color: Color(0xFF6366F1)),
              label: Text('批注', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor)),
            ),
            // Copy button
            IconButton(
              icon: Icon(Icons.copy_rounded, size: 16, color: iconColor),
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(),
              onPressed: () => _copyToClipboard(context),
            ),
            // Close / Dismiss button
            IconButton(
              icon: Icon(Icons.close_rounded, size: 16, color: iconColor.withValues(alpha: 0.6)),
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(),
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}
