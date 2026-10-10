import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_version.dart';
import '../../models/document_model.dart';
import '../../providers/document_provider.dart';
import '../../providers/reader_settings_provider.dart';
import '../../theme/app_theme.dart';
import '../reader/reader_view.dart';
import 'components/document_card.dart';
import 'components/server_settings_dialog.dart';
import 'components/upload_dropzone.dart';

class BookshelfView extends StatefulWidget {
  const BookshelfView({super.key});

  @override
  State<BookshelfView> createState() => _BookshelfViewState();
}

class _BookshelfViewState extends State<BookshelfView> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openReader(BuildContext context, DocumentModel doc) {
    context.read<DocumentProvider>().setActiveDocument(doc);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PdfReaderScreen(document: doc),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final docProvider = context.watch<DocumentProvider>();
    final readerSettings = context.watch<ReaderSettingsProvider>();
    final theme = Theme.of(context);
    final isDark = readerSettings.readingMode == ReadingMode.dark;
    final isConnected = docProvider.isBackendConnected;
    final docs = docProvider.documents;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4F46E5), Color(0xFF06B6D4)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.menu_book_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'ReadN',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, letterSpacing: -0.5),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Cloud Sync',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: '当前版本: ${AppVersion.displayVersion} (构建: ${AppVersion.buildNumber})',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.15),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  AppVersion.displayVersion,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          // Cloud Status Pill
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => const ServerSettingsDialog(),
              );
            },
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isConnected
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.red.withValues(alpha: 0.1),
                border: Border.all(
                  color: isConnected ? Colors.green.shade300 : Colors.red.shade300,
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isConnected ? Colors.green : Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isConnected ? '云端已连接' : '未连接云端',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isConnected ? Colors.green.shade800 : Colors.red.shade800,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.settings_outlined,
                    size: 14,
                    color: isConnected ? Colors.green.shade800 : Colors.red.shade800,
                  ),
                ],
              ),
            ),
          ),
          // Theme Switcher Menu
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
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                ),
              ),
              child: Icon(
                readerSettings.readingMode == ReadingMode.dark
                    ? Icons.dark_mode_rounded
                    : readerSettings.readingMode == ReadingMode.sepia
                        ? Icons.menu_book_rounded
                        : Icons.light_mode_rounded,
                size: 16,
                color: readerSettings.readingMode == ReadingMode.sepia
                    ? const Color(0xFFD97706)
                    : theme.colorScheme.primary,
              ),
            ),
            onSelected: (mode) => readerSettings.setReadingMode(mode),
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
                    Text('深色夜间模式'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            tooltip: '刷新文档库',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => docProvider.loadDocuments(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 900;
          final padding = isWide ? 32.0 : 16.0;

          return RefreshIndicator(
            onRefresh: () => docProvider.loadDocuments(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: padding, vertical: 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Stats Banner
                      _buildHeaderBanner(context, docProvider, isWide),
                      const SizedBox(height: 24),

                      // Upload Area
                      const UploadDropzone(),
                      const SizedBox(height: 28),

                      // Toolbar: Search, Sort, View Toggle
                      _buildToolbar(context, docProvider, isWide),
                      const SizedBox(height: 20),

                      // Document Grid or List
                      if (docProvider.isLoading)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(48.0),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else if (docs.isEmpty)
                        _buildEmptyState(context, docProvider)
                      else if (docProvider.isGridView)
                        _buildGridView(context, docs, constraints.maxWidth)
                      else
                        _buildListView(context, docs),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeaderBanner(BuildContext context, DocumentProvider docProvider, bool isWide) {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.all(isWide ? 24 : 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.secondary,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '我的云端知识库',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '一次上传，全端秒开。基于 pdfrx 极速渲染引擎与云端批注同步',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          if (isWide) ...[
            _buildStatItem('文档总数', '${docProvider.totalDocumentsCount}', Icons.description_rounded),
            const SizedBox(width: 24),
            _buildStatItem('高亮/批注', '${docProvider.totalAnnotationsCount}', Icons.draw_rounded),
          ],
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              Text(
                label,
                style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.8)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context, DocumentProvider docProvider, bool isWide) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        // Search bar
        SizedBox(
          width: isWide ? 320 : double.infinity,
          child: TextField(
            controller: _searchController,
            onChanged: (val) => docProvider.setSearchQuery(val),
            decoration: InputDecoration(
              hintText: '搜索文档标题或文件名...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        docProvider.setSearchQuery('');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              filled: true,
              fillColor: Theme.of(context).cardTheme.color,
            ),
          ),
        ),
        // Sort and View buttons
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Sort Dropdown
            DropdownButton<DocumentSortBy>(
              value: docProvider.sortBy,
              underline: const SizedBox(),
              icon: const Icon(Icons.sort_rounded),
              items: const [
                DropdownMenuItem(
                  value: DocumentSortBy.updatedAt,
                  child: Text('最新修改'),
                ),
                DropdownMenuItem(
                  value: DocumentSortBy.title,
                  child: Text('名称排序'),
                ),
                DropdownMenuItem(
                  value: DocumentSortBy.fileSize,
                  child: Text('文件大小'),
                ),
              ],
              onChanged: (val) {
                if (val != null) docProvider.setSortBy(val);
              },
            ),
            const SizedBox(width: 8),
            // View Mode Toggle
            IconButton(
              tooltip: docProvider.isGridView ? '切换到列表视图' : '切换到网格视图',
              icon: Icon(docProvider.isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded),
              onPressed: () => docProvider.toggleViewMode(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context, DocumentProvider docProvider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.library_books_rounded, size: 56, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            const Text(
              '云端文档库暂无内容',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              '点击上方上传按钮或拖拽 PDF 文件，即可开启极速阅读与批注',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridView(BuildContext context, List<DocumentModel> docs, double containerWidth) {
    int crossAxisCount = 4;
    if (containerWidth < 600) {
      crossAxisCount = 1;
    } else if (containerWidth < 900) {
      crossAxisCount = 2;
    } else if (containerWidth < 1200) {
      crossAxisCount = 3;
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.15,
      ),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final doc = docs[index];
        return DocumentCard(
          document: doc,
          isGrid: true,
          onTap: () => _openReader(context, doc),
        );
      },
    );
  }

  Widget _buildListView(BuildContext context, List<DocumentModel> docs) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final doc = docs[index];
        return DocumentCard(
          document: doc,
          isGrid: false,
          onTap: () => _openReader(context, doc),
        );
      },
    );
  }
}

