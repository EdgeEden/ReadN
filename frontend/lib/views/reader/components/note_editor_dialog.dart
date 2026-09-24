import 'package:flutter/material.dart';
import '../../../models/annotation_model.dart';
import '../../../theme/app_theme.dart';

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
  late String _selectedColor;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(text: widget.annotation.noteContent);
    _selectedColor = widget.annotation.colorHex;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _handleSave() {
    final updated = widget.annotation.copyWith(
      colorHex: _selectedColor,
      noteContent: _noteController.text.trim(),
      type: _noteController.text.trim().isNotEmpty ? "note" : "highlight",
    );
    widget.onSave(updated);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 440,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sticky_note_2_rounded, color: Color(0xFF4F46E5), size: 22),
                const SizedBox(width: 8),
                Text(
                  '第 ${widget.annotation.pageNumber} 页批注',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Quoted text
            if (widget.annotation.selectedText.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.parseHexColor(_selectedColor, alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border(
                    left: BorderSide(
                      color: AppTheme.parseHexColor(_selectedColor),
                      width: 4,
                    ),
                  ),
                ),
                child: Text(
                  '“${widget.annotation.selectedText}”',
                  style: TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.9),
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const SizedBox(height: 16),
            // Color palette selector
            const Text(
              '荧光颜色',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Row(
              children: AppTheme.highlightColors.map((colorItem) {
                final isSelected = _selectedColor.toLowerCase() == colorItem.hex.toLowerCase();
                return GestureDetector(
                  onTap: () => setState(() => _selectedColor = colorItem.hex),
                  child: Container(
                    margin: const EdgeInsets.only(right: 10),
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: colorItem.color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.black87 : Colors.black12,
                        width: isSelected ? 2.5 : 1.0,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: colorItem.color.withValues(alpha: 0.5),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              )
                            ]
                          : [],
                    ),
                    child: isSelected
                        ? const Icon(Icons.check_rounded, size: 16, color: Colors.black87)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            // Note edit box
            const Text(
              '笔记 / 批注内容',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: '写下您的想法、要点总结或批注...',
                hintStyle: const TextStyle(fontSize: 13),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 20),
            // Actions
            Row(
              children: [
                IconButton(
                  tooltip: '删除此高亮与批注',
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
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
                ElevatedButton(
                  onPressed: _handleSave,
                  child: const Text('保存批注'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

