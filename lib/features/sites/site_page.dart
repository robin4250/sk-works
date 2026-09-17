import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SiteStatus { preparing, active, paused, completed }

extension SiteStatusLabel on SiteStatus {
  String get label => switch (this) {
        SiteStatus.preparing => '準備中',
        SiteStatus.active => '進行中',
        SiteStatus.paused => '一時停止',
        SiteStatus.completed => '完了',
      };
}

class SiteRecord {
  const SiteRecord({
    required this.id,
    required this.name,
    required this.customerName,
    required this.status,
    this.address = '',
    this.managerName = '',
    this.startDate = '',
    this.endDate = '',
    this.notes = '',
  });

  final String id;
  final String name;
  final String customerName;
  final SiteStatus status;
  final String address;
  final String managerName;
  final String startDate;
  final String endDate;
  final String notes;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'customerName': customerName,
        'status': status.name,
        'address': address,
        'managerName': managerName,
        'startDate': startDate,
        'endDate': endDate,
        'notes': notes,
      };

  factory SiteRecord.fromJson(Map<String, dynamic> json) {
    return SiteRecord(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      customerName: json['customerName']?.toString() ?? '',
      status: SiteStatus.values.firstWhere(
        (value) => value.name == json['status'],
        orElse: () => SiteStatus.preparing,
      ),
      address: json['address']?.toString() ?? '',
      managerName: json['managerName']?.toString() ?? '',
      startDate: json['startDate']?.toString() ?? '',
      endDate: json['endDate']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
    );
  }
}

class SitePage extends StatefulWidget {
  const SitePage({super.key});

  @override
  State<SitePage> createState() => _SitePageState();
}

class _SitePageState extends State<SitePage> {
  static const _storageKey = 'sk_works_sites_v2';
  final _sites = <SiteRecord>[];
  String _query = '';
  SiteStatus? _filter;
  bool _loading = true;

  static const _samples = [
    SiteRecord(
      id: 'sumida-renovation',
      name: '墨田区〇〇改修工事',
      customerName: '株式会社ABC',
      status: SiteStatus.active,
      managerName: '山田 太郎',
      address: '東京都墨田区',
    ),
    SiteRecord(
      id: 'koto-newbuild',
      name: '江東区△△新築工事',
      customerName: '株式会社XYZ',
      status: SiteStatus.preparing,
      managerName: '佐藤 次郎',
      address: '東京都江東区',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var loaded = <SiteRecord>[];
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        loaded = decoded
            .map((item) => SiteRecord.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      loaded = [];
    }
    if (loaded.isEmpty) loaded = List<SiteRecord>.from(_samples);
    if (!mounted) return;
    setState(() {
      _sites
        ..clear()
        ..addAll(loaded);
      _loading = false;
    });
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode(_sites.map((site) => site.toJson()).toList()),
      );
    } catch (_) {
      // Prototype persistence is best-effort until cloud storage is connected.
    }
  }

  @override
  Widget build(BuildContext context) {
    final needle = _query.trim().toLowerCase();
    final filtered = _sites.where((site) {
      final matchesStatus = _filter == null || site.status == _filter;
      final haystack = [
        site.name,
        site.customerName,
        site.address,
        site.managerName,
        site.notes,
      ].join(' ').toLowerCase();
      return matchesStatus && (needle.isEmpty || haystack.contains(needle));
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('現場管理')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _add,
        icon: const Icon(Icons.add_business),
        label: const Text('現場登録'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '現場名・得意先・担当者・住所で検索',
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('すべて'),
                    selected: _filter == null,
                    onSelected: (_) => setState(() => _filter = null),
                  ),
                  const SizedBox(width: 8),
                  for (final status in SiteStatus.values) ...[
                    ChoiceChip(
                      label: Text(status.label),
                      selected: _filter == status,
                      onSelected: (_) => setState(() => _filter = status),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? const Center(child: Text('該当する現場はありません'))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final site = filtered[index];
                            return Card(
                              child: ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.apartment_outlined),
                                ),
                                title: Text(
                                  site.name,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                subtitle: Text(
                                  [
                                    site.customerName,
                                    site.status.label,
                                    if (site.managerName.isNotEmpty) site.managerName,
                                  ].join(' / '),
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _showDetails(site),
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

  Future<void> _add() async {
    final site = await Navigator.of(context).push<SiteRecord>(
      MaterialPageRoute(builder: (_) => const SiteFormPage()),
    );
    if (site == null) return;
    setState(() => _sites.insert(0, site));
    await _save();
  }

  void _showDetails(SiteRecord site) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(site.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text('得意先: ${site.customerName}'),
              Text('状態: ${site.status.label}'),
              if (site.managerName.isNotEmpty) Text('担当者: ${site.managerName}'),
              if (site.address.isNotEmpty) Text('住所: ${site.address}'),
              if (site.startDate.isNotEmpty) Text('開始日: ${site.startDate}'),
              if (site.endDate.isNotEmpty) Text('終了日: ${site.endDate}'),
              if (site.notes.isNotEmpty) Text('備考: ${site.notes}'),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(sheetContext);
                  setState(() => _sites.remove(site));
                  await _save();
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('削除'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SiteFormPage extends StatefulWidget {
  const SiteFormPage({super.key});

  @override
  State<SiteFormPage> createState() => _SiteFormPageState();
}

class _SiteFormPageState extends State<SiteFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _customer = TextEditingController();
  final _address = TextEditingController();
  final _manager = TextEditingController();
  final _startDate = TextEditingController();
  final _endDate = TextEditingController();
  final _notes = TextEditingController();
  SiteStatus _status = SiteStatus.preparing;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _customer,
      _address,
      _manager,
      _startDate,
      _endDate,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('現場 - 新規登録')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: '現場名'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? '現場名を入力してください'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _customer,
                decoration: const InputDecoration(labelText: '得意先'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? '得意先を入力してください'
                    : null,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<SiteStatus>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: '状態'),
                items: SiteStatus.values
                    .map((status) => DropdownMenuItem(
                          value: status,
                          child: Text(status.label),
                        ))
                    .toList(),
                onChanged: (value) => setState(() => _status = value ?? _status),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _manager,
                decoration: const InputDecoration(labelText: '担当者'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _address,
                decoration: const InputDecoration(labelText: '住所'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _startDate,
                decoration: const InputDecoration(labelText: '開始日 (YYYY/MM/DD)'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _endDate,
                decoration: const InputDecoration(labelText: '終了日 (YYYY/MM/DD)'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '備考'),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.save_outlined),
                label: const Text('登録する'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      SiteRecord(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: _name.text.trim(),
        customerName: _customer.text.trim(),
        status: _status,
        address: _address.text.trim(),
        managerName: _manager.text.trim(),
        startDate: _startDate.text.trim(),
        endDate: _endDate.text.trim(),
        notes: _notes.text.trim(),
      ),
    );
  }
}
