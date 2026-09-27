import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:provider/provider.dart';

import '../../../models/ai_message_model.dart';
import '../../../providers/ai_provider.dart';
import '../../../providers/annotation_provider.dart';
import '../../../providers/reader_settings_provider.dart';
import '../../../theme/app_theme.dart';
import 'ai_card_summary_dialog.dart';
import 'ai_config_dialog.dart';
import 'knowledge_card_dialog.dart';
import 'latex_interactive_view.dart';
import 'markdown_html_support.dart';
import 'markdown_reader_view.dart';

class AiChatSidebarTab extends StatefulWidget {
  final int currentPage;
  final int totalPages;
  final String documentTitle;
  final String docId;
  final Future<String?> Function(int pageNumber)? onGetPageContext;

  const AiChatSidebarTab({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.documentTitle,
    this.docId = '',
    this.onGetPageContext,
  });

  @override
  State<AiChatSidebarTab> createState() => _AiChatSidebarTabState();
}

class _AiChatSidebarTabState extends State<AiChatSidebarTab> with SingleTickerProviderStateMixin {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutQuad,
        );
      }
    });
  }

  Future<void> _sendCurrentMessage([String? customPrompt]) async {
    final text = customPrompt ?? _inputController.text.trim();
    final aiProvider = context.read<AiProvider>();

    if (text.isEmpty && !aiProvider.hasPendingQuote) return;

    final targetPage = aiProvider.pendingQuotedPage ?? widget.currentPage;
    final pageContext = await widget.onGetPageContext?.call(targetPage);

    _inputController.clear();
    aiProvider.sendMessage(
      text,
      pageContextText: pageContext,
      documentTitle: widget.documentTitle,
    );

    _scrollToBottom();
  }

  void _openConfigDialog() {
    showDialog(
      context: context,
      builder: (_) => const AiConfigDialog(),
    );
  }

  String _findRelevantQuoteForMessage(ChatMessage msg, AiProvider aiProvider) {
    if (msg.quotedText != null && msg.quotedText!.trim().isNotEmpty) {
      return msg.quotedText!.trim();
    }
    final idx = aiProvider.messages.indexOf(msg);
    if (idx > 0) {
      for (int i = idx - 1; i >= 0; i--) {
        final prev = aiProvider.messages[i];
        if (prev.quotedText != null && prev.quotedText!.trim().isNotEmpty) {
          return prev.quotedText!.trim();
        }
      }
    }
    return '';
  }

  int _findRelevantPageForMessage(ChatMessage msg, AiProvider aiProvider) {
    if (msg.pageNumber != null && msg.pageNumber! > 0) {
      return msg.pageNumber!;
    }
    final idx = aiProvider.messages.indexOf(msg);
    if (idx > 0) {
      for (int i = idx - 1; i >= 0; i--) {
        final prev = aiProvider.messages[i];
        if (prev.pageNumber != null && prev.pageNumber! > 0) {
          return prev.pageNumber!;
        }
      }
    }
    return widget.currentPage;
  }

  void _saveDirectlyAsKnowledgeCard(BuildContext context, ChatMessage msg, AiProvider aiProvider) {
    final quote = _findRelevantQuoteForMessage(msg, aiProvider);
    final pageNumber = _findRelevantPageForMessage(msg, aiProvider);

    showDialog(
      context: context,
      builder: (_) => KnowledgeCardDialog(
        initialQuote: quote,
        initialContent: msg.content,
        pageNumber: pageNumber,
        docId: widget.docId,
        startInEditMode: false,
        onSave: (newCard) {
          context.read<AnnotationProvider>().addAnnotation(newCard);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Color(0xFF86EFAC), size: 18),
                  SizedBox(width: 8),
                  Text('已成功将 AI 回答保存为知识卡片'),
                ],
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      ),
    );
  }

  void _summarizeAndSaveAsKnowledgeCard(BuildContext context, ChatMessage msg, AiProvider aiProvider) {
    final quote = _findRelevantQuoteForMessage(msg, aiProvider);
    final pageNumber = _findRelevantPageForMessage(msg, aiProvider);

    showDialog(
      context: context,
      builder: (_) => AiCardSummaryDialog(
        config: aiProvider.config,
        conversationHistory: aiProvider.messages,
        targetMessage: msg,
        initialQuote: quote,
        pageNumber: pageNumber,
        docId: widget.docId,
        documentTitle: widget.documentTitle,
        onSave: (newCard) {
          context.read<AnnotationProvider>().addAnnotation(newCard);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Color(0xFF86EFAC), size: 18),
                  SizedBox(width: 8),
                  Text('已成功生成并保存结构化知识卡片'),
                ],
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final aiProvider = context.watch<AiProvider>();
    final settings = context.watch<ReaderSettingsProvider>();
    final theme = Theme.of(context);
    final isDark = settings.readingMode == ReadingMode.dark;
    final isSepia = settings.readingMode == ReadingMode.sepia;

    final cardBg = isDark
        ? const Color(0xFF1E293B)
        : isSepia
            ? const Color(0xFFF7EED9)
            : const Color(0xFFFFFFFF);

    final inputBg = isDark
        ? const Color(0xFF0F172A)
        : isSepia
            ? const Color(0xFFEFE6CF)
            : const Color(0xFFF8FAFC);

    final textColor = isDark
        ? const Color(0xFFF1F5F9)
        : isSepia
            ? const Color(0xFF3D2714)
            : const Color(0xFF1E293B);

    return Column(
      children: [
        // 1. Top Bar (Model badge + Settings button + Clear button)
        _buildHeaderBar(context, theme, isDark, aiProvider),
        const Divider(height: 1),

        // 2. Unconfigured Alert Banner (if apiKey is empty)
        if (!aiProvider.isConfigured)
          _buildConfigBanner(context, theme, isDark),

        // 3. Message History List
        Expanded(
          child: aiProvider.messages.isEmpty
              ? _buildEmptyState(context, theme, isDark, aiProvider)
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  itemCount: aiProvider.messages.length,
                  itemBuilder: (ctx, idx) {
                    final msg = aiProvider.messages[idx];
                    return _buildMessageItem(ctx, msg, isDark, isSepia, theme, textColor, cardBg, aiProvider);
                  },
                ),
        ),

        // 4. Quoted Reference Preview (if user clicked "问AI" on text / formula)
        if (aiProvider.hasPendingQuote)
          _buildPendingQuoteCard(context, theme, isDark, aiProvider),

        // 5. Quick action chips & Context Toggle
        _buildQuickChipsBar(context, theme, isDark, aiProvider),

        // 6. Bottom Prompt Composer Input
        _buildComposerBar(context, theme, isDark, inputBg, textColor, aiProvider),
      ],
    );
  }

  Widget _buildHeaderBar(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    AiProvider aiProvider,
  ) {
    final rawModel = aiProvider.config.model.trim();
    final modelName = rawModel.isNotEmpty ? rawModel : '请选择模型...';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // Model Badge
          Tooltip(
            message: rawModel.isNotEmpty
                ? '当前使用的 AI 模型: $rawModel (点击修改配置)'
                : '尚未选择 AI 模型 (点击进行配置与选择)',
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _openConfigDialog,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: isDark ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome_rounded, size: 13, color: Color(0xFF8B5CF6)),
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 130),
                      child: Text(
                        modelName,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF8B5CF6),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),

          // Clear history button
          if (aiProvider.messages.isNotEmpty)
            Tooltip(
              message: '清空当前对话记录',
              child: IconButton(
                icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('清空对话记录'),
                      content: const Text('确定要清空当前的 AI 对话历史吗？'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: Colors.red),
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            aiProvider.clearHistory();
                          },
                          child: const Text('清空'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          const SizedBox(width: 4),

          // Settings Button
          Tooltip(
            message: 'AI API 密钥与模型配置',
            child: IconButton(
              icon: const Icon(Icons.settings_outlined, size: 18),
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(),
              onPressed: _openConfigDialog,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigBanner(BuildContext context, ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: isDark ? 0.15 : 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.amber),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '尚未配置 API Key',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: _openConfigDialog,
            child: const Text('立即配置', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    AiProvider aiProvider,
  ) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.auto_awesome_rounded, size: 36, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Text(
              'AI 文献阅读助手',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '划选文章段落或 LaTeX 公式点击“问AI”，\n或直接在下方输入问题',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 20),

            // Quick Starter Cards
            _buildStarterChip('🇨🇳 翻译并解析当前页面内容', () => _sendCurrentMessage('请翻译并详细解析本页内容。')),
            const SizedBox(height: 6),
            _buildStarterChip('📝 提炼本页核心论点与要点', () => _sendCurrentMessage('请提炼归纳本页的核心论点与结论。')),
            const SizedBox(height: 6),
            _buildStarterChip('📐 梳理公式含义与推导逻辑', () => _sendCurrentMessage('请详细梳理本页的数学公式、符号定义及其推导逻辑。')),
          ],
        ),
      ),
    );
  }

  Widget _buildStarterChip(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF334155)
                : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 11, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageItem(
    BuildContext context,
    ChatMessage msg,
    bool isDark,
    bool isSepia,
    ThemeData theme,
    Color textColor,
    Color cardBg,
    AiProvider aiProvider,
  ) {
    if (msg.isUser) {
      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Quoted Card if present
            if (msg.hasQuote) ...[
              Container(
                constraints: const BoxConstraints(maxWidth: 320),
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: isDark ? 0.18 : 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: const Border(
                    left: BorderSide(color: Color(0xFF8B5CF6), width: 3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.format_quote_rounded, size: 12, color: Color(0xFF8B5CF6)),
                        const SizedBox(width: 4),
                        Text(
                          '第 ${msg.pageNumber ?? "?"} 页引文',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF8B5CF6),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      msg.quotedText!,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.3,
                        color: isDark ? Colors.grey.shade300 : Colors.grey.shade800,
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],

            // User Prompt Bubble
            Container(
              constraints: const BoxConstraints(maxWidth: 320),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(4),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4F46E5).withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: SelectableText(
                msg.content,
                style: const TextStyle(fontSize: 13, color: Colors.white, height: 1.4),
              ),
            ),
          ],
        ),
      );
    }

    // Assistant Message
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Thinking Process Card (Collapsible, Auto-folds after completion)
          if (msg.hasThinking)
            _buildThinkingCard(context, msg, isDark, theme, aiProvider),

          // 2. Assistant Answer Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (msg.content.isEmpty && msg.isStreaming && !msg.hasThinking) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('AI 正在思考并组织回答...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ] else if (msg.content.isNotEmpty) ...[
                  MarkdownBody(
                    data: msg.content,
                    selectable: true,
                    extensionSet: md.ExtensionSet(
                      md.ExtensionSet.gitHubFlavored.blockSyntaxes,
                      [
                        LatexBlockInlineSyntax(),
                        LatexBracketInlineSyntax(),
                        LatexInlineSyntax(),
                        LatexParenInlineSyntax(),
                        MarkdownHighlightInlineSyntax(),
                        HtmlMarkInlineSyntax(),
                        ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
                      ],
                    ),
                    builders: {
                      'latex': _AiLatexBuilder(isDark: isDark, textColor: textColor),
                      'code': _AiCodeBuilder(isDark: isDark, textColor: textColor),
                      'mark': CommonMarkElementBuilder(isDark: isDark, fontSize: 13),
                    },
                    styleSheet: MarkdownStyleSheet(
                      p: TextStyle(fontSize: 13, height: 1.6, color: textColor),
                      h1: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor),
                      h2: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: textColor),
                      h3: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: textColor),
                      code: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                        color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      codeblockPadding: const EdgeInsets.all(10),
                      tableBorder: TableBorder.all(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                        width: 0.8,
                      ),
                      tableCellsPadding: const EdgeInsets.all(6),
                      tableBody: TextStyle(fontSize: 12, color: textColor),
                      tableHead: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor),
                    ),
                  ),
                ],

                // Error Message if any
                if (msg.error != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 16, color: Colors.red),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            msg.error!,
                            style: const TextStyle(fontSize: 11, color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Action Footer
                if (msg.content.isNotEmpty && !msg.isStreaming) ...[
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          aiProvider.config.model,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),

                      // 1. Save Directly as Knowledge Card (Icon Only)
                      Tooltip(
                        message: '保存为知识卡片',
                        child: IconButton(
                          padding: const EdgeInsets.all(5),
                          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                          icon: const Icon(
                            Icons.style_rounded,
                            size: 15,
                            color: Color(0xFF8B5CF6),
                          ),
                          onPressed: () => _saveDirectlyAsKnowledgeCard(context, msg, aiProvider),
                        ),
                      ),

                      // 2. Summarize & Save as Knowledge Card (Icon Only)
                      Tooltip(
                        message: 'AI总结提炼并保存为卡片',
                        child: IconButton(
                          padding: const EdgeInsets.all(5),
                          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                          icon: const Icon(
                            Icons.auto_awesome_rounded,
                            size: 15,
                            color: Color(0xFF6366F1),
                          ),
                          onPressed: () => _summarizeAndSaveAsKnowledgeCard(context, msg, aiProvider),
                        ),
                      ),

                      // 3. Copy Answer Button (Icon Only)
                      Tooltip(
                        message: '复制回答内容',
                        child: IconButton(
                          padding: const EdgeInsets.all(5),
                          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                          icon: Icon(
                            Icons.copy_rounded,
                            size: 14,
                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                          ),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: msg.content));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('已复制 AI 回答到剪贴板'),
                                duration: Duration(seconds: 1),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThinkingCard(
    BuildContext context,
    ChatMessage msg,
    bool isDark,
    ThemeData theme,
    AiProvider aiProvider,
  ) {
    final isExpanded = msg.isThinkingExpanded;
    final isThinking = msg.isThinking;
    final durationSeconds = ((msg.thinkingDurationMs ?? 0) / 1000).toStringAsFixed(1);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Collapsible Header
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => aiProvider.toggleThinkingExpanded(msg.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                children: [
                  Icon(
                    Icons.psychology_rounded,
                    size: 15,
                    color: isThinking ? const Color(0xFF8B5CF6) : Colors.grey,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isThinking
                        ? '深度思考中...'
                        : (msg.thinkingDurationMs != null ? '已深度思考 ($durationSeconds 秒)' : '思考过程'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isThinking ? const Color(0xFF8B5CF6) : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                    ),
                  ),
                  if (isThinking) ...[
                    const SizedBox(width: 6),
                    const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                  ],
                  const Spacer(),
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ),

          // Thinking Body Content
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(10),
              child: SelectableText(
                msg.thinkingContent ?? '',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.45,
                  fontStyle: FontStyle.italic,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPendingQuoteCard(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    AiProvider aiProvider,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF8B5CF6).withValues(alpha: isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF8B5CF6).withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.format_quote_rounded, size: 14, color: Color(0xFF8B5CF6)),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '已引用第 ${aiProvider.pendingQuotedPage ?? widget.currentPage} 页文本/公式',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF8B5CF6),
                  ),
                ),
                Text(
                  aiProvider.pendingQuotedText!,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.grey.shade300 : Colors.grey.shade800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 14),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
            splashRadius: 14,
            onPressed: () => aiProvider.clearPendingQuote(),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickChipsBar(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    AiProvider aiProvider,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Include Page Context Toggle Chip
            FilterChip(
              label: Text('传递第 ${widget.currentPage} 页上下文'),
              labelStyle: TextStyle(
                fontSize: 10.5,
                fontWeight: aiProvider.config.includePageContext ? FontWeight.bold : FontWeight.normal,
                color: aiProvider.config.includePageContext
                    ? (isDark ? const Color(0xFF86EFAC) : const Color(0xFF15803D))
                    : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
              ),
              selected: aiProvider.config.includePageContext,
              selectedColor: const Color(0xFF10B981).withValues(alpha: isDark ? 0.25 : 0.15),
              checkmarkColor: isDark ? const Color(0xFF86EFAC) : const Color(0xFF15803D),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              onSelected: (val) => aiProvider.setIncludePageContext(val),
            ),
            const SizedBox(width: 6),

            // Quick Prompt Chips
            _buildActionChip('🇨🇳 翻译', () => _sendCurrentMessage('请将这段内容准确翻译成通顺的中文。')),
            const SizedBox(width: 4),
            _buildActionChip('🔍 解析', () => _sendCurrentMessage('请深入解析此内容的学术背景、含义与逻辑。')),
            const SizedBox(width: 4),
            _buildActionChip('📐 推导', () => _sendCurrentMessage('请详细推导此公式并解释各个变量含义。')),
            const SizedBox(width: 4),
            _buildActionChip('📝 摘要', () => _sendCurrentMessage('请用简明扼要的三句话总结此内容。')),
          ],
        ),
      ),
    );
  }

  Widget _buildActionChip(String label, VoidCallback onTap) {
    return ActionChip(
      label: Text(label),
      labelStyle: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onPressed: onTap,
    );
  }

  Widget _buildComposerBar(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    Color inputBg,
    Color textColor,
    AiProvider aiProvider,
  ) {
    final isGenerating = aiProvider.isGenerating;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            width: 0.8,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: inputBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                ),
              ),
              child: TextField(
                controller: _inputController,
                focusNode: _focusNode,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendCurrentMessage(),
                style: TextStyle(fontSize: 12.5, color: textColor, height: 1.4),
                decoration: InputDecoration(
                  hintText: aiProvider.hasPendingQuote
                      ? '输入针对引文的问题 (例如: 翻译/推导)...'
                      : '向 AI 提问或解析文献...',
                  hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Send / Stop Button
          if (isGenerating)
            IconButton(
              icon: const Icon(Icons.stop_circle_rounded, color: Colors.red, size: 28),
              tooltip: '停止生成',
              onPressed: () => aiProvider.stopGeneration(),
            )
          else
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFF6366F1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 16),
              ),
              tooltip: '发送 (Enter)',
              onPressed: () => _sendCurrentMessage(),
            ),
        ],
      ),
    );
  }
}

class _AiLatexBuilder extends MarkdownElementBuilder {
  final bool isDark;
  final Color textColor;

  _AiLatexBuilder({required this.isDark, required this.textColor});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final text = element.textContent.trim();
    if (text.isEmpty) return null;
    final isDisplay = element.attributes['display'] == 'true';

    try {
      return InteractiveLatexView(
        rawLatex: text,
        isDisplay: isDisplay,
        textColor: textColor,
        baseFontSize: 13,
        codeBg: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
        isDark: isDark,
        pageNumber: 1,
      );
    } catch (_) {
      return Text(text, style: preferredStyle);
    }
  }
}

class _AiCodeBuilder extends MarkdownElementBuilder {
  final bool isDark;
  final Color textColor;

  _AiCodeBuilder({required this.isDark, required this.textColor});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final className = element.attributes['class'] ?? '';
    final isLatex = className.contains('language-latex') ||
        className.contains('language-tex') ||
        className.contains('language-math');

    final text = element.textContent.trim();
    if (isLatex && text.isNotEmpty) {
      return LatexFencedBlockWidget(
        rawLatex: text,
        textColor: textColor,
        baseFontSize: 13,
        codeBg: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
        isDark: isDark,
        pageNumber: 1,
      );
    }
    return null;
  }
}
