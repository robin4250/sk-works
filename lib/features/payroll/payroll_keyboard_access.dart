import 'package:flutter/material.dart';

/// Dismisses an editor keyboard without changing its controllers or save state.
class PayrollKeyboardDismissArea extends StatelessWidget {
  const PayrollKeyboardDismissArea({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
    child: child,
  );
}

/// Keeps both the existing actions and a numeric-keyboard completion control
/// above the keyboard. The completion control never submits the form.
class PayrollKeyboardFooter extends StatelessWidget {
  const PayrollKeyboardFooter({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (inset > 0)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const ValueKey('payroll-keyboard-done'),
                onPressed: () => FocusManager.instance.primaryFocus?.unfocus(),
                icon: const Icon(Icons.keyboard_hide),
                label: const Text('完了'),
              ),
            ),
          child,
        ],
      ),
    );
  }
}
