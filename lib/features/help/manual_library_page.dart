import 'package:flutter/material.dart';

import 'manual_content.dart';
import 'manual_pdf_service.dart';
import 'manual_version.dart';
import '../../international/language_controller.dart';

class ManualLibraryPage extends StatelessWidget {
  const ManualLibraryPage({
    super.key,
    required this.role,
  });

  final ManualRole role;

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    final sections = ManualContent.forRole(role);
    final roleLabel = SkoLanguageController.tr(ManualContent.roleLabel(role));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          SkoLanguageController.tr('使い方・説明書'),
          style: const TextStyle(fontWeight: FontWeight.w900),
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
                      SkoLanguageController.trParams('{role}用説明書', {'role': roleLabel}),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(SkoLanguageController.trParams(
                      'SKO v{version} / ベータ版 / {date}',
                      {'version': ManualVersion.appVersion, 'date': ManualVersion.revisionDate},
                    )),
                    const SizedBox(height: 8),
                    Text(SkoLanguageController.trParams(
                      '{count}章を機能別に読めます。PDFのページ数は内容に合わせて増えます。',
                      {'count': sections.length},
                    )),
                    Text(SkoLanguageController.tr('PDFは日本語版です。')),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ManualPdfPreviewPage.role(role: role),
                        ),
                      ),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: Text(SkoLanguageController.trParams('{role}用説明書 PDFを開く', {'role': roleLabel})),
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
                      label: Text(SkoLanguageController.tr('SKOベータ版パンフレットを開く')),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              SkoLanguageController.tr('機能別目次'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < sections.length; i++)
              ListTile(
                leading: Text('${i + 1}'),
                title: Text(SkoLanguageController.tr(sections[i].title)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ManualChapterPage(section: sections[i], number: i + 1),
                )),
              ),
            const SizedBox(height: 16),
            Text(SkoLanguageController.tr('画面で読む')),
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
    this.initiallyExpanded = false,
  });

  final int number;
  final ManualSection section;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    return Card(
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        leading: CircleAvatar(
          child: Text(
            '$number',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        title: Text(
          SkoLanguageController.tr(section.title),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(SkoLanguageController.tr(section.summary)),
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
                    SkoLanguageController.trParams('⭕ ここを押す：{button}', {'button': SkoLanguageController.tr(section.buttonLabel)}),
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
              title: Text(SkoLanguageController.tr(section.steps[i])),
            ),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ManualPdfPreviewPage.chapter(section: section),
            )),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(SkoLanguageController.tr('この機能のPDFを開く')),
          ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.support_agent_outlined),
            title: Text(
              SkoLanguageController.tr('サポート・補足'),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(SkoLanguageController.tr(section.support)),
          ),
        ],
      ),
    );
  }
}


class ManualChapterPage extends StatelessWidget {
  const ManualChapterPage({super.key, required this.section, required this.number});
  final ManualSection section;
  final int number;

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    return Scaffold(
      appBar: AppBar(title: Text(SkoLanguageController.tr(section.title))),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(16),
        children: [
          Text(ManualVersion.revisionLabel),
          const SizedBox(height: 8),
          _ManualSectionCard(number: number, section: section, initiallyExpanded: true),
        ])),
    );
  }
}
