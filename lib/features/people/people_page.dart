import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PersonKind { employee, partnerCompany, partnerWorker }

extension PersonKindLabel on PersonKind {
  String get label => switch (this) {
        PersonKind.employee => '社員',
        PersonKind.partnerCompany => '協力会社',
        PersonKind.partnerWorker => '協力会社作業員',
      };
}

class PersonRecord {
  const PersonRecord({
    required this.id,
    required this.kind,
    required this.name,
    this.companyName = '',
    this.phone = '',
    this.email = '',
    this.role = '',
    this.notes = '',
    this.active = true,
  });

  final String id;
  final PersonKind kind;
  final String name;
  final String companyName;
  final String phone;
  final String email;
  final String role;
  final String notes;
  final bool active;

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.name,
        'name': name,
        'companyName': companyName,
        'phone': phone,
        'email': email,
        'role': role,
        'notes': notes,
        'active': active,
      };

  factory PersonRecord.fromJson(Map<String, dynamic> json) {
    return PersonRecord(
      id: json['id']?.toString() ?? '',
      kind: PersonKind.values.firstWhere(
        (value) => value.name == json['kind'],
        orElse: () => PersonKind.employee,
      ),
      name: json['name']?.toString() ?? '',
      companyName: json['companyName']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      active: json['active'] is bool ? json['active'] as bool : true,
    );
  }
}

class PeoplePage extends StatefulWidget {
  const PeoplePage({super.key});

  @override
  State<PeoplePage> createState() => _PeoplePageState();
}

class _PeoplePageState extends State<PeoplePage> {
  static const _storageKey = 'sk_works_people_v2';
  final _records = <PersonRecord>[];
  String _query = '';
  PersonKind? _filter;
  bool _loading = true;

  static const _samples = [
    PersonRecord(
      id: 'employee-yamada',
      kind: PersonKind.employee,
      name: '山田 太郎',
      phone: '090-0000-0000',
      role: '現場責任者',
    ),
    PersonRecord(
      id: 'partner-sample',
      kind: PersonKind.partnerCompany,
      name: '株式会社サンプル工業',
      phone: '03-0000-0000',
      role: '足場・雑工',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var loaded = <PersonRecord>[];
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        loaded = decoded
            .map((item) => PersonRecord.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      loaded = [];
    }
    if (loaded.isEmpty) loaded = List<PersonRecord>.from(_samples);
    if (!mounted) return;
    setState(() {
      _records
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
        jsonEncode(_records.map((record) => record.toJson()).toList()),
      );
    } catch (_) {
      // Local persistence is best-effort in the prototype phase.
    }
  }

  @override
  Widget build(BuildContext context) {
    final needle = _query.trim().toLowerCase();
    final filtered = _records.where((record) {
      final matchesKind = _filter == null || record.kind == _filter;
      final haystack = [
        record.name,
        record.companyName,
        record.phone,
        record.email,
        record.role,
        record.notes,
      ].join(' ').toLowerCase();
      return matchesKind && (needle.isEmpty || haystack.contains(needle));
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('社員・協力会社')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _add,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('新規登録'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '氏名・会社名・電話番号などで検索',
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
                  for (final kind in PersonKind.values) ...[
                    ChoiceChip(
                      label: Text(kind.label),
                      selected: _filter == kind,
                      onSelected: (_) => setState(() => _filter = kind),
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
                      ? const Center(child: Text('該当する登録はありません'))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final record = filtered[index];
                            final subtitleParts = <String>[
                              record.kind.label,
                              if (record.companyName.isNotEmpty) record.companyName,
                              if (record.role.isNotEmpty) record.role,
                              if (record.phone.isNotEmpty) record.phone,
                            ];
                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  child: Icon(
                                    record.kind == PersonKind.partnerCompany
                                        ? Icons.business_outlined
                                        : Icons.person_outline,
                                  ),
                                ),
                                title: Text(
                                  record.name,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                subtitle: Text(subtitleParts.join(' / ')),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _showDetails(record),
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
    final record = await Navigator.of(context).push<PersonRecord>(
      MaterialPageRoute(builder: (_) => const PersonFormPage()),
    );
    if (record == null) return;
    setState(() => _records.insert(0, record));
    await _save();
  }

  void _showDetails(PersonRecord record) {
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
              Text(record.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text('区分: ${record.kind.label}'),
              if (record.companyName.isNotEmpty) Text('会社: ${record.companyName}'),
              if (record.role.isNotEmpty) Text('役割・職種: ${record.role}'),
              if (record.phone.isNotEmpty) Text('電話: ${record.phone}'),
              if (record.email.isNotEmpty) Text('メール: ${record.email}'),
              if (record.notes.isNotEmpty) Text('備考: ${record.notes}'),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(sheetContext);
                  setState(() => _records.remove(record));
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

class PersonFormPage extends StatefulWidget {
  const PersonFormPage({super.key});

  @override
  State<PersonFormPage> createState() => _PersonFormPageState();
}

class _PersonFormPageState extends State<PersonFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _company = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _role = TextEditingController();
  final _notes = TextEditingController();
  PersonKind _kind = PersonKind.employee;

  @override
  void dispose() {
    for (final controller in [_name, _company, _phone, _email, _role, _notes]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('社員・協力会社 - 新規登録')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<PersonKind>(
                initialValue: _kind,
                decoration: const InputDecoration(labelText: '区分'),
                items: PersonKind.values
                    .map((kind) => DropdownMenuItem(value: kind, child: Text(kind.label)))
                    .toList(),
                onChanged: (value) => setState(() => _kind = value ?? _kind),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: _kind == PersonKind.partnerCompany ? '会社名' : '氏名',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? '名称を入力してください'
                    : null,
              ),
              const SizedBox(height: 14),
              if (_kind == PersonKind.partnerWorker) ...[
                TextField(
                  controller: _company,
                  decoration: const InputDecoration(labelText: '所属会社'),
                ),
                const SizedBox(height: 14),
              ],
              TextField(
                controller: _role,
                decoration: const InputDecoration(labelText: '役割・職種'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: '電話番号'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'メールアドレス'),
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
      PersonRecord(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        kind: _kind,
        name: _name.text.trim(),
        companyName: _company.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        role: _role.text.trim(),
        notes: _notes.text.trim(),
      ),
    );
  }
}
