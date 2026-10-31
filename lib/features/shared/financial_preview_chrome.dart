import 'package:flutter/material.dart';

/// Keeps document controls together without reducing text scaling or tap targets.
/// Long warnings remain in the open, scrollable header rather than a disclosure.
class FinancialPreviewChrome extends StatefulWidget {
  const FinancialPreviewChrome({
    super.key,
    required this.actions,
    required this.status,
    required this.preview,
    required this.footer,
  });
  final List<Widget> actions, status;
  final Widget preview, footer;

  @override
  State<FinancialPreviewChrome> createState() => _FinancialPreviewChromeState();
}

class _FinancialPreviewChromeState extends State<FinancialPreviewChrome> {
  final _controls = ScrollController();
  @override
  void dispose() {
    _controls.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final actionStyle = TextButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        textStyle: const TextStyle(fontSize: 14),
      );
      return Column(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: constraints.maxHeight * .38),
            child: Scrollbar(
              controller: _controls,
              child: SingleChildScrollView(
                controller: _controls,
                primary: false,
                key: const ValueKey('financial_preview_controls_scroll'),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ...widget.status,
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: TextButtonTheme(
                        data: TextButtonThemeData(style: actionStyle),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 0,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: widget.actions,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: SizedBox(
              key: const ValueKey('financial_preview_document_viewport'),
              width: double.infinity,
              child: widget.preview,
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              key: const ValueKey('financial_preview_footer'),
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: widget.footer,
            ),
          ),
        ],
      );
    },
  );
}
