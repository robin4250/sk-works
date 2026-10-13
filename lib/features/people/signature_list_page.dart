import 'package:flutter/material.dart';

import 'company_document_exchange_repository.dart';
import 'signature_send_page.dart';

class SignatureListPage extends StatefulWidget {
  const SignatureListPage({super.key});

  @override
  State<SignatureListPage> createState() => _SignatureListPageState();
}

class _SignatureListPageState extends State<SignatureListPage> {
  final _repository = CompanyDocumentExchangeRepository.maybeCreate();
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) {
      setState(() {
        _loading = false;
        _error = 'サイン一覧を利用できません。';
      });
      return;
    }
    try {
      final sources = await repository.listSignatureSources();
      final items = sources
          .where((row) => row['kind']?.toString() == 'daily_report_signature')
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('PostgrestException(message: ', '').replaceFirst('Bad state: ', '');
      });
    }
  }

  Future<void> _send() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SignatureSendPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'サイン一覧',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'サイン一覧を送信',
            onPressed: _loading || _items.isEmpty ? null : _send,
            icon: const Icon(Icons.send_outlined),
          ),
          IconButton(
            tooltip: '再読み込み',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!, textAlign: TextAlign.center),
                    ),
                  )
                : _items.isEmpty
                    ? const Center(child: Text('保存済みのサインはありません'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          return Card(
                            child: ListTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.draw_outlined),
                              ),
                              title: Text(
                                item['name']?.toString() ?? 'サイン',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              subtitle: Text(
                                item['group']?.toString() ?? '',
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
