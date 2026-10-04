import 'package:flutter/material.dart';

import '../../international/language_controller.dart';
import '../../widgets/sko_scroll_chrome.dart';
import 'floating_help_controller.dart';
import 'menu_help_catalog.dart';

class FloatingHelpOverlay extends StatefulWidget {
  const FloatingHelpOverlay({super.key});

  @override
  State<FloatingHelpOverlay> createState() => _FloatingHelpOverlayState();
}

class _FloatingHelpOverlayState extends State<FloatingHelpOverlay> {
  bool _loaded = false;
  bool _dragging = false;
  Offset? _dragPosition;
  Offset? _dragStartPosition;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await FloatingHelpController.load();
    if (!mounted) return;
    setState(() => _loaded = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();

    return ValueListenableBuilder<bool>(
      valueListenable: FloatingHelpController.enabled,
      builder: (context, enabled, _) {
        if (!enabled) return const SizedBox.shrink();

        return LayoutBuilder(
          builder: (context, constraints) {
            const size = 52.0;
            const margin = 8.0;
            final maxX = (constraints.maxWidth - size - margin).clamp(0.0, double.infinity);
            const footerClearance = 78.0;
            final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
            final bottomClearance = keyboardHeight > 0
                ? keyboardHeight + 12.0
                : footerClearance;
            final maxY = (constraints.maxHeight - size - bottomClearance)
                .clamp(0.0, double.infinity);

            return AnimatedBuilder(
              animation: Listenable.merge([
                FloatingHelpController.xFraction,
                FloatingHelpController.yFraction,
              ]),
              builder: (context, _) {
                final left = (_dragPosition?.dx ??
                        FloatingHelpController.xFraction.value * maxX)
                    .clamp(margin, maxX);
                final top = (_dragPosition?.dy ??
                        FloatingHelpController.yFraction.value * maxY)
                    .clamp(margin, maxY);

                return Stack(
                  children: [
                    Positioned(
                      left: left,
                      top: top,
                      child: SafeArea(
                        child: Material(
                          elevation: 8,
                          shape: const CircleBorder(),
                          child: GestureDetector(
                            onTap: _dragging ? null : _openHelp,
                            onLongPressStart: (_) {
                              setState(() {
                                _dragging = true;
                                _dragStartPosition = Offset(left, top);
                                _dragPosition = _dragStartPosition;
                              });
                            },
                            onLongPressMoveUpdate: (details) {
                              setState(() {
                                final start =
                                    _dragStartPosition ?? Offset(left, top);
                                _dragPosition = Offset(
                                  (start.dx + details.offsetFromOrigin.dx)
                                      .clamp(margin, maxX),
                                  (start.dy + details.offsetFromOrigin.dy)
                                      .clamp(margin, maxY),
                                );
                              });
                            },
                            onLongPressEnd: (_) async {
                              final position = _dragPosition ?? Offset(left, top);
                              await FloatingHelpController.savePosition(
                                x: maxX <= 0 ? 0 : position.dx / maxX,
                                y: maxY <= 0 ? 0 : position.dy / maxY,
                              );
                              if (!mounted) return;
                              setState(() {
                                _dragging = false;
                                _dragPosition = null;
                                _dragStartPosition = null;
                              });
                            },
                            child: Semantics(
                              button: true,
                              label: SkoLanguageController.isEnglish
                                  ? 'Help'
                                  : '何かお困りですか？',
                              child: Container(
                                width: size,
                                height: size,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Theme.of(context).colorScheme.surface,
                                    width: 2,
                                  ),
                                ),
                                child: Icon(
                                  Icons.question_mark_rounded,
                                  color: Theme.of(context).colorScheme.onPrimary,
                                  size: 28,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _openHelp() async {
    final navContext = SkoScrollChromeController.navigatorKey.currentContext;
    if (navContext == null) return;

    final current = FloatingHelpController.currentHelpItem();
    final items = FloatingHelpController.searchableItems();

    await showModalBottomSheet<void>(
      context: navContext,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _FloatingHelpSheet(
        current: current,
        items: items,
      ),
    );
  }
}

class _FloatingHelpSheet extends StatefulWidget {
  const _FloatingHelpSheet({
    required this.current,
    required this.items,
  });

  final MenuHelpItem? current;
  final List<MenuHelpItem> items;

  @override
  State<_FloatingHelpSheet> createState() => _FloatingHelpSheetState();
}

class _FloatingHelpSheetState extends State<_FloatingHelpSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final english = SkoLanguageController.isEnglish;
    final needle = _query.trim().toLowerCase();
    final filtered = widget.items.where((item) {
      if (needle.isEmpty) return true;
      final haystack = [
        item.label,
        item.purpose,
        item.destination,
        item.access,
        item.details,
      ].join(' ').toLowerCase();
      return haystack.contains(needle);
    }).toList(growable: false);

    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.82,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                english ? 'How can I help?' : '何かお困りですか？',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                english
                    ? 'Search by page, feature, or action.'
                    : 'ページ名・機能名・操作名から使い方を探せます。',
              ),
              if (widget.current != null) ...[
                const SizedBox(height: 14),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.auto_awesome_outlined),
                    title: Text(
                      english
                          ? 'About this screen'
                          : 'いま開いている画面について',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(
                      english
                          ? widget.current!.label
                          : widget.current!.label,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showItem(widget.current!),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: english
                      ? 'Search help'
                      : '例：給与明細、日報、現場、承認',
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          english
                              ? 'No matching help topics.'
                              : '該当する説明がありません',
                        ),
                      )
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          return Card(
                            child: ListTile(
                              title: Text(
                                item.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(item.purpose),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _showItem(item),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showItem(MenuHelpItem item) {
    final english = SkoLanguageController.isEnglish;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(item.label),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                english ? 'What it does' : '何ができる？',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(item.purpose),
              const SizedBox(height: 12),
              Text(
                english ? 'Where it opens' : 'どこへ進む？',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(item.destination),
              if (item.details.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  english ? 'How to use it' : '使い方・ポイント',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(item.details),
              ],
              const SizedBox(height: 12),
              Text(
                english ? 'Who can use it' : '利用できる人',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(item.access),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(english ? 'Close' : '閉じる'),
          ),
        ],
      ),
    );
  }
}
