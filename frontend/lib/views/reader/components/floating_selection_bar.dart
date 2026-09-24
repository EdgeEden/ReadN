import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../theme/app_theme.dart';

class FloatingSelectionBar extends StatelessWidget {
  final String selectedText;
  final ValueChanged<String> onHighlight;
  final VoidCallback onAddNote;
  final VoidCallback onDismiss;

  const FloatingSelectionBar({
    super.key,
    required this.selectedText,
    required this.onHighlight,
    required this.onAddNote,
    required this.onDismiss,
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
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A), // Sleek deep slate
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: const Color(0xFF334155), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Color bubbles
            ...AppTheme.highlightColors.map((item) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Tooltip(
                  message: '荧光高亮 (${item.label})',
                  child: InkWell(
                    onTap: () => onHighlight(item.hex),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: item.color,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: item.color.withValues(alpha: 0.4),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 1,
              height: 20,
              color: const Color(0xFF334155),
            ),
            // Add Note button
            Tooltip(
              message: '添加批注与心得',
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: onAddNote,
                icon: const Icon(Icons.edit_note_rounded, size: 18, color: Color(0xFF818CF8)),
                label: const Text('批注', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ),
            // Copy button
            Tooltip(
              message: '复制文本',
              child: IconButton(
                icon: const Icon(Icons.copy_rounded, size: 16, color: Colors.white70),
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(),
                onPressed: () => _copyToClipboard(context),
              ),
            ),
            // Close / Dismiss button
            Tooltip(
              message: '关闭菜单',
              child: IconButton(
                icon: const Icon(Icons.close_rounded, size: 16, color: Colors.white38),
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(),
                onPressed: onDismiss,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
