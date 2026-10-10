import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'qualification_photo_submission_review_repository.dart';

class QualificationPhotoSubmissionReviewPage extends StatefulWidget {
  const QualificationPhotoSubmissionReviewPage({super.key});
  @override
  State<QualificationPhotoSubmissionReviewPage> createState() => _ReviewState();
}

class _ReviewState extends State<QualificationPhotoSubmissionReviewPage> {
  final _repository =
      QualificationPhotoSubmissionReviewRepository.maybeCreate();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  final Map<String, Map<String, dynamic>> _uncertain = {};
  String? _actor;
  @override
  void initState() {
    super.initState();
    _actor = _repository?.client.auth.currentUser?.id;
    _load();
  }

  void _checkActor() {
    final actor = _actor;
    if (actor == null || _repository?.client.auth.currentUser?.id != actor) {
      throw StateError('ログインが変更されました。画面を開き直してください。');
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = _repository;
      if (repository == null) throw StateError('SKOへのログインが必要です。');
      _checkActor();
      final items = await repository.pending();
      for (final entry in _uncertain.entries.toList()) {
        try {
          final status = await repository.confirmedStatus(entry.value);
          _checkActor();
          if (status != null) {
            _uncertain.remove(entry.key);
            if (status != 'pending') _message('申請の状態を確認しました：$status');
          }
        } catch (_) {}
      }
      for (final row in _uncertain.values) {
        if (!items.any((item) => item['id'] == row['id'])) items.add(row);
      }
      _checkActor();
      if (mounted) {
        setState(() {
          _items = items;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    }
    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _open(Map<String, dynamic> row) async {
    setState(() {
      _busy = true;
    });
    try {
      _checkActor();
      final paths = await _repository!.photos(row);
      _checkActor();
      if (paths.isEmpty) {
        _message('登録済みの資格写真をすべて削除する申請です。');
      }
      final urls = await Future.wait(paths.map(_repository!.signedUrl));
      _checkActor();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text('資格申請の写真')),
            body: urls.isEmpty
                ? const Center(child: Text('登録済みの資格写真をすべて削除する申請です。'))
                : ListView.builder(
                    itemCount: urls.length,
                    itemBuilder: (context, index) => Column(
                      children: [
                        Text('${index + 1} / ${urls.length}'),
                        if (paths[index].toLowerCase().endsWith('.pdf'))
                          TextButton(
                            onPressed: () async {
                              _checkActor();
                              if (!await launchUrl(
                                Uri.parse(urls[index]),
                                mode: LaunchMode.externalApplication,
                              )) {
                                _message('PDFを開けませんでした。');
                              }
                            },
                            child: const Text('PDFを確認'),
                          )
                        else
                          SizedBox(
                            height: 400,
                            child: InteractiveViewer(
                              child: Image.network(
                                urls[index],
                                fit: BoxFit.contain,
                                errorBuilder: (_, error, stack) =>
                                    const Text('写真を取得できません。一覧から開き直してください。'),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ),
      );
    } catch (e) {
      _message(e.toString());
    }
    if (mounted) {
      setState(() {
        _busy = false;
      });
    }
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _review(Map<String, dynamic> row, bool approve) async {
    try {
      _checkActor();
    } catch (e) {
      _message(e.toString());
      return;
    }
    String? reason;
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approve ? '資格申請を承認しますか？' : '資格申請を却下しますか？'),
        content: approve
            ? Text(
                QualificationPhotoSubmissionReviewRepository.paths(row).isEmpty
                    ? '登録済みの資格写真をすべて削除する申請を承認します。'
                    : '登録済みの資格写真へ申請内容を反映します。',
              )
            : TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: '却下理由（必須）'),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () {
              if (!approve && controller.text.trim().isEmpty) return;
              reason = controller.text.trim();
              Navigator.pop(context, true);
            },
            child: Text(approve ? '承認' : '却下'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
    });
    try {
      _checkActor();
      await _repository!.review(row, approve: approve, reason: reason);
      _checkActor();
      _message(approve ? '承認しました。' : '却下しました。');
    } catch (e) {
      if (e is QualificationReviewUncertain) {
        _uncertain[row['id'].toString()] = row;
      }
      _message(e.toString());
    }
    if (mounted) {
      setState(() {
        _busy = false;
      });
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('資格写真の承認待ち'),
      actions: [
        IconButton(
          onPressed: _busy || _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!),
                TextButton(onPressed: _load, child: const Text('再読み込み')),
              ],
            ),
          )
        : _items.isEmpty
        ? const Center(child: Text('承認できる申請はありません。'))
        : ListView(
            children: _items
                .map(
                  (row) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${row['worker_name'] ?? ''} / ${row['qualification_name'] ?? ''}',
                          ),
                          TextButton(
                            onPressed: _busy ? null : () => _open(row),
                            child: const Text('申請写真をすべて確認'),
                          ),
                          if (_uncertain.containsKey(row['id'].toString()))
                            const Text('操作結果が不明です。再操作せず管理者へ確認してください。'),
                          Row(
                            children: [
                              TextButton(
                                onPressed:
                                    _busy ||
                                        _uncertain.containsKey(
                                          row['id'].toString(),
                                        )
                                    ? null
                                    : () => _review(row, true),
                                child: const Text('承認'),
                              ),
                              TextButton(
                                onPressed:
                                    _busy ||
                                        _uncertain.containsKey(
                                          row['id'].toString(),
                                        )
                                    ? null
                                    : () => _review(row, false),
                                child: const Text('却下'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
  );
}
