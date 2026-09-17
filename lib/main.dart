import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const SkWorksApp());
}

class SkWorksApp extends StatelessWidget {
  const SkWorksApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF173B57);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SK WORKS',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F6F8),
        cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  static final List<ModuleDefinition> modules = [
    ModuleDefinition(
      storageKey: 'people',
      title: '社員・協力会社',
      subtitle: '社員・下請け会社・作業員を管理',
      icon: Icons.people_alt_outlined,
      fields: const ['氏名 / 会社名', '区分', '電話番号', '備考'],
      samples: const [
        ['山田 太郎', '社員', '090-0000-0000', '現場責任者'],
        ['株式会社サンプル工業', '協力会社', '03-0000-0000', '足場・雑工'],
      ],
    ),
    ModuleDefinition(
      storageKey: 'qualifications',
      title: '資格管理',
      subtitle: '資格マスターと保有資格を管理',
      icon: Icons.badge_outlined,
      fields: const ['資格名', '保有者', '有効期限', '備考'],
      samples: const [
        ['職長・安全衛生責任者', '山田 太郎', '期限なし', '登録済'],
        ['玉掛け技能講習', '佐藤 次郎', '期限なし', '修了証あり'],
      ],
    ),
    ModuleDefinition(
      storageKey: 'sites',
      title: '現場管理',
      subtitle: '現場情報・担当者・進捗を管理',
      icon: Icons.apartment_outlined,
      fields: const ['現場名', '得意先', '担当者', '状態'],
      samples: const [
        ['墨田区〇〇改修工事', '株式会社ABC', '山田 太郎', '進行中'],
        ['江東区△△新築工事', '株式会社XYZ', '佐藤 次郎', '準備中'],
      ],
    ),
    ModuleDefinition(
      storageKey: 'attendance',
      title: '勤怠・人工',
      subtitle: '出面・人工・残業などを記録',
      icon: Icons.schedule_outlined,
      fields: const ['日付', '作業員', '現場', '人工 / 時間'],
      samples: const [
        ['2026/09/17', '山田 太郎', '墨田区〇〇改修工事', '1.0人工'],
        ['2026/09/17', '佐藤 次郎', '墨田区〇〇改修工事', '1.0人工 + 残業2h'],
      ],
    ),
    ModuleDefinition(
      storageKey: 'invoices',
      title: '請求管理',
      subtitle: '得意先・現場別の請求を管理',
      icon: Icons.receipt_long_outlined,
      fields: const ['請求先', '対象期間', '請求額', '状態'],
      samples: const [
        ['株式会社ABC', '2026年9月', '¥1,250,000', '作成中'],
        ['株式会社XYZ', '2026年8月', '¥840,000', '請求済'],
      ],
    ),
    ModuleDefinition(
      storageKey: 'settings',
      title: '設定',
      subtitle: '会社情報・各種マスターを設定',
      icon: Icons.settings_outlined,
      fields: const ['設定項目', '内容', '区分', '備考'],
      samples: const [
        ['会社名', 'SK WORKS', '基本情報', ''],
        ['消費税率', '10%', '請求設定', '標準税率'],
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SK WORKS'),
        actions: [
          IconButton(
            tooltip: '通知',
            onPressed: () => _showInfo(context, '通知機能は今後接続します'),
            icon: const Icon(Icons.notifications_none),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const _HeaderCard(),
            const SizedBox(height: 16),
            const _StatusStrip(),
            const SizedBox(height: 20),
            Text(
              '業務メニュー',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 10),
            ...modules.map(
              (module) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: CircleAvatar(child: Icon(module.icon)),
                    title: Text(
                      module.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(module.subtitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ModulePage(module: module),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showInfo(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SK WORKS',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 6),
            const Text('会社・現場・人員・資格・勤怠・請求をひとつに。'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('本日の入力画面は次段階で追加します')),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('本日の入力を開始'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip();

  @override
  Widget build(BuildContext context) {
    const items = [
      ('稼働現場', '2'),
      ('登録人員', '2'),
      ('資格', '2'),
      ('請求作成中', '1'),
    ];

    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = items[index];
          return SizedBox(
            width: 112,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.$2,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(item.$1, maxLines: 1),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class ModuleDefinition {
  ModuleDefinition({
    required this.storageKey,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.fields,
    required this.samples,
  });

  final String storageKey;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<String> fields;
  final List<List<String>> samples;
}

class ModulePage extends StatefulWidget {
  const ModulePage({super.key, required this.module});

  final ModuleDefinition module;

  @override
  State<ModulePage> createState() => _ModulePageState();
}

class _ModulePageState extends State<ModulePage> {
  final List<List<String>> records = [];
  final SharedPreferencesAsync prefs = SharedPreferencesAsync();
  bool loading = true;
  String query = '';

  String get storageKey => 'sk_works_${widget.module.storageKey}_v1';

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    List<List<String>> loaded = [];
    try {
      final raw = await prefs.getString(storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        loaded = decoded
            .map((row) => (row as List<dynamic>).map((e) => e.toString()).toList())
            .toList();
      }
    } catch (_) {
      loaded = [];
    }

    if (loaded.isEmpty) {
      loaded = widget.module.samples.map((row) => List<String>.from(row)).toList();
    }

    if (!mounted) return;
    setState(() {
      records
        ..clear()
        ..addAll(loaded);
      loading = false;
    });
  }

  Future<void> _saveRecords() async {
    try {
      await prefs.setString(storageKey, jsonEncode(records));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('端末保存に失敗しました。入力内容は現在の画面には残っています。')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = records.where((row) {
      if (query.trim().isEmpty) return true;
      final needle = query.toLowerCase();
      return row.any((value) => value.toLowerCase().contains(needle));
    }).toList();

    return Scaffold(
      appBar: AppBar(title: Text(widget.module.title)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: loading ? null : _addRecord,
        icon: const Icon(Icons.add),
        label: const Text('新規登録'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '検索',
                ),
                onChanged: (value) => setState(() => query = value),
              ),
            ),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? const Center(child: Text('該当するデータがありません'))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final row = filtered[index];
                            return Card(
                              child: ListTile(
                                title: Text(
                                  row.first,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    row.skip(1).where((e) => e.isNotEmpty).join(' / '),
                                  ),
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _showDetails(row),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addRecord() async {
    final result = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => RecordFormPage(
          title: '${widget.module.title} - 新規登録',
          fields: widget.module.fields,
        ),
      ),
    );
    if (result != null) {
      setState(() => records.insert(0, result));
      await _saveRecords();
    }
  }

  void _showDetails(List<String> row) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.first,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                for (var i = 0; i < widget.module.fields.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 100,
                          child: Text(
                            widget.module.fields[i],
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(child: Text(row.length > i ? row[i] : '')),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _deleteRecord(row);
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('削除'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.check),
                        label: const Text('閉じる'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteRecord(List<String> row) async {
    setState(() => records.remove(row));
    await _saveRecords();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('データを削除しました')),
    );
  }
}

class RecordFormPage extends StatefulWidget {
  const RecordFormPage({
    super.key,
    required this.title,
    required this.fields,
  });

  final String title;
  final List<String> fields;

  @override
  State<RecordFormPage> createState() => _RecordFormPageState();
}

class _RecordFormPageState extends State<RecordFormPage> {
  final formKey = GlobalKey<FormState>();
  late final List<TextEditingController> controllers;

  @override
  void initState() {
    super.initState();
    controllers = List.generate(widget.fields.length, (_) => TextEditingController());
  }

  @override
  void dispose() {
    for (final controller in controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Form(
          key: formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (var i = 0; i < widget.fields.length; i++) ...[
                TextFormField(
                  controller: controllers[i],
                  decoration: InputDecoration(labelText: widget.fields[i]),
                  validator: i == 0
                      ? (value) {
                          if (value == null || value.trim().isEmpty) {
                            return '${widget.fields[i]}を入力してください';
                          }
                          return null;
                        }
                      : null,
                ),
                const SizedBox(height: 14),
              ],
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('登録する'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _save() {
    if (!(formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      controllers.map((controller) => controller.text.trim()).toList(),
    );
  }
}
