import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'company_contact_parser.dart';

class CompanyContactValue extends StatelessWidget {
  const CompanyContactValue({
    super.key,
    required this.text,
    this.uri,
    required this.onOpen,
  });
  final String text;
  final Uri? uri;
  final Future<void> Function(Uri) onOpen;
  @override
  Widget build(BuildContext context) => uri == null
      ? SelectableText(text)
      : InkWell(
          onTap: () => onOpen(uri!),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              text,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        );
}

class CompanyNotesLinks extends StatefulWidget {
  const CompanyNotesLinks({
    super.key,
    required this.text,
    required this.onOpen,
  });
  final String text;
  final Future<void> Function(Uri) onOpen;
  @override
  State<CompanyNotesLinks> createState() => _CompanyNotesLinksState();
}

class _CompanyNotesLinksState extends State<CompanyNotesLinks> {
  final _recognizers = <TapGestureRecognizer>[];
  late List<({String text, Uri? uri})> _parts;
  void _load() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
    _parts = companyNoteParts(widget.text);
    for (final part in _parts) {
      if (part.uri != null)
        _recognizers.add(
          TapGestureRecognizer()..onTap = () => widget.onOpen(part.uri!),
        );
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CompanyNotesLinks oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _load();
  }

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var index = 0;
    return SelectionArea(
      child: Text.rich(
        TextSpan(
          children: [
            for (final part in _parts)
              TextSpan(
                text: part.text,
                recognizer: part.uri == null ? null : _recognizers[index++],
                style: part.uri == null
                    ? null
                    : TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        decoration: TextDecoration.underline,
                      ),
              ),
          ],
        ),
      ),
    );
  }
}
