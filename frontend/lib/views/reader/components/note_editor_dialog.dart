import 'package:flutter/material.dart';
import '../../../models/annotation_model.dart';

class NoteEditorDialog extends StatefulWidget {
  final PdfAnnotation annotation;
  final ValueChanged<PdfAnnotation> onSave;
  final VoidCallback onDelete;

  const NoteEditorDialog({
    super.key,
    required this.annotation,
    required this.onSave,
    required this.onDelete,
  });

  @override
  State<NoteEditorDialog> createState() => _NoteEditorDialogState();
}

class _NoteEditorDialogState extends State<NoteEditorDialog> {
  late TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(text: widget.annotation.noteContent);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _handleSave() {
    final text = _noteController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('批注内容不能为空'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final updated = widget.annotation.copyWith(
      noteContent: text,
      type: "note",
      colorHex: widget.annotation.colorHex.isNotEmpty ? widget.annotation.colorHex : "#6366F1",
      updatedAt: DateTime.now(),
    );
    widget.onSave(updated);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const accentColor = Color(0xFF6366F1);

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 460,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: isDark ? 0.25 : 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.edit_note_rounded, color: accentColor, size: 20),
                ),
                const SizedBox(width: 10),
                Text(
                  '第 ${widget.annotation.pageNumber} 页批注',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 2. Quoted text preview (引文 / 图标停泊锚点)
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                  width: 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
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
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.location_on_rounded, size: 14, color: accentColor),
                                  const SizedBox(width: 4),
                                  Text(
                                    '引文与图标停泊锚点 (第 ${widget.annotation.pageNumber} 页):',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.annotation.selectedText.trim().isNotEmpty
                                    ? '“${widget.annotation.selectedText.trim()}”'
                                    : (widget.annotation.rects.isNotEmpty
                                        ? '(已在第 ${widget.annotation.pageNumber} 页位置锚定，点击徽标可随时回顾)'
                                        : '(第 ${widget.annotation.pageNumber} 页独立批注笔记，展示于页面摘要栏)'),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontStyle: FontStyle.italic,
                                  height: 1.45,
                                  color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                                ),
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
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
            const SizedBox(height: 14),

            // 3. Note Text field
            Text(
              '批注笔记内容',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              maxLines: 5,
              minLines: 3,
              style: const TextStyle(fontSize: 13, height: 1.5),
              decoration: InputDecoration(
                hintText: '写下您的批注与想法...',
                hintStyle: const TextStyle(fontSize: 12.5, color: Colors.grey),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 18),

            // 4. Actions
            Row(
              children: [
                IconButton(
                  tooltip: '删除此批注',
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                  onPressed: () {
                    widget.onDelete();
                    Navigator.of(context).pop();
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  onPressed: _handleSave,
                  icon: const Icon(Icons.save_rounded, size: 16),
                  label: const Text('保存批注', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
