import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../../theme/app_theme.dart';

/// Interactive Widget for inline and display LaTeX math formulas.
/// Supports hover affordance, 1-click LaTeX source copy, fluorescent highlighting, and note annotations.
class InteractiveLatexView extends StatefulWidget {
  final String rawLatex;
  final bool isDisplay;
  final Color textColor;
  final double baseFontSize;
  final Color codeBg;
  final bool isDark;
  final String? highlightColor;
  final int pageNumber;
  final void Function(String rawLatex, String colorHex, {required bool isDisplay, required int pageNumber})? onHighlight;
  final void Function(String rawLatex, {required bool isDisplay, required int pageNumber})? onRemoveHighlight;
  final void Function(String rawLatex, {required bool isDisplay, required int pageNumber})? onAddNote;
  final void Function(String rawLatex, {required bool isDisplay, required int pageNumber})? onAskAi;

  const InteractiveLatexView({
    super.key,
    required this.rawLatex,
    required this.isDisplay,
    required this.textColor,
    required this.baseFontSize,
    required this.codeBg,
    required this.isDark,
    this.highlightColor,
    required this.pageNumber,
    this.onHighlight,
    this.onRemoveHighlight,
    this.onAddNote,
    this.onAskAi,
  });

  @override
  State<InteractiveLatexView> createState() => _InteractiveLatexViewState();
}

class _InteractiveLatexViewState extends State<InteractiveLatexView> {
  bool _isHovered = false;

  void _copyLatex(BuildContext context, {bool withDelimiters = false}) {
    final textToCopy = withDelimiters
        ? (widget.isDisplay ? '\$\$${widget.rawLatex}\$\$' : '\$${widget.rawLatex}\$')
        : widget.rawLatex;

    Clipboard.setData(ClipboardData(text: textToCopy));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF86EFAC), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '已复制 LaTeX 原文: $textToCopy',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _openActionDialog(BuildContext context) {
    showLatexActionDialog(
      context: context,
      rawLatex: widget.rawLatex,
      isDisplay: widget.isDisplay,
      textColor: widget.textColor,
      baseFontSize: widget.baseFontSize,
      codeBg: widget.codeBg,
      isDark: widget.isDark,
      highlightColor: widget.highlightColor,
      pageNumber: widget.pageNumber,
      onHighlight: widget.onHighlight,
      onRemoveHighlight: widget.onRemoveHighlight,
      onAddNote: widget.onAddNote,
      onAskAi: widget.onAskAi,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasHighlight = widget.highlightColor != null && widget.highlightColor!.isNotEmpty;
    Color? highlightBase;
    if (hasHighlight) {
      try {
        highlightBase = AppTheme.parseHexColor(widget.highlightColor!);
      } catch (_) {
        highlightBase = const Color(0xFFFDE047);
      }
    }

    final mathWidget = Math.tex(
      widget.rawLatex,
      mathStyle: widget.isDisplay ? MathStyle.display : MathStyle.text,
      textStyle: TextStyle(
        color: widget.textColor,
        fontSize: widget.baseFontSize * (widget.isDisplay ? 1.1 : 1.02),
      ),
      onErrorFallback: (err) {
        return Text(
          widget.rawLatex,
          style: TextStyle(
            fontFamily: 'monospace',
            color: widget.textColor,
            fontSize: widget.baseFontSize * 0.9,
          ),
        );
      },
    );

    if (widget.isDisplay) {
      // Display Math Block
      final bg = hasHighlight
          ? highlightBase!.withValues(alpha: widget.isDark ? 0.30 : 0.22)
          : (_isHovered ? (widget.isDark ? const Color(0x22818CF8) : const Color(0x114F46E5)) : Colors.transparent);

      final borderColor = hasHighlight
          ? highlightBase!.withValues(alpha: widget.isDark ? 0.75 : 0.60)
          : (_isHovered ? (widget.isDark ? const Color(0xFF6366F1) : const Color(0xFF818CF8)) : Colors.transparent);

      return Center(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onTap: () => _openActionDialog(context),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: borderColor,
                  width: hasHighlight ? 1.2 : 1.0,
                ),
                boxShadow: hasHighlight
                    ? [
                        BoxShadow(
                          color: highlightBase!.withValues(alpha: widget.isDark ? 0.20 : 0.12),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        )
                      ]
                    : null,
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: mathWidget,
                  ),
                  // Subtle top-right quick actions on hover
                  if (_isHovered)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: widget.isDark ? const Color(0xFF1E293B) : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: widget.isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                            width: 0.8,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              onTap: () => _copyLatex(context, withDelimiters: false),
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.all(3),
                                child: Icon(
                                  Icons.copy_rounded,
                                  size: 13,
                                  color: widget.isDark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5),
                                ),
                              ),
                            ),
                            const SizedBox(width: 2),
                            InkWell(
                              onTap: () => _openActionDialog(context),
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.all(3),
                                child: Icon(
                                  Icons.palette_outlined,
                                  size: 13,
                                  color: widget.isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                                ),
                              ),
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
      );
    } else {
      // Inline Math
      final bg = hasHighlight
          ? highlightBase!.withValues(alpha: widget.isDark ? 0.30 : 0.22)
          : (_isHovered ? (widget.isDark ? const Color(0x33818CF8) : const Color(0x224F46E5)) : Colors.transparent);

      final border = hasHighlight
          ? Border.all(
              color: highlightBase!.withValues(alpha: widget.isDark ? 0.75 : 0.60),
              width: 1.0,
            )
          : (_isHovered
              ? Border.all(
                  color: (widget.isDark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5)).withValues(alpha: 0.6),
                  width: 1.0,
                )
              : null);

      return MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: () => _openActionDialog(context),
          child: Tooltip(
            message: 'LaTeX: \$${widget.rawLatex}\$ (点击复制/高亮/批注)',
            waitDuration: const Duration(milliseconds: 400),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(6),
                border: border,
                boxShadow: hasHighlight
                    ? [
                        BoxShadow(
                          color: highlightBase!.withValues(alpha: widget.isDark ? 0.20 : 0.12),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: mathWidget,
            ),
          ),
        ),
      );
    }
  }
}

/// Interactive Fenced LaTeX Code Block Widget (` ```latex ` / ` ```math ` / ` ```tex `)
class LatexFencedBlockWidget extends StatefulWidget {
  final String rawLatex;
  final Color textColor;
  final double baseFontSize;
  final Color codeBg;
  final bool isDark;
  final String? highlightColor;
  final int pageNumber;
  final void Function(String rawLatex, String colorHex, {required bool isDisplay, required int pageNumber})? onHighlight;
  final void Function(String rawLatex, {required bool isDisplay, required int pageNumber})? onRemoveHighlight;
  final void Function(String rawLatex, {required bool isDisplay, required int pageNumber})? onAddNote;
  final void Function(String rawLatex, {required bool isDisplay, required int pageNumber})? onAskAi;

  const LatexFencedBlockWidget({
    super.key,
    required this.rawLatex,
    required this.textColor,
    required this.baseFontSize,
    required this.codeBg,
    required this.isDark,
    this.highlightColor,
    required this.pageNumber,
    this.onHighlight,
    this.onRemoveHighlight,
    this.onAddNote,
    this.onAskAi,
  });

  @override
  State<LatexFencedBlockWidget> createState() => _LatexFencedBlockWidgetState();
}

class _LatexFencedBlockWidgetState extends State<LatexFencedBlockWidget> {
  bool _showSourceCode = false;

  void _copyCode(BuildContext context) {
    Clipboard.setData(ClipboardData(text: widget.rawLatex));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF86EFAC), size: 18),
            const SizedBox(width: 8),
            const Text('已复制 LaTeX 源码到剪贴板'),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _openActionDialog(BuildContext context) {
    showLatexActionDialog(
      context: context,
      rawLatex: widget.rawLatex,
      isDisplay: true,
      textColor: widget.textColor,
      baseFontSize: widget.baseFontSize,
      codeBg: widget.codeBg,
      isDark: widget.isDark,
      highlightColor: widget.highlightColor,
      pageNumber: widget.pageNumber,
      onHighlight: widget.onHighlight,
      onRemoveHighlight: widget.onRemoveHighlight,
      onAddNote: widget.onAddNote,
      onAskAi: widget.onAskAi,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasHighlight = widget.highlightColor != null && widget.highlightColor!.isNotEmpty;
    Color? highlightBase;
    if (hasHighlight) {
      try {
        highlightBase = AppTheme.parseHexColor(widget.highlightColor!);
      } catch (_) {
        highlightBase = const Color(0xFFFDE047);
      }
    }

    final borderColor = hasHighlight
        ? highlightBase!.withValues(alpha: widget.isDark ? 0.75 : 0.60)
        : (widget.isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1));

    final cardBg = hasHighlight
        ? highlightBase!.withValues(alpha: widget.isDark ? 0.22 : 0.16)
        : widget.codeBg.withValues(alpha: widget.isDark ? 0.6 : 0.85);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: hasHighlight ? 1.2 : 1.0),
        boxShadow: [
          BoxShadow(
            color: hasHighlight
                ? highlightBase!.withValues(alpha: widget.isDark ? 0.25 : 0.15)
                : Colors.black.withValues(alpha: widget.isDark ? 0.3 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: widget.isDark
                  ? const Color(0xFF0F172A).withValues(alpha: 0.8)
                  : const Color(0xFFF1F5F9).withValues(alpha: 0.9),
              border: Border(
                bottom: BorderSide(
                  color: widget.isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                  width: 0.8,
                ),
              ),
            ),
            child: Row(
              children: [
                // Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: widget.isDark
                        ? const Color(0xFF6366F1).withValues(alpha: 0.2)
                        : const Color(0xFF4F46E5).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.functions_rounded,
                        size: 14,
                        color: widget.isDark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'LaTeX 公式',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: widget.isDark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // View Mode Toggle Button
                Tooltip(
                  message: _showSourceCode ? '切换为渲染视图' : '切换为 LaTeX 源码',
                  child: InkWell(
                    onTap: () => setState(() => _showSourceCode = !_showSourceCode),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _showSourceCode
                            ? (widget.isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0))
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: widget.isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _showSourceCode ? Icons.visibility_rounded : Icons.code_rounded,
                            size: 13,
                            color: widget.textColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _showSourceCode ? '公式渲染' : '源码',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: widget.textColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Highlight Color Popup Menu (Compact fluorescent color bubbles bar only)
                PopupMenuButton<String>(
                  tooltip: '选择公式高亮颜色',
                  icon: Icon(
                    Icons.palette_outlined,
                    size: 16,
                    color: hasHighlight ? highlightBase : widget.textColor.withValues(alpha: 0.8),
                  ),
                  splashRadius: 16,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                  offset: const Offset(0, 32),
                  elevation: 8,
                  color: widget.isDark ? const Color(0xFF1E293B) : Colors.white,
                  surfaceTintColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: widget.isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                      width: 0.8,
                    ),
                  ),
                  itemBuilder: (popupCtx) => [
                    PopupMenuItem<String>(
                      enabled: false,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      height: 38,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ...AppTheme.highlightColors.map((colorItem) {
                            final isChosen = widget.highlightColor?.toUpperCase() == colorItem.hex.toUpperCase();
                            final color = AppTheme.parseHexColor(colorItem.hex);
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 3),
                              child: Tooltip(
                                message: colorItem.label,
                                child: InkWell(
                                  onTap: () {
                                    Navigator.of(popupCtx).pop();
                                    widget.onHighlight?.call(
                                      widget.rawLatex,
                                      colorItem.hex,
                                      isDisplay: true,
                                      pageNumber: widget.pageNumber,
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: color,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isChosen
                                            ? (widget.isDark ? Colors.white : const Color(0xFF0F172A))
                                            : Colors.black12,
                                        width: isChosen ? 2.2 : 1.0,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: color.withValues(alpha: 0.4),
                                          blurRadius: 4,
                                          offset: const Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                    child: isChosen
                                        ? const Icon(Icons.check, size: 14, color: Colors.black87)
                                        : null,
                                  ),
                                ),
                              ),
                            );
                          }),
                          if (hasHighlight) ...[
                            Container(
                              height: 18,
                              width: 1,
                              color: widget.isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                            ),
                            Tooltip(
                              message: '清除高亮',
                              child: InkWell(
                                onTap: () {
                                  Navigator.of(popupCtx).pop();
                                  widget.onRemoveHighlight?.call(
                                    widget.rawLatex,
                                    isDisplay: true,
                                    pageNumber: widget.pageNumber,
                                  );
                                },
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: widget.isDark ? 0.2 : 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close_rounded,
                                    size: 14,
                                    color: Colors.red,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 4),
                // Ask AI Button
                Tooltip(
                  message: '向 AI 提问/推导此公式',
                  child: IconButton(
                    icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                    splashRadius: 16,
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                    color: const Color(0xFF8B5CF6),
                    onPressed: () => widget.onAskAi?.call(widget.rawLatex, isDisplay: true, pageNumber: widget.pageNumber),
                  ),
                ),
                const SizedBox(width: 4),
                // Copy Button
                Tooltip(
                  message: '复制 LaTeX 原文',
                  child: IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    splashRadius: 16,
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                    color: widget.textColor.withValues(alpha: 0.8),
                    onPressed: () => _copyCode(context),
                  ),
                ),
              ],
            ),
          ),
          // Content Area (Clicking formula opens full LaTeX action dialog)
          Padding(
            padding: const EdgeInsets.all(16),
            child: _showSourceCode
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: widget.isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: widget.isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: SelectableText(
                      widget.rawLatex,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: widget.baseFontSize * 0.9,
                        color: widget.isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                        height: 1.5,
                      ),
                    ),
                  )
                : MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => _openActionDialog(context),
                      child: Tooltip(
                        message: '点击打开公式操作面板 (复制/高亮/批注)',
                        waitDuration: const Duration(milliseconds: 500),
                        child: Center(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Math.tex(
                              widget.rawLatex,
                              mathStyle: MathStyle.display,
                              textStyle: TextStyle(
                                color: widget.textColor,
                                fontSize: widget.baseFontSize * 1.15,
                              ),
                              onErrorFallback: (err) {
                                return Text(
                                  widget.rawLatex,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    color: widget.textColor,
                                    fontSize: widget.baseFontSize * 0.9,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Interactive Dialog for LaTeX Formulas: Copying, Fluorescent Highlighting, and Adding Notes
void showLatexActionDialog({
  required BuildContext context,
  required String rawLatex,
  required bool isDisplay,
  required Color textColor,
  required double baseFontSize,
  required Color codeBg,
  required bool isDark,
  String? highlightColor,
  required int pageNumber,
  void Function(String rawLatex, String colorHex, {required bool isDisplay, required int pageNumber})? onHighlight,
  void Function(String rawLatex, {required bool isDisplay, required int pageNumber})? onRemoveHighlight,
  void Function(String rawLatex, {required bool isDisplay, required int pageNumber})? onAddNote,
  void Function(String rawLatex, {required bool isDisplay, required int pageNumber})? onAskAi,
}) {
  showDialog(
    context: context,
    builder: (dialogCtx) {
      String? selectedColor = highlightColor;

      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isHighlighted = selectedColor != null && selectedColor!.isNotEmpty;

          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            actionsPadding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF6366F1).withValues(alpha: 0.2) : const Color(0xFF4F46E5).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.functions_rounded,
                    size: 20,
                    color: isDark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'LaTeX 数学公式',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        '第 $pageNumber 页 · 支持公式复制、荧光高亮、批注与 AI 解析',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  splashRadius: 18,
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Rendered Preview Card
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Center(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Math.tex(
                            rawLatex,
                            mathStyle: isDisplay ? MathStyle.display : MathStyle.text,
                            textStyle: TextStyle(
                              color: textColor,
                              fontSize: baseFontSize * 1.2,
                            ),
                            onErrorFallback: (err) {
                              return Text(
                                rawLatex,
                                style: const TextStyle(fontFamily: 'monospace'),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // LaTeX Source Code Box with Copy Buttons
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: codeBg.withValues(alpha: isDark ? 0.5 : 0.8),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'LaTeX 源码',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                ),
                              ),
                              const Spacer(),
                              // Copy Raw button
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  visualDensity: VisualDensity.compact,
                                ),
                                icon: const Icon(Icons.copy_rounded, size: 14),
                                label: const Text('复制纯代码', style: TextStyle(fontSize: 12)),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: rawLatex));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('已复制 LaTeX 纯代码: $rawLatex'),
                                      duration: const Duration(seconds: 2),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 4),
                              // Copy with Delimiters button
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  visualDensity: VisualDensity.compact,
                                ),
                                icon: const Icon(Icons.data_object_rounded, size: 14),
                                label: Text(isDisplay ? '复制 \$\$...\$\$' : '复制 \$...\$', style: const TextStyle(fontSize: 12)),
                                onPressed: () {
                                  final fullStr = isDisplay ? '\$\$$rawLatex\$\$' : '\$$rawLatex\$';
                                  Clipboard.setData(ClipboardData(text: fullStr));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('已复制 Markdown 公式: $fullStr'),
                                      duration: const Duration(seconds: 2),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            rawLatex,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Fluorescent Highlighter Palette
                    Row(
                      children: [
                        Icon(
                          Icons.palette_rounded,
                          size: 16,
                          color: isDark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '公式荧光高亮',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A),
                          ),
                        ),
                        const Spacer(),
                        if (isHighlighted)
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red.shade400,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: const Icon(Icons.highlight_off_rounded, size: 14),
                            label: const Text('清除高亮', style: TextStyle(fontSize: 12)),
                            onPressed: () {
                              setDialogState(() => selectedColor = null);
                              onRemoveHighlight?.call(rawLatex, isDisplay: isDisplay, pageNumber: pageNumber);
                              Navigator.of(dialogCtx).pop();
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Color bubbles
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: AppTheme.highlightColors.map((colorItem) {
                        final isChosen = selectedColor?.toUpperCase() == colorItem.hex.toUpperCase();
                        final color = AppTheme.parseHexColor(colorItem.hex);

                        return Tooltip(
                          message: '${colorItem.label} (${colorItem.hex})',
                          child: InkWell(
                            onTap: () {
                              setDialogState(() => selectedColor = colorItem.hex);
                              onHighlight?.call(rawLatex, colorItem.hex, isDisplay: isDisplay, pageNumber: pageNumber);
                              Navigator.of(dialogCtx).pop();
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isChosen
                                      ? (isDark ? Colors.white : const Color(0xFF0F172A))
                                      : Colors.transparent,
                                  width: 2.2,
                                ),
                              ),
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: color.withValues(alpha: 0.4),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: isChosen
                                    ? const Icon(
                                        Icons.check,
                                        size: 16,
                                        color: Colors.black87,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              // Ask AI Button
              TextButton.icon(
                icon: const Icon(Icons.auto_awesome_rounded, size: 16, color: Color(0xFF8B5CF6)),
                label: const Text('问 AI 公式解析', style: TextStyle(color: Color(0xFF8B5CF6), fontWeight: FontWeight.bold)),
                onPressed: () {
                  Navigator.of(dialogCtx).pop();
                  onAskAi?.call(rawLatex, isDisplay: isDisplay, pageNumber: pageNumber);
                },
              ),
              const SizedBox(width: 4),
              // Add Note Button
              TextButton.icon(
                icon: const Icon(Icons.edit_note_rounded, size: 16),
                label: const Text('添加批注笔记'),
                onPressed: () {
                  Navigator.of(dialogCtx).pop();
                  onAddNote?.call(rawLatex, isDisplay: isDisplay, pageNumber: pageNumber);
                },
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('完成'),
                onPressed: () => Navigator.of(dialogCtx).pop(),
              ),
            ],
          );
        },
      );
    },
  );
}
