import 'package:flutter/material.dart';

import 'qualification_recognition_matcher.dart';

class QualificationRecognitionReviewResult {
  const QualificationRecognitionReviewResult({
    required this.qualificationMasterId,
    required this.qualificationName,
    required this.personName,
    required this.expiresAt,
    required this.certificateNumber,
  });

  final String? qualificationMasterId;
  final String qualificationName;
  final String personName;
  final DateTime? expiresAt;
  final String certificateNumber;
}

class QualificationRecognitionReviewPage extends StatefulWidget {
  const QualificationRecognitionReviewPage({
    super.key,
    required this.candidate,
  });

  final QualificationRecognitionCandidate candidate;

  @override
  State<QualificationRecognitionReviewPage> createState() =>
      _QualificationRecognitionReviewPageState();
}

class _QualificationRecognitionReviewPageState
    extends State<QualificationRecognitionReviewPage> {
  late final TextEditingController _qualificationName;
  late final TextEditingController _personName;
  late final TextEditingController _certificateNumber;
  String? _selectedMasterId;
  DateTime? _expiresAt;

  @override
  void initState() {
    super.initState();
    final first = widget.candidate.qualificationCandidates.isEmpty
        ? null
        : widget.candidate.qualificationCandidates.first;
    _selectedMasterId = first?.masterId;
    _qualificationName =
        TextEditingController(text: first?.canonicalName ?? '');
    _personName =
        TextEditingController(text: widget.candidate.personName ?? '');
    _certificateNumber =
        TextEditingController(text: widget.candidate.certificateNumber ?? '');
    _expiresAt = widget.candidate.expiresAt;
  }

  @override
  void dispose() {
    _qualificationName.dispose();
    _personName.dispose();
    _certificateNumber.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final candidates = widget.candidate.qualificationCandidates;

    return Scaffold(
      appBar: AppBar(title: const Text('資格証の読み取り内容を確認')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '画像から読み取った内容は候補です。登録前に必ず資格名・氏名・期限等を確認してください。',
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (candidates.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                initialValue: _selectedMasterId,
                decoration: const InputDecoration(
                  labelText: '資格マスター候補',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                items: [
                  for (final item in candidates)
                    DropdownMenuItem(
                      value: item.masterId,
                      child: Text(item.canonicalName),
                    ),
                ],
                onChanged: (selectedId) {
                  final selected = candidates.where(
                    (item) => item.masterId == selectedId,
                  );
                  setState(() {
                    _selectedMasterId = selectedId;
                    if (selected.isNotEmpty) {
                      _qualificationName.text =
                          selected.first.canonicalName;
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _qualificationName,
              decoration: const InputDecoration(
                labelText: '資格名 *',
                helperText: '候補がない場合は読み取り結果を修正して入力',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _personName,
              decoration: const InputDecoration(labelText: '氏名'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _certificateNumber,
              decoration: const InputDecoration(labelText: '証明書番号'),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('有効期限'),
              subtitle: Text(
                _expiresAt == null ? '読み取りなし / 設定なし' : _format(_expiresAt!),
              ),
              trailing: const Icon(Icons.calendar_month_outlined),
              onTap: _pickExpiry,
            ),
            const SizedBox(height: 18),
            ExpansionTile(
              title: const Text('読み取り元テキストを確認'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(widget.candidate.rawText),
                ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('この内容で登録へ進む'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? now,
      firstDate: DateTime(1950),
      lastDate: DateTime(now.year + 50),
    );
    if (picked != null && mounted) {
      setState(() => _expiresAt = picked);
    }
  }

  void _submit() {
    final qualificationName = _qualificationName.text.trim();
    if (qualificationName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('資格名を確認してください')),
      );
      return;
    }

    Navigator.of(context).pop(
      QualificationRecognitionReviewResult(
        qualificationMasterId: _selectedMasterId,
        qualificationName: qualificationName,
        personName: _personName.text.trim(),
        expiresAt: _expiresAt,
        certificateNumber: _certificateNumber.text.trim(),
      ),
    );
  }

  String _format(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return date.year.toString() + '/' + month + '/' + day;
  }
}
