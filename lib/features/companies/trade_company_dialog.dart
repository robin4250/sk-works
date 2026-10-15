import 'package:flutter/material.dart';

/// Company details and every subsequent decision use the same action geometry.
/// Each action retains its existing button type, callback and enabled state.
class TradeCompanyDialog extends StatelessWidget {
  const TradeCompanyDialog({
    super.key,
    required this.title,
    this.content,
    required this.actions,
  });
  final Widget title;
  final Widget? content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: title,
    content: content,
    scrollable: true,
    actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
    actions: [
      SizedBox(
        width: 500,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .48,
          ),
          child: SingleChildScrollView(
            child: TradeCompanyActionButtons(actions: actions),
          ),
        ),
      ),
    ],
  );
}

class TradeCompanyActionButtons extends StatelessWidget {
  const TradeCompanyActionButtons({super.key, required this.actions});
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      alignment: Alignment.center,
    );
    return Theme(
      data: theme.copyWith(
        textButtonTheme: TextButtonThemeData(
          style: theme.textButtonTheme.style?.merge(style) ?? style,
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: theme.outlinedButtonTheme.style?.merge(style) ?? style,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: theme.filledButtonTheme.style?.merge(style) ?? style,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            actions[i],
          ],
        ],
      ),
    );
  }
}
