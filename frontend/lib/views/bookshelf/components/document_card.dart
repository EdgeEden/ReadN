import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../models/document_model.dart';
import '../../../providers/document_provider.dart';

class DocumentCard extends StatefulWidget {
  final DocumentModel document;
  final bool isGrid;
  final VoidCallback onTap;

  const DocumentCard({
    super.key,
    required this.document,
    required this.isGrid,
    required this.onTap,
  });

  @override
  State<DocumentCard> createState() => _DocumentCardState();
}

class _DocumentCardState extends State<DocumentCard> {
  bool _isHovered = false;

  void _showRenameDialog(BuildContext context) {
    final controller = TextEditingController(text: widget.document.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('重命名文档'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '文档标题',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty) {
                context.read<DocumentProvider>().renameDocument(widget.document.id, newTitle);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('确认删除'),
        content: Text('确定要从云端删除文档 "${widget.document.title}" 吗？此操作将同时清除所有批注与高亮。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              context.read<DocumentProvider>().deleteDocument(widget.document.id);
              Navigator.of(ctx).pop();
            },
            child: const Text('删除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!widget.isGrid) {
      // List Row View
      return MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: theme.cardTheme.color,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _isHovered ? theme.colorScheme.primary : const Color(0xFFE2E8F0),
              width: _isHovered ? 1.5 : 1.0,
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ]
                : [],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            onTap: widget.onTap,
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.picture_as_pdf_rounded, color: Colors.red, size: 24),
            ),
            title: Text(
              widget.document.title,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Row(
              children: [
                Text('${widget.document.pageCount} 页', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(width: 8),
                const Text('•', style: TextStyle(color: Colors.grey)),
                const SizedBox(width: 8),
                Text(widget.document.formattedSize, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(width: 8),
                const Text('•', style: TextStyle(color: Colors.grey)),
                const SizedBox(width: 8),
                Text(widget.document.formattedDate, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!widget.document.hasTextLayer)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.document_scanner_rounded, size: 13, color: Colors.blue),
                        SizedBox(width: 4),
                        Text(
                          '纯图片',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue),
                        ),
                      ],
                    ),
                  ),
                if (widget.document.annotationCount > 0)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.edit_note_rounded, size: 14, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text(
                          '${widget.document.annotationCount}',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                        ),
                      ],
                    ),
                  ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: (val) {
                    if (val == 'rename') _showRenameDialog(context);
                    if (val == 'delete') _showDeleteDialog(context);
                    if (val == 'ocr') {
                      context.read<DocumentProvider>().triggerOcr(widget.document.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已启动双层可检索 PDF (OCR) 转换任务，后台正在处理中...')),
                      );
                    }
                    if (val == 'copy_link') {
                      final url = widget.document.getFileUrl(context.read<DocumentProvider>().storageService.getBaseUrl());
                      Clipboard.setData(ClipboardData(text: url));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制文档流式链接到剪贴板')),
                      );
                    }
                  },
                  itemBuilder: (ctx) => [
                    if (!widget.document.hasTextLayer)
                      const PopupMenuItem(
                        value: 'ocr',
                        child: Row(
                          children: [
                            Icon(Icons.auto_fix_high_rounded, size: 16, color: Color(0xFF4F46E5)),
                            SizedBox(width: 8),
                            Text('转换为双层PDF (OCR)'),
                          ],
                        ),
                      ),
                    const PopupMenuItem(value: 'rename', child: Text('重命名')),
                    const PopupMenuItem(value: 'copy_link', child: Text('复制链接')),
                    const PopupMenuItem(value: 'delete', child: Text('删除文档', style: TextStyle(color: Colors.red))),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Grid Card View
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isHovered ? theme.colorScheme.primary : const Color(0xFFE2E8F0),
            width: _isHovered ? 1.5 : 1.0,
          ),
          boxShadow: _isHovered
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  )
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: PDF icon and Menu
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.red.shade400, Colors.red.shade600],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          )
                        ],
                      ),
                      child: const Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 24),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_horiz_rounded, color: Colors.grey),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onSelected: (val) {
                        if (val == 'rename') _showRenameDialog(context);
                        if (val == 'delete') _showDeleteDialog(context);
                        if (val == 'ocr') {
                          context.read<DocumentProvider>().triggerOcr(widget.document.id);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已启动双层可检索 PDF (OCR) 转换任务，后台正在处理中...')),
                          );
                        }
                        if (val == 'copy_link') {
                          final url = widget.document.getFileUrl(context.read<DocumentProvider>().storageService.getBaseUrl());
                          Clipboard.setData(ClipboardData(text: url));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已复制文档流式链接到剪贴板')),
                          );
                        }
                      },
                      itemBuilder: (ctx) => [
                        if (!widget.document.hasTextLayer)
                          const PopupMenuItem(
                            value: 'ocr',
                            child: Row(
                              children: [
                                Icon(Icons.auto_fix_high_rounded, size: 16, color: Color(0xFF4F46E5)),
                                SizedBox(width: 8),
                                Text('转换为双层PDF (OCR)'),
                              ],
                            ),
                          ),
                        const PopupMenuItem(value: 'rename', child: Text('重命名')),
                        const PopupMenuItem(value: 'copy_link', child: Text('复制链接')),
                        const PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(color: Colors.red))),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                // Title
                Text(
                  widget.document.title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, height: 1.3),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                // Badges row: Pages, Size, Annotations
                Row(
                  children: [
                    if (!widget.document.hasTextLayer) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '纯图片',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${widget.document.pageCount}P',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        widget.document.formattedSize,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey),
                      ),
                    ),
                    if (widget.document.annotationCount > 0) ...[
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.edit_note_rounded, size: 12, color: Colors.amber),
                            const SizedBox(width: 2),
                            Text(
                              '${widget.document.annotationCount}',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
