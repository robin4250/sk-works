import 'package:flutter/material.dart';
import 'own_published_shift_repository.dart';
import 'own_published_shift_view.dart';

class OwnPublishedShiftPage extends StatefulWidget {
  const OwnPublishedShiftPage({super.key, required this.month});
  final DateTime month;
  @override
  State<OwnPublishedShiftPage> createState() => _OwnPublishedShiftPageState();
}

class _OwnPublishedShiftPageState extends State<OwnPublishedShiftPage> {
  final _repository = ownShiftEntryReleased ? OwnPublishedShiftRepository.maybeCreate() : null;
  Future<OwnShiftContext>? _context;
  @override
  void initState() {
    super.initState();
    _reload();
  }
  void _reload() {
    if (!ownShiftEntryReleased) return;
    _context = _repository?.loadContext() ?? Future.error(StateError('ログインを確認してください。'));
  }
  @override
  void dispose() {
    _repository?.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('シフト予定')),
    body: !ownShiftEntryReleased ? const Center(child: Text('準備中です。')) :
      FutureBuilder<OwnShiftContext>(key: ObjectKey(_context), future: _context,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('シフトを確認できません。'),
            TextButton(onPressed: () => setState(_reload), child: const Text('再読み込み')),
          ]));
          final data = snapshot.data;
          if (data == null) return const Center(child: CircularProgressIndicator());
          return SingleChildScrollView(padding: const EdgeInsets.all(12), child: OwnPublishedShiftView(
            gateway: data.gateway, companyId: data.companyId,
            month: widget.month, siteNames: data.siteNames));
        }),
  );
}
