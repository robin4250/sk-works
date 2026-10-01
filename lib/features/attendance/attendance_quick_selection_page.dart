import 'package:flutter/material.dart';

import 'attendance_verification_repository.dart';

class AttendanceQuickSelectionPage extends StatefulWidget {
  const AttendanceQuickSelectionPage({super.key});

  @override
  State<AttendanceQuickSelectionPage> createState() =>
      _AttendanceQuickSelectionPageState();
}

class _AttendanceQuickSelectionPageState
    extends State<AttendanceQuickSelectionPage> {
  final _repository = AttendanceVerificationRepository.maybeCreate();

  List<Map<String, dynamic>> _sites = const [];
  String _mode = 'manual';
  int _radiusM = 300;
  String? _siteId;
  bool _canManage = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'クラウド接続を確認できません。';
      });
      return;
    }

    try {
      final settings = await repository.loadSettings();
      final sites = await repository.loadSites();
      final preferredSiteId = await repository.loadPreferredSiteId();
      final canManage = await repository.canManageAttendance();

      if (!mounted) return;
      setState(() {
        _mode = settings['mode']?.toString() ?? 'manual';
        _radiusM = (settings['proximity_radius_m'] as num?)?.toInt() ?? 300;
        _sites = sites;
        _siteId = sites.any((site) => site['id']?.toString() == preferredSiteId)
            ? preferredSiteId
            : null;
        _canManage = canManage;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _save() async {
    final repository = _repository;
    if (repository == null || _saving) return;

    setState(() => _saving = true);
    try {
      await repository.savePreferredSiteId(_siteId);
      if (_canManage) {
        await repository.saveSettings(
          mode: _mode,
          proximityRadiusM: _radiusM,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存できませんでした: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '出勤方法と現場',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorState(message: _error!, onRetry: _load)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                    children: [
                      Text(
                        '出勤方法',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _mode,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.verified_user_outlined),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'manual',
                            child: Text('手動'),
                          ),
                          DropdownMenuItem(
                            value: 'location',
                            child: Text('位置情報'),
                          ),
                          DropdownMenuItem(
                            value: 'location_photo',
                            child: Text('位置情報＋写真'),
                          ),
                        ],
                        onChanged: _canManage && !_saving
                            ? (value) {
                                if (value == null) return;
                                setState(() => _mode = value);
                              }
                            : null,
                      ),
                      if (!_canManage) ...[
                        const SizedBox(height: 6),
                        const Text(
                          '出勤方法は会社設定です。変更できるのは管理権限があるユーザーだけです。',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Text(
                        '現場',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _siteId,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.business_outlined),
                          hintText: '現場を選択',
                        ),
                        items: [
                          for (final site in _sites)
                            DropdownMenuItem<String>(
                              value: site['id']?.toString(),
                              child: Text(
                                site['name']?.toString() ?? '名称未登録',
                              ),
                            ),
                        ],
                        onChanged: _saving
                            ? null
                            : (value) => setState(() => _siteId = value),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.check),
                        label: Text(_saving ? '保存中…' : '選択を保存'),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 42),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('再試行'),
            ),
          ],
        ),
      ),
    );
  }
}
