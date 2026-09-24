import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/document_provider.dart';

class UploadDropzone extends StatefulWidget {
  final VoidCallback? onUploadSuccess;

  const UploadDropzone({super.key, this.onUploadSuccess});

  @override
  State<UploadDropzone> createState() => _UploadDropzoneState();
}

class _UploadDropzoneState extends State<UploadDropzone> {
  bool _isHovering = false;

  Future<void> _pickAndUpload() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final pickedFile = result.files.first;
        final bytes = pickedFile.bytes;
        final name = pickedFile.name;

        if (bytes != null && mounted) {
          final docProvider = context.read<DocumentProvider>();
          final doc = await docProvider.uploadDocument(bytes, name);
          if (doc != null && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('《${doc.title}》已成功上传至云端并同步！'),
                backgroundColor: Colors.green.shade700,
                behavior: SnackBarBehavior.floating,
              ),
            );
            widget.onUploadSuccess?.call();
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('选择或上传文件失败: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final docProvider = context.watch<DocumentProvider>();
    final theme = Theme.of(context);
    final isUploading = docProvider.isUploading;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: isUploading ? null : _pickAndUpload,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: _isHovering
                ? theme.colorScheme.primary.withValues(alpha: 0.04)
                : theme.cardTheme.color,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _isHovering
                  ? theme.colorScheme.primary
                  : const Color(0xFFCBD5E1),
              width: _isHovering ? 2.0 : 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: isUploading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : Icon(
                        Icons.cloud_upload_rounded,
                        color: theme.colorScheme.primary,
                        size: 26,
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isUploading ? '正在上传并同步至云端...' : '点击上传 PDF 文档到云端',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isUploading
                          ? '正在提取文档索引与页面数据...'
                          : '支持大体积 PDF，云端秒级解析，自动同步所有设备与阅读批注',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: isUploading ? null : _pickAndUpload,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('选择文件'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

