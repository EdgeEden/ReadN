import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/app_version.dart';
import '../../../providers/document_provider.dart';
import '../../../services/storage_service.dart';

class ServerSettingsDialog extends StatefulWidget {
  const ServerSettingsDialog({super.key});

  @override
  State<ServerSettingsDialog> createState() => _ServerSettingsDialogState();
}

class _ServerSettingsDialogState extends State<ServerSettingsDialog> {
  late TextEditingController _urlController;
  bool _isTesting = false;
  bool? _testResult;
  String? _testMessage;

  @override
  void initState() {
    super.initState();
    final storage = context.read<StorageService>();
    _urlController = TextEditingController(text: storage.getBaseUrl());
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testResult = null;
      _testMessage = null;
    });

    final docProvider = context.read<DocumentProvider>();
    final tempUrl = _urlController.text.trim();
    await docProvider.storageService.setBaseUrl(tempUrl);

    final isOk = await docProvider.apiService.checkHealth();
    setState(() {
      _isTesting = false;
      _testResult = isOk;
      _testMessage = isOk ? "连接成功！后端服务运行正常" : "连接失败，请检查服务器地址与网络";
    });

    if (isOk) {
      docProvider.checkConnectionAndLoad();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.cloud_sync_rounded, color: Theme.of(context).colorScheme.primary),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    '云端服务配置',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                '配置 ReadN FastAPI 后端 API 服务地址：',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _urlController,
                decoration: InputDecoration(
                  labelText: '后端服务 URL',
                  hintText: 'http://localhost:18903 或 http://你的云服务器IP:18903',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.link_rounded),
                ),
              ),
              const SizedBox(height: 12),
              if (_testMessage != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _testResult == true
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _testResult == true ? Icons.check_circle_rounded : Icons.error_rounded,
                        color: _testResult == true ? Colors.green : Colors.red,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _testMessage!,
                          style: TextStyle(
                            fontSize: 13,
                            color: _testResult == true ? Colors.green.shade800 : Colors.red.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _isTesting ? null : _testConnection,
                      icon: _isTesting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.network_check_rounded, size: 18),
                      label: const Text('测试连接'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        await _testConnection();
                        if (context.mounted && _testResult == true) {
                          Navigator.of(context).pop();
                        }
                      },
                      child: const Text('保存并同步'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.4)),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text(
                    AppVersion.fullDisplay,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                  Text(
                    '构建日期: ${AppVersion.releaseDate}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

