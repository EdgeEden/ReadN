import 'package:flutter/material.dart';

class PageJumpDialog extends StatefulWidget {
  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onJump;

  const PageJumpDialog({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.onJump,
  });

  @override
  State<PageJumpDialog> createState() => _PageJumpDialogState();
}

class _PageJumpDialogState extends State<PageJumpDialog> {
  late TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.currentPage}');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    final page = int.tryParse(text);
    if (page == null || page < 1 || page > widget.totalPages) {
      setState(() {
        _error = '请输入 1 到 ${widget.totalPages} 之间的有效页码';
      });
      return;
    }
    widget.onJump(page);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('跳转页码'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: '目标页码 (1 - ${widget.totalPages})',
              errorText: _error,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('跳转'),
        ),
      ],
    );
  }
}

