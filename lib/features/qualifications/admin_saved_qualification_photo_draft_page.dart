import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'admin_saved_qualification_photo_contract.dart';
import 'admin_saved_qualification_photo_draft.dart';

export 'admin_saved_qualification_photo_draft.dart' show AdminSavedQualificationPhotoDraft;

@immutable
class AdminSavedQualificationPhotoScope {
  const AdminSavedQualificationPhotoScope({this.companyId, this.actorId});
  final String? companyId;
  final String? actorId;
}

/// Isolated draft UI; no live screen currently opens this page.
/// The caller supplies an exact trusted baseline and current identity scope.
class AdminSavedQualificationPhotoDraftPage extends StatefulWidget {
  const AdminSavedQualificationPhotoDraftPage({
    super.key,
    required this.capability,
    required this.companyId,
    required this.actorId,
    required this.targetId,
    required this.savedPaths,
    required this.scope,
    this.initialSelection,
    this.photoBuilder,
  });

  final AdminSavedQualificationPhotoCapability capability;
  final String companyId;
  final String actorId;
  final String targetId;
  final List<String> savedPaths;
  final List<String>? initialSelection;
  final ValueListenable<AdminSavedQualificationPhotoScope> scope;

  /// Existing photo renderer only. This page requests no URLs or media itself.
  final Widget Function(BuildContext context, String savedPath)? photoBuilder;

  @override
  State<AdminSavedQualificationPhotoDraftPage> createState() =>
      _AdminSavedQualificationPhotoDraftPageState();
}

class _AdminSavedQualificationPhotoDraftPageState
    extends State<AdminSavedQualificationPhotoDraftPage> {
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  late final List<String> _baseline;
  late List<String> _selection;
  bool _invalid = false;

  bool get _scopeMatches =>
      listEquals(_baseline, widget.savedPaths) &&
      widget.capability.available &&
      widget.capability.matchesScope(
        companyId: widget.companyId,
        actorId: widget.actorId,
      ) &&
      widget.scope.value.companyId == widget.companyId &&
      widget.scope.value.actorId == widget.actorId;

  bool _validPaths(List<String> paths, {required bool baseline}) {
    if (paths.length > widget.capability.maxPhotos ||
        paths.length > 20 ||
        (baseline && paths.isEmpty) ||
        paths.toSet().length != paths.length ||
        paths.any((path) => path.trim().isEmpty)) {
      return false;
    }
    return baseline || paths.every(_baseline.contains);
  }

  @override
  void initState() {
    super.initState();
    _baseline = List.unmodifiable(widget.savedPaths);
    _selection = List.of(widget.initialSelection ?? _baseline);
    _invalid =
        !_uuid.hasMatch(widget.targetId) ||
        !_scopeMatches ||
        !_validPaths(_baseline, baseline: true) ||
        !_validPaths(_selection, baseline: false);
    if (_invalid) _selection = [];
    widget.scope.addListener(_scopeChanged);
  }

  void _scopeChanged() {
    if (_invalid || _scopeMatches || !mounted) return;
    setState(() {
      _invalid = true;
      _selection = [];
    });
  }

  @override
  void didUpdateWidget(
    covariant AdminSavedQualificationPhotoDraftPage oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope) {
      oldWidget.scope.removeListener(_scopeChanged);
      widget.scope.addListener(_scopeChanged);
    }
    if (!_scopeMatches ||
        oldWidget.companyId != widget.companyId ||
        oldWidget.actorId != widget.actorId ||
        oldWidget.targetId != widget.targetId ||
        !listEquals(_baseline, widget.savedPaths) ||
        !listEquals(oldWidget.initialSelection, widget.initialSelection) ||
        oldWidget.scope != widget.scope) {
      _invalid = true;
      _selection = [];
    }
  }

  @override
  void dispose() {
    widget.scope.removeListener(_scopeChanged);
    super.dispose();
  }

  void _move(int from, int to) {
    if (_invalid || !_scopeMatches) {
      _scopeChanged();
      return;
    }
    setState(() => _selection.insert(to, _selection.removeAt(from)));
  }

  void _confirm() {
    if (_invalid ||
        !_scopeMatches ||
        !_validPaths(_selection, baseline: false)) {
      _scopeChanged();
      return;
    }
    Navigator.of(context).pop(
      AdminSavedQualificationPhotoDraft(
        companyId: widget.companyId,
        actorId: widget.actorId,
        targetId: widget.targetId,
        savedPaths: _baseline,
        selectedPaths: _selection,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allowed = !_invalid && _scopeMatches;
    return Scaffold(
      appBar: AppBar(title: const Text('資格写真の変更内容')),
      body: !allowed
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('写真やログイン状態を確認できません。元の画面から開き直してください。'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('保存済み写真の順番や、残す写真を選びます。ここでは変更申請を送信しません。'),
                const SizedBox(height: 12),
                if (_selection.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('すべての写真を変更対象から外しています。正式な写真はまだ変更されません。'),
                  ),
                for (var index = 0; index < _selection.length; index++)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('写真 ${index + 1}'),
                          SizedBox(
                            height: 120,
                            child:
                                widget.photoBuilder?.call(
                                  context,
                                  _selection[index],
                                ) ??
                                const Center(
                                  child: Icon(Icons.image_outlined, size: 48),
                                ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                tooltip: '写真 ${index + 1} を上へ',
                                onPressed: index > 0
                                    ? () => _move(index, index - 1)
                                    : null,
                                icon: const Icon(Icons.arrow_upward),
                              ),
                              IconButton(
                                tooltip: '写真 ${index + 1} を下へ',
                                onPressed: index < _selection.length - 1
                                    ? () => _move(index, index + 1)
                                    : null,
                                icon: const Icon(Icons.arrow_downward),
                              ),
                              TextButton(
                                onPressed: () {
                                  if (_invalid || !_scopeMatches) {
                                    _scopeChanged();
                                    return;
                                  }
                                  setState(() => _selection.removeAt(index));
                                },
                                child: const Text('選択から外す'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                if (!listEquals(_selection, _baseline))
                  TextButton(
                    onPressed: () {
                      if (_invalid || !_scopeMatches) {
                        _scopeChanged();
                        return;
                      }
                      setState(() => _selection = List.of(_baseline));
                    },
                    child: const Text('元の選択に戻す'),
                  ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('キャンセル'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: allowed ? _confirm : null,
                  child: const Text('選択を確認'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
