import 'package:flutter/material.dart';

/// Keeps raw, unsaved editor input while the payroll list scrolls off screen.
/// The caller keys this by worker; changing worker starts a separate editor.
class PayrollDraftKeepAlive extends StatefulWidget {
  const PayrollDraftKeepAlive({super.key, required this.child});

  final Widget child;

  @override
  State<PayrollDraftKeepAlive> createState() => _PayrollDraftKeepAliveState();
}

class _PayrollDraftKeepAliveState extends State<PayrollDraftKeepAlive>
    with AutomaticKeepAliveClientMixin<PayrollDraftKeepAlive> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
