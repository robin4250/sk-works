import 'package:flutter/material.dart';

import 'qualification_master_candidate_repository.dart';
import 'qualification_master_candidate_service.dart';

class QualificationMasterCandidateReviewPage extends StatefulWidget {
  const QualificationMasterCandidateReviewPage({
    super.key,
    required this.candidates,
  });

  final List<QualificationMasterCandidate> candidates;

  @override
  State<QualificationMasterCandidateReviewPage> createState() =>
      _QualificationMasterCandidateReviewPageState();
}

class _QualificationMasterCandidateReviewPageState
    extends State<QualificationMasterCandidateReviewPage> {
  final _repository = QualificationMasterCandidateRepository.maybeCreate();
  final _done = <int>{};
  int? _busyIndex;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('資格マスター候補を確認')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '読み取り結果を自動登録はしません。同一資格・表記揺れを確認し、既存資格の別名にするか、新しい資格マスターとして作成するかを選んでください。',
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (widget.candidates.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('確認が必要な資格候補はありません'),
                ),
              ),
            for (var index = 0;
                index < widget.candidates.length;
                index++)
              _candidateCard(index, widget.candidates[index]),
          ],
        ),
      ),
    );
  }

  Widget _candidateCard(
    int index,
    QualificationMasterCandidate candidate,
  ) {
    final completed = _done.contains(index);
    final busy = _busyIndex == index;
    final existing = candidate.existingMasterId != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    candidate.canonicalName,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                if (completed)
                  const Icon(Icons.check_circle, semanticLabel: '確認済み'),
              ],
            ),
            const SizedBox(height: 6),
            Text('読み取り ' + candidate.occurrences.toString() + '件'),
            if (existing) ...[
              const SizedBox(height: 4),
              Text(
                '既存資格: ' + (candidate.existingMasterName ?? ''),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final variant in candidate.variants)
                  Chip(label: Text(variant)),
              ],
            ),
            const SizedBox(height: 12),
            if (!completed)
              FilledButton.icon(
                onPressed: busy ? null : () => _review(index, candidate),
                icon: Icon(
                  existing ? Icons.merge_type : Icons.library_add_outlined,
                ),
                label: Text(
                  existing ? '既存資格の別名候補として確認' : '新規資格として確認',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _review(
    int index,
    QualificationMasterCandidate candidate,
  ) async {
    final repository = _repository;
    if (repository == null) return;
    final existing = candidate.existingMasterId != null;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(existing ? '既存資格にまとめますか？' : '新しい資格を作りますか？'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (existing)
                Text('資格マスター: ' + (candidate.existingMasterName ?? ''))
              else
                Text('新規資格名: ' + candidate.canonicalName),
              const SizedBox(height: 10),
              const Text('読み取り表記:'),
              for (final variant in candidate.variants) Text('・' + variant),
              const SizedBox(height: 12),
              const Text('確定後も元の資格証画像・読み取り結果は別データとして扱い、資格マスター名を勝手に上書きしません。'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(existing ? '別名として登録' : '新規資格を作成'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyIndex = index);
    try {
      if (existing) {
        await repository.addAliases(
          masterId: candidate.existingMasterId!,
          aliases: candidate.variants,
        );
      } else {
        await repository.createMaster(
          name: candidate.canonicalName,
          aliases: candidate.variants,
        );
      }
      if (!mounted) return;
      setState(() => _done.add(index));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('資格マスター候補を反映しました')),
      );
    } finally {
      if (mounted) setState(() => _busyIndex = null);
    }
  }
}
