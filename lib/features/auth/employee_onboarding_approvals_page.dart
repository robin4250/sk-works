import 'package:flutter/material.dart';

import 'employee_onboarding_repository.dart';

class EmployeeOnboardingApprovalsPage extends StatefulWidget {
  const EmployeeOnboardingApprovalsPage({super.key});

  @override
  State<EmployeeOnboardingApprovalsPage> createState() =>
      _EmployeeOnboardingApprovalsPageState();
}

class _EmployeeOnboardingApprovalsPageState
    extends State<EmployeeOnboardingApprovalsPage> {
  final _repository = EmployeeOnboardingRepository.maybeCreate();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];

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
        _error = '本登録承認を利用できません。';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final canReview = await repository.canReview();
      if (!canReview) {
        throw StateError('本登録を承認する権限がありません。');
      }
      final rows = await repository.loadPendingApprovals();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  Future<void> _approve(Map<String, dynamic> row) async {
    final repository = _repository;
    final inviteId = row['invite_id']?.toString();
    if (repository == null || inviteId == null || inviteId.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('本登録しますか？'),
        content: Text(
          '${row['name'] ?? '従業員'}さんをSKOの一般ユーザーとして本登録します。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('本登録'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await repository.approve(inviteId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('本登録が完了しました')),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('本登録できませんでした: $error')),
      );
    }
  }

  Widget _detailLine(String label, Object? value) {
    final text = value?.toString().trim() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(child: Text(text.isEmpty ? '未入力' : text)),
        ],
      ),
    );
  }

  Widget _imagePreview(String label, String? path) {
    final repository = _repository;
    if (repository == null || path == null || path.isEmpty) {
      return ListTile(
        leading: const Icon(Icons.image_not_supported_outlined),
        title: Text(label),
        subtitle: const Text('画像なし'),
      );
    }

    return FutureBuilder<String>(
      future: repository.signedUrl(path),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return ListTile(
            leading: const CircularProgressIndicator(),
            title: Text(label),
          );
        }
        if (snapshot.hasError || snapshot.data == null) {
          return ListTile(
            leading: const Icon(Icons.broken_image_outlined),
            title: Text(label),
            subtitle: const Text('表示できませんでした'),
          );
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    snapshot.data!,
                    height: 220,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        const Text('画像を表示できませんでした'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openDetails(Map<String, dynamic> row) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('本登録内容の確認')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _detailLine('名前', row['name']),
                        _detailLine('電話番号', row['phone']),
                        _detailLine('住所', row['address']),
                        _detailLine('血液型', row['blood_type']),
                        _detailLine('家族構成', row['family_composition']),
                        const Divider(),
                        _detailLine('緊急連絡先 関係', row['emergency_relation']),
                        _detailLine('緊急連絡先 名前', row['emergency_name']),
                        _detailLine('緊急連絡先 電話', row['emergency_phone']),
                        _detailLine('緊急連絡先 住所', row['emergency_address']),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _imagePreview(
                  '本人写真',
                  row['portrait_path']?.toString(),
                ),
                _imagePreview(
                  'マイナンバーカード 表面',
                  row['my_number_front_path']?.toString(),
                ),
                _imagePreview(
                  'マイナンバーカード 裏面',
                  row['my_number_back_path']?.toString(),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _approve(row);
                  },
                  icon: const Icon(Icons.verified_user_outlined),
                  label: const Text('本登録'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '従業員の本登録承認',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: '再読み込み',
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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _load,
                            child: const Text('再試行'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _rows.isEmpty
                    ? const Center(
                        child: Text(
                          '本登録待ちはありません',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _rows.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final row = _rows[index];
                          return Card(
                            child: ListTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.person_add_alt_1),
                              ),
                              title: Text(
                                row['name']?.toString() ?? '従業員',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              subtitle: Text(
                                row['phone']?.toString() ?? '',
                              ),
                              trailing: FilledButton(
                                onPressed: () => _openDetails(row),
                                child: const Text('確認'),
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
