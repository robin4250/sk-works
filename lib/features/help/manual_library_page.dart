import 'package:flutter/material.dart';

import 'manual_content.dart';
import 'manual_pdf_service.dart';

class ManualLibraryPage extends StatelessWidget {
  const ManualLibraryPage({
    super.key,
    required this.role,
  });

  final ManualRole role;

  @override
  Widget build(BuildContext context) {
    final sections = ManualContent.forRole(role);
    final roleLabel = ManualContent.roleLabel(role);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '使い方・説明書',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '$roleLabel用説明書',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${sections.length}ページ構成です。'
                      '画面内でも読めて、A4 PDFとしてプレビュー・印刷・共有できます。',
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ManualPdfPreviewPage.role(role: role),
                        ),
                      ),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: Text('$roleLabel用説明書 PDFを開く'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const ManualPdfPreviewPage.pamphlet(),
                        ),
                      ),
                      icon: const Icon(Icons.menu_book_outlined),
                      label: const Text('SKOパンフレット 20ページを開く'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '画面で読む',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < sections.length; i++) ...[
              _ManualSectionCard(
                number: i + 1,
                section: sections[i],
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _ManualSectionCard extends StatelessWidget {
  const _ManualSectionCard({
    required this.number,
    required this.section,
  });

  final int number;
  final ManualSection section;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: CircleAvatar(
          child: Text(
            '$number',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        title: Text(
          section.title,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(section.summary),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.touch_app_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '⭕ ここを押す：${section.buttonLabel}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < section.steps.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                radius: 15,
                child: Text('${i + 1}'),
              ),
              title: Text(section.steps[i]),
            ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.support_agent_outlined),
            title: const Text(
              'サポート・補足',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(section.support),
          ),
        ],
      ),
    );
  }
}
